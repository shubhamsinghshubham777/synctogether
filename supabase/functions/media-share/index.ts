// Consolidated Edge Function router for Cloudflare R2 Media Sharing
import { createClient } from "npm:@supabase/supabase-js@2.58.0";
import {
  S3Client,
  CreateMultipartUploadCommand,
  UploadPartCommand,
  ListPartsCommand,
  CompleteMultipartUploadCommand,
  AbortMultipartUploadCommand,
  GetObjectCommand,
  HeadObjectCommand,
} from "npm:@aws-sdk/client-s3";
import { getSignedUrl } from "npm:@aws-sdk/s3-request-presigner";

const s3 = new S3Client({
  region: "auto",
  endpoint: Deno.env.get("CF_R2_ENDPOINT") || "https://dummy.r2.cloudflarestorage.com",
  credentials: {
    accessKeyId: Deno.env.get("CF_R2_ACCESS_KEY_ID") || "dummy_key",
    secretAccessKey: Deno.env.get("CF_R2_SECRET_ACCESS_KEY") || "dummy_secret",
  },
});

const bucketName = Deno.env.get("CF_R2_BUCKET_NAME") || "synctogether-media";

// Service role client for privileged DB mutations
const supabaseAdmin = createClient(
  Deno.env.get("SUPABASE_URL") || "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "",
);

const kPartSizeBytes = 10485760; // 10 MB chunks

// Nothing the client echoes back after `initiate` is trusted. The slot RPC
// already priced the upload against the caller's tier and wrote the key, the
// upload id and the declared size to a row; every later step reads that row.
// Taking `r2Key`/`uploadId`/`fileSize` from the body let a free account
// declare 10 MB, upload 10 GB (or write to any key in the bucket) and be
// debited for 10 MB.
type UploadSlot = { r2Key: string; uploadId: string; declaredSize: number };

async function roomUploadSlot(roomId: string): Promise<UploadSlot | null> {
  const { data } = await supabaseAdmin
    .from("rooms")
    .select("media_r2_key, media_upload_id, media_file_size, media_upload_state")
    .eq("id", roomId)
    .maybeSingle();
  if (!data || data.media_upload_state !== "uploading" || !data.media_r2_key || !data.media_upload_id) {
    return null;
  }
  return { r2Key: data.media_r2_key, uploadId: data.media_upload_id, declaredSize: Number(data.media_file_size) };
}

async function stagedUploadSlot(stagedId: string, userId: string): Promise<UploadSlot | null> {
  const { data } = await supabaseAdmin
    .from("staged_media_uploads")
    .select("user_id, r2_key, upload_id, file_size, upload_state")
    .eq("id", stagedId)
    .maybeSingle();
  if (!data || data.user_id !== userId || data.upload_state !== "uploading" || !data.r2_key || !data.upload_id) {
    return null;
  }
  return { r2Key: data.r2_key, uploadId: data.upload_id, declaredSize: Number(data.file_size) };
}

// The client still sends the key and upload id it was given; a mismatch means
// it is addressing somebody else's upload.
function slotMatches(slot: UploadSlot, body: Record<string, unknown>): boolean {
  const r2Key = body.r2Key ?? body.r2_key;
  const uploadId = body.uploadId ?? body.upload_id;
  return (r2Key === undefined || r2Key === slot.r2Key) && (uploadId === undefined || uploadId === slot.uploadId);
}

function partsWithinSlot(partNumbers: unknown[], slot: UploadSlot): boolean {
  const maxPart = Math.max(1, Math.ceil(slot.declaredSize / kPartSizeBytes));
  return partNumbers.length <= maxPart &&
    partNumbers.every((n) => Number.isInteger(n) && (n as number) >= 1 && (n as number) <= maxPart);
}

// Part URLs bound the part *count*, not each part's size, so the assembled
// object is measured before anything is debited or marked ready.
async function storedObjectSize(r2Key: string): Promise<number | null> {
  try {
    const head = await s3.send(new HeadObjectCommand({ Bucket: bucketName, Key: r2Key }));
    return head.ContentLength ?? null;
  } catch (_) {
    return null;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders() });
  }

  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return json({ error: "not_authenticated" }, 401);
  }

  const userClient = createClient(
    Deno.env.get("SUPABASE_URL") || "",
    Deno.env.get("SUPABASE_ANON_KEY") || "",
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: userData, error: userError } = await userClient.auth.getUser();
  const user = userData?.user;
  if (userError || !user) {
    return json({ error: "not_authenticated" }, 401);
  }

  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_body" }, 400);
  }

  const url = new URL(req.url);
  const actionFromPath = url.pathname.split("/").pop();
  const action = (body.action as string) || actionFromPath;

  try {
    switch (action) {
      case "initiate":
        return await handleInitiate(user.id, body);
      case "part-urls":
        return await handlePartUrls(user.id, body);
      case "list-parts":
        return await handleListParts(user.id, body);
      case "complete":
        return await handleComplete(user.id, body);
      case "abort":
        return await handleAbort(user.id, body);
      case "download-url":
        return await handleDownloadUrl(user.id, body);
      case "staged-initiate":
        return await handleStagedInitiate(user.id, body);
      case "staged-part-urls":
        return await handleStagedPartUrls(user.id, body);
      case "staged-list-parts":
        return await handleStagedListParts(user.id, body);
      case "staged-complete":
        return await handleStagedComplete(user.id, body);
      case "staged-abort":
        return await handleStagedAbort(user.id, body);
      default:
        return json({ error: "unknown_action" }, 400);
    }
  } catch (err: unknown) {
    const error = err as Error;
    return json({ error: error.message || "internal_error" }, 500);
  }
});

async function verifyHost(roomId: string, userId: string): Promise<boolean> {
  const { data: room, error: roomError } = await supabaseAdmin
    .from("rooms")
    .select("id, created_by, ended_at, expires_at")
    .eq("id", roomId)
    .maybeSingle();

  if (roomError || !room) return false;
  if (room.ended_at !== null || new Date(room.expires_at) <= new Date()) {
    return false;
  }

  if (room.created_by === userId) {
    return true;
  }

  const { data: member } = await supabaseAdmin
    .from("room_members")
    .select("role")
    .eq("room_id", roomId)
    .eq("user_id", userId)
    .eq("role", "host")
    .maybeSingle();

  return !!member;
}

async function verifyMember(roomId: string, userId: string): Promise<{
  isMember: boolean;
  room?: {
    ended_at: string | null;
    expires_at: string;
    media_r2_key: string | null;
    media_name: string | null;
    media_file_size: number | null;
    media_upload_state: string;
  };
}> {
  const { data: room, error: roomError } = await supabaseAdmin
    .from("rooms")
    .select("id, created_by, ended_at, expires_at, media_r2_key, media_name, media_file_size, media_upload_state")
    .eq("id", roomId)
    .maybeSingle();

  if (roomError || !room) return { isMember: false };
  if (room.ended_at !== null || new Date(room.expires_at) <= new Date()) {
    return { isMember: false };
  }

  if (room.created_by === userId) {
    return { isMember: true, room };
  }

  const { data: member } = await supabaseAdmin
    .from("room_members")
    .select("role")
    .eq("room_id", roomId)
    .eq("user_id", userId)
    .maybeSingle();

  if (!member) return { isMember: false };
  return { isMember: true, room };
}

async function handleInitiate(userId: string, body: Record<string, unknown>): Promise<Response> {
  const roomId = (body.roomId || body.room_id) as string;
  const fileName = ((body.fileName || body.file_name) as string)?.trim();
  const fileSize = Number(body.fileSize || body.file_size);
  const contentType = (body.contentType || body.content_type || "video/mp4") as string;

  if (!roomId || !fileName || !fileSize || fileSize <= 0) {
    return json({ error: "invalid_arguments" }, 400);
  }

  if (!contentType.startsWith("video/")) {
    return json({ error: "invalid_content_type" }, 400);
  }

  const isHost = await verifyHost(roomId, userId);
  if (!isHost) {
    return json({ error: "not_host" }, 403);
  }

  const safeFileName = fileName.replace(/[^a-zA-Z0-9._-]/g, "_");
  const r2Key = `rooms/${roomId}/${crypto.randomUUID()}-${safeFileName}`;
  const totalParts = fileSize <= kPartSizeBytes ? 1 : Math.ceil(fileSize / kPartSizeBytes);

  let uploadId: string;
  try {
    const createRes = await s3.send(
      new CreateMultipartUploadCommand({
        Bucket: bucketName,
        Key: r2Key,
        ContentType: contentType,
      }),
    );
    uploadId = createRes.UploadId!;
    if (!uploadId) throw new Error("failed_to_create_multipart");
  } catch (err: unknown) {
    const e = err as Error;
    return json({ error: "s3_initiate_failed", details: e.message }, 502);
  }

  const { error: rpcError } = await supabaseAdmin.rpc("request_upload_slot", {
    p_room_id: roomId,
    p_user_id: userId,
    p_file_size: fileSize,
    p_r2_key: r2Key,
    p_upload_id: uploadId,
  });

  if (rpcError) {
    try {
      await s3.send(
        new AbortMultipartUploadCommand({
          Bucket: bucketName,
          Key: r2Key,
          UploadId: uploadId,
        }),
      );
    } catch (_) {}
    return json({ error: rpcError.message }, 400);
  }

  return json({
    uploadId,
    r2Key,
    partSizeBytes: kPartSizeBytes,
    totalParts,
  });
}

async function handlePartUrls(userId: string, body: Record<string, unknown>): Promise<Response> {
  const roomId = (body.roomId || body.room_id) as string;
  const partNumbers = (body.partNumbers || body.part_numbers) as number[];

  if (!roomId || !Array.isArray(partNumbers) || partNumbers.length === 0) {
    return json({ error: "invalid_arguments" }, 400);
  }

  const isHost = await verifyHost(roomId, userId);
  if (!isHost) {
    return json({ error: "not_host" }, 403);
  }

  const slot = await roomUploadSlot(roomId);
  if (!slot || !slotMatches(slot, body)) {
    return json({ error: "upload_slot_mismatch" }, 403);
  }
  if (!partsWithinSlot(partNumbers, slot)) {
    return json({ error: "invalid_part_numbers" }, 400);
  }

  const parts = await Promise.all(
    partNumbers.map(async (partNumber) => {
      const command = new UploadPartCommand({
        Bucket: bucketName,
        Key: slot.r2Key,
        UploadId: slot.uploadId,
        PartNumber: partNumber,
      });
      const url = await getSignedUrl(s3, command, { expiresIn: 1800 });
      return { partNumber, url };
    }),
  );

  return json({ parts });
}

async function handleListParts(userId: string, body: Record<string, unknown>): Promise<Response> {
  const roomId = (body.roomId || body.room_id) as string;

  if (!roomId) {
    return json({ error: "invalid_arguments" }, 400);
  }

  const isHost = await verifyHost(roomId, userId);
  if (!isHost) {
    return json({ error: "not_host" }, 403);
  }

  const slot = await roomUploadSlot(roomId);
  if (!slot || !slotMatches(slot, body)) {
    return json({ error: "upload_slot_mismatch" }, 403);
  }

  try {
    const res = await s3.send(
      new ListPartsCommand({
        Bucket: bucketName,
        Key: slot.r2Key,
        UploadId: slot.uploadId,
      }),
    );

    const parts = (res.Parts ?? []).map((p) => ({
      partNumber: p.PartNumber,
      etag: (p.ETag ?? "").replace(/^"|"$/g, "").trim(),
      size: p.Size,
    }));

    return json({ parts });
  } catch (err: unknown) {
    const e = err as Error;
    return json({ error: "s3_list_parts_failed", details: e.message }, 502);
  }
}

async function handleComplete(userId: string, body: Record<string, unknown>): Promise<Response> {
  const roomId = (body.roomId || body.room_id) as string;
  const rawParts = body.parts as Array<{ partNumber: number; etag: string }>;

  if (!roomId || !Array.isArray(rawParts) || rawParts.length === 0) {
    return json({ error: "invalid_arguments" }, 400);
  }

  const isHost = await verifyHost(roomId, userId);
  if (!isHost) {
    return json({ error: "not_host" }, 403);
  }

  const slot = await roomUploadSlot(roomId);
  if (!slot || !slotMatches(slot, body)) {
    return json({ error: "upload_slot_mismatch" }, 403);
  }
  if (!partsWithinSlot(rawParts.map((p) => p.partNumber), slot)) {
    return json({ error: "invalid_part_numbers" }, 400);
  }

  const sortedParts = [...rawParts]
    .sort((a, b) => a.partNumber - b.partNumber)
    .map((p) => ({
      PartNumber: p.partNumber,
      ETag: p.etag.replace(/^"|"$/g, "").trim(),
    }));

  try {
    await s3.send(
      new CompleteMultipartUploadCommand({
        Bucket: bucketName,
        Key: slot.r2Key,
        UploadId: slot.uploadId,
        MultipartUpload: { Parts: sortedParts },
      }),
    );
  } catch (err: unknown) {
    const e = err as Error;
    return json({ error: "s3_complete_failed", details: e.message }, 502);
  }

  const storedSize = await storedObjectSize(slot.r2Key);
  if (storedSize === null || storedSize > slot.declaredSize) {
    // `failed` queues the object for deletion, so the oversize bytes do not
    // linger in the bucket.
    await supabaseAdmin.rpc("set_media_upload_state", {
      p_room_id: roomId,
      p_user_id: userId,
      p_state: "failed",
      p_r2_key: slot.r2Key,
      p_bytes_uploaded: storedSize ?? 0,
    });
    return json({ error: "upload_size_mismatch" }, 400);
  }

  const { error: rpcError } = await supabaseAdmin.rpc("set_media_upload_state", {
    p_room_id: roomId,
    p_user_id: userId,
    p_state: "ready",
    p_file_size: storedSize,
    p_r2_key: slot.r2Key,
    p_bytes_uploaded: storedSize,
  });

  if (rpcError) {
    return json({ error: rpcError.message }, 500);
  }

  return json({ success: true, state: "ready" });
}

async function handleAbort(userId: string, body: Record<string, unknown>): Promise<Response> {
  const roomId = (body.roomId || body.room_id) as string;
  const bytesUploaded = Number(body.bytesUploaded ?? body.bytes_uploaded ?? 0);

  if (!roomId) {
    return json({ error: "invalid_arguments" }, 400);
  }

  const isHost = await verifyHost(roomId, userId);
  if (!isHost) {
    return json({ error: "not_host" }, 403);
  }

  const slot = await roomUploadSlot(roomId);
  if (slot && slotMatches(slot, body)) {
    try {
      await s3.send(
        new AbortMultipartUploadCommand({
          Bucket: bucketName,
          Key: slot.r2Key,
          UploadId: slot.uploadId,
        }),
      );
    } catch (_) {}
  }

  await supabaseAdmin.rpc("clear_media_sharing", {
    p_room_id: roomId,
    p_bytes_uploaded: bytesUploaded,
  });

  return json({ success: true });
}

async function handleStagedInitiate(userId: string, body: Record<string, unknown>): Promise<Response> {
  const fileName = ((body.fileName || body.file_name) as string)?.trim();
  const fileSize = Number(body.fileSize || body.file_size);
  const durationMs = (body.durationMs || body.duration_ms) ? Number(body.durationMs || body.duration_ms) : null;
  const contentType = (body.contentType || body.content_type || "video/mp4") as string;

  if (!fileName || !fileSize || fileSize <= 0) {
    return json({ error: "invalid_arguments" }, 400);
  }

  if (!contentType.startsWith("video/")) {
    return json({ error: "invalid_content_type" }, 400);
  }

  const safeFileName = fileName.replace(/[^a-zA-Z0-9._-]/g, "_");
  const r2Key = `users/${userId}/staged/${crypto.randomUUID()}-${safeFileName}`;
  const totalParts = fileSize <= kPartSizeBytes ? 1 : Math.ceil(fileSize / kPartSizeBytes);

  let uploadId: string;
  try {
    const createRes = await s3.send(
      new CreateMultipartUploadCommand({
        Bucket: bucketName,
        Key: r2Key,
        ContentType: contentType,
      }),
    );
    uploadId = createRes.UploadId!;
    if (!uploadId) throw new Error("failed_to_create_multipart");
  } catch (err: unknown) {
    const e = err as Error;
    return json({ error: "s3_initiate_failed", details: e.message }, 502);
  }

  const { data: slot, error: rpcError } = await supabaseAdmin.rpc("request_staged_upload_slot", {
    p_user_id: userId,
    p_file_size: fileSize,
    p_file_name: fileName,
    p_duration_ms: durationMs,
    p_r2_key: r2Key,
    p_upload_id: uploadId,
  });

  if (rpcError || (slot && slot.allowed === false)) {
    try {
      await s3.send(
        new AbortMultipartUploadCommand({
          Bucket: bucketName,
          Key: r2Key,
          UploadId: uploadId,
        }),
      );
    } catch (_) {}
    return json({ error: rpcError?.message || slot?.error || "slot_rejected", details: slot }, 400);
  }

  return json({
    stagedId: slot.staged_id,
    uploadId,
    r2Key,
    partSizeBytes: kPartSizeBytes,
    totalParts,
    sharingLevel: slot.sharing_level,
  });
}

async function handleStagedPartUrls(userId: string, body: Record<string, unknown>): Promise<Response> {
  const stagedId = (body.stagedId || body.staged_id) as string;
  const partNumbers = (body.partNumbers || body.part_numbers) as number[];

  if (!stagedId || !Array.isArray(partNumbers) || partNumbers.length === 0) {
    return json({ error: "invalid_arguments" }, 400);
  }

  const slot = await stagedUploadSlot(stagedId, userId);
  if (!slot || !slotMatches(slot, body)) {
    return json({ error: "unauthorized_or_invalid_staged_upload" }, 403);
  }
  if (!partsWithinSlot(partNumbers, slot)) {
    return json({ error: "invalid_part_numbers" }, 400);
  }

  const parts = await Promise.all(
    partNumbers.map(async (partNumber) => {
      const command = new UploadPartCommand({
        Bucket: bucketName,
        Key: slot.r2Key,
        UploadId: slot.uploadId,
        PartNumber: partNumber,
      });
      const url = await getSignedUrl(s3, command, { expiresIn: 1800 });
      return { partNumber, url };
    }),
  );

  return json({ parts });
}

async function handleStagedListParts(userId: string, body: Record<string, unknown>): Promise<Response> {
  const stagedId = (body.stagedId || body.staged_id) as string;

  if (!stagedId) {
    return json({ error: "invalid_arguments" }, 400);
  }

  const slot = await stagedUploadSlot(stagedId, userId);
  if (!slot || !slotMatches(slot, body)) {
    return json({ error: "unauthorized" }, 403);
  }

  try {
    const res = await s3.send(
      new ListPartsCommand({
        Bucket: bucketName,
        Key: slot.r2Key,
        UploadId: slot.uploadId,
      }),
    );

    const parts = (res.Parts ?? []).map((p) => ({
      partNumber: p.PartNumber,
      etag: (p.ETag ?? "").replace(/^"|"$/g, "").trim(),
      size: p.Size,
    }));

    return json({ parts });
  } catch (err: unknown) {
    const e = err as Error;
    return json({ error: "s3_list_parts_failed", details: e.message }, 502);
  }
}

async function handleStagedComplete(userId: string, body: Record<string, unknown>): Promise<Response> {
  const stagedId = (body.stagedId || body.staged_id) as string;
  const rawParts = body.parts as Array<{ partNumber: number; etag: string }>;

  if (!stagedId || !Array.isArray(rawParts) || rawParts.length === 0) {
    return json({ error: "invalid_arguments" }, 400);
  }

  const slot = await stagedUploadSlot(stagedId, userId);
  if (!slot || !slotMatches(slot, body)) {
    return json({ error: "unauthorized" }, 403);
  }
  if (!partsWithinSlot(rawParts.map((p) => p.partNumber), slot)) {
    return json({ error: "invalid_part_numbers" }, 400);
  }

  const sortedParts = [...rawParts]
    .sort((a, b) => a.partNumber - b.partNumber)
    .map((p) => ({
      PartNumber: p.partNumber,
      ETag: p.etag.replace(/^"|"$/g, "").trim(),
    }));

  try {
    await s3.send(
      new CompleteMultipartUploadCommand({
        Bucket: bucketName,
        Key: slot.r2Key,
        UploadId: slot.uploadId,
        MultipartUpload: { Parts: sortedParts },
      }),
    );
  } catch (err: unknown) {
    const e = err as Error;
    return json({ error: "s3_complete_failed", details: e.message }, 502);
  }

  const storedSize = await storedObjectSize(slot.r2Key);
  if (storedSize === null || storedSize > slot.declaredSize) {
    // The row's BEFORE DELETE trigger queues the object for deletion.
    await supabaseAdmin.rpc("clear_staged_upload", {
      p_staged_id: stagedId,
      p_bytes_uploaded: storedSize ?? 0,
    });
    return json({ error: "upload_size_mismatch" }, 400);
  }

  const { error: rpcError } = await supabaseAdmin.rpc("set_staged_upload_state", {
    p_staged_id: stagedId,
    p_user_id: userId,
    p_state: "ready",
    p_file_size: storedSize,
    p_r2_key: slot.r2Key,
    p_bytes_uploaded: storedSize,
  });

  if (rpcError) {
    return json({ error: rpcError.message }, 500);
  }

  return json({ success: true, stagedId, r2Key: slot.r2Key, state: "ready" });
}

async function handleStagedAbort(userId: string, body: Record<string, unknown>): Promise<Response> {
  const stagedId = (body.stagedId || body.staged_id) as string;
  const bytesUploaded = Number(body.bytesUploaded ?? body.bytes_uploaded ?? 0);

  if (!stagedId) {
    return json({ error: "invalid_arguments" }, 400);
  }

  const { data: staged } = await supabaseAdmin
    .from("staged_media_uploads")
    .select("id, user_id")
    .eq("id", stagedId)
    .maybeSingle();

  if (!staged || staged.user_id !== userId) {
    return json({ error: "unauthorized" }, 403);
  }

  const slot = await stagedUploadSlot(stagedId, userId);
  if (slot && slotMatches(slot, body)) {
    try {
      await s3.send(
        new AbortMultipartUploadCommand({
          Bucket: bucketName,
          Key: slot.r2Key,
          UploadId: slot.uploadId,
        }),
      );
    } catch (_) {}
  }

  await supabaseAdmin.rpc("clear_staged_upload", {
    p_staged_id: stagedId,
    p_bytes_uploaded: bytesUploaded,
  });

  return json({ success: true });
}

async function handleDownloadUrl(userId: string, body: Record<string, unknown>): Promise<Response> {
  const roomId = body.roomId as string;
  if (!roomId) {
    return json({ error: "invalid_arguments" }, 400);
  }

  const { isMember, room } = await verifyMember(roomId, userId);
  if (!isMember || !room) {
    return json({ error: "not_a_member" }, 403);
  }

  if (room.ended_at !== null || new Date(room.expires_at) <= new Date()) {
    return json({ error: "room_ended" }, 403);
  }

  if (room.media_upload_state !== "ready" || !room.media_r2_key) {
    return json({ error: "media_not_ready" }, 400);
  }

  const now = Date.now();
  const roomExpires = new Date(room.expires_at).getTime();
  const remainingSeconds = Math.max(0, Math.floor((roomExpires - now) / 1000));
  const ttlSeconds = Math.min(Math.max(3600, remainingSeconds + 7200), 86400);

  const fileName = room.media_name || "video.mp4";
  const safeAscii = fileName.replace(/[^\x20-\x7E]/g, "_").replace(/"/g, '\\"');
  const encodedUtf8 = encodeURIComponent(fileName);
  const contentDisposition = `inline; filename="${safeAscii}"; filename*=UTF-8''${encodedUtf8}`;

  const command = new GetObjectCommand({
    Bucket: bucketName,
    Key: room.media_r2_key,
    ResponseContentDisposition: contentDisposition,
  });

  const streamUrl = await getSignedUrl(s3, command, { expiresIn: ttlSeconds });

  return json({
    streamUrl,
    fileName,
    fileSize: room.media_file_size,
    expiresIn: ttlSeconds,
  });
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(), "Content-Type": "application/json" },
  });
}

function corsHeaders(): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };
}
