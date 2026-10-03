// Mints a LiveKit access token for a room the caller is a member of.
// Secrets are set via `supabase secrets set --env-file supabase/functions/.env`
// - never shipped to clients. Membership is checked through the caller's own
// JWT, so RLS (room_members select policy) is the source of truth.
//
// Endpoints: LIVEKIT_ENDPOINTS is a JSON array, in priority order, of
// LiveKit-protocol servers ({id, url, key, secret}) - e.g. a self-hosted
// server first and LiveKit Cloud behind it. Without it the single legacy
// LIVEKIT_URL / LIVEKIT_API_KEY / LIVEKIT_API_SECRET triple is endpoint
// "default". The room is pinned to one endpoint by `pick_av_endpoint`; a
// client that could not reach its endpoint sends `failed_endpoint` and gets
// the next one. When none is left the answer is 503 `av_capacity_exhausted`.

import { createClient } from "npm:@supabase/supabase-js@2.58.0";
import { AccessToken, TrackSource } from "npm:livekit-server-sdk@2.17.0";
import { cameraGrant, parseEndpoints } from "../_shared/av_endpoints.ts";

type TokenRequest = { room_id?: string; failed_endpoint?: string; force_endpoint?: string };

// Local/staging only: lets a debug build pin its room to a named endpoint and
// see the endpoint list. Never set in production - it would let any member
// move their room onto an endpoint we have marked down.
const DEBUG_SWITCHING = Deno.env.get("AV_DEBUG_SWITCHING") === "true";

// Seconds the client waits before asking again once every endpoint is down.
const EXHAUSTED_RETRY_S = 300;

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return json({ error: "not_authenticated" }, 401);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: userData, error: userError } = await supabase.auth.getUser();
  const user = userData?.user;
  if (userError || !user) {
    return json({ error: "not_authenticated" }, 401);
  }

  let body: TokenRequest;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  const roomId = body.room_id;
  if (!roomId) {
    return json({ error: "room_id_required" }, 400);
  }

  // Visible through RLS only if the caller is a member of a room they can see.
  const { data: membership } = await supabase
    .from("room_members")
    .select("room_id, rooms!inner(ended_at, expires_at, av_level, video_trial_ends_at)")
    .eq("room_id", roomId)
    .eq("user_id", user.id)
    .maybeSingle();
  if (!membership) {
    return json({ error: "not_a_member" }, 403);
  }
  const room = membership.rooms as unknown as {
    ended_at: string | null;
    expires_at: string;
    av_level: string;
    video_trial_ends_at: string | null;
  };
  if (room.ended_at !== null || new Date(room.expires_at) <= new Date()) {
    return json({ error: "room_ended" }, 403);
  }
  // The room's tier decides AV, not the client. The app hides the controls
  // for a `none`/`voice` room, but anyone can call this function directly, so
  // the token itself carries the limit: no token for `none`, microphone-only
  // publish for `voice`.
  if (room.av_level !== "voice" && room.av_level !== "video") {
    return json({ error: "av_not_available" }, 403);
  }

  const { data: profile } = await supabase
    .from("profiles")
    .select("display_name")
    .eq("id", user.id)
    .maybeSingle();

  const endpoints = parseEndpoints(Deno.env.toObject());
  if (endpoints.length === 0) {
    return json({ error: "av_not_configured" }, 500);
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const failed = typeof body.failed_endpoint === "string" ? body.failed_endpoint : null;
  const { data: picked, error: pickError } = await admin.rpc("pick_av_endpoint", {
    p_room_id: roomId,
    p_candidates: endpoints.map((e) => e.id),
    p_failed: failed,
    p_user: failed ? user.id : null,
    p_force: DEBUG_SWITCHING && typeof body.force_endpoint === "string" ? body.force_endpoint : null,
  });
  if (pickError) {
    console.error("pick_av_endpoint failed", pickError);
    return json({ error: "av_pick_failed" }, 500);
  }
  const endpoint = endpoints.find((e) => e.id === picked);
  if (!endpoint) {
    return json({ error: "av_capacity_exhausted", retry_after_s: EXHAUSTED_RETRY_S }, 503);
  }

  // Kept short on purpose; see the ttl note below.
  const grant = cameraGrant(room.av_level, room.video_trial_ends_at, endpoint, new Date(), 600);

  const token = new AccessToken(
    endpoint.key,
    endpoint.secret,
    {
      identity: user.id,
      name: profile?.display_name ?? "Watcher",
      // Short on purpose: av-cleanup can remove a kicked member from the
      // call, but cannot revoke a token. LiveKit refreshes the token of a
      // participant who stays connected, and every reconnect comes back
      // here, where membership is re-checked - so 10 minutes is the most a
      // removed member can sneak back in for. A video-trial token lives no
      // longer than the trial (cameraGrant); av-cleanup's revoke_camera job
      // takes the camera off anyone still connected when it ends.
      ttl: grant.ttlSeconds,
    },
  );
  token.addGrant({
    room: roomId,
    roomJoin: true,
    canPublish: true,
    canPublishSources: grant.camera
      ? [TrackSource.MICROPHONE, TrackSource.CAMERA]
      : [TrackSource.MICROPHONE],
    canSubscribe: true,
    canPublishData: true,
  });

  return json({
    token: await token.toJwt(),
    url: endpoint.url,
    endpoint: endpoint.id,
    // Whether this token can publish the camera. In a voice room it says the
    // trial is running *and* this endpoint allows it - a room that failed
    // over to LiveKit Cloud mid-trial carries on with voice only.
    camera: grant.camera,
    ...(DEBUG_SWITCHING ? { endpoints: endpoints.map((e) => e.id) } : {}),
  });
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
