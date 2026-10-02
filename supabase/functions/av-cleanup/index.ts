// Drains pending_av_cleanups: deletes ended rooms and removes departed
// members on EVERY configured LiveKit endpoint, since a room may have been
// moved between endpoints during its life. Invoked by invoke_av_cleanup
// (pg_cron, every minute). Mirrors cleanup-r2: a row that keeps failing is
// dropped for good at attempts >= 5.

import { createClient } from "npm:@supabase/supabase-js@2.58.0";
import { RoomServiceClient } from "npm:livekit-server-sdk@2.17.0";
import { httpHost, parseEndpoints } from "../_shared/av_endpoints.ts";

const MAX_ATTEMPTS = 5;

// "Already gone" is the outcome we wanted.
function isNotFound(err: unknown): boolean {
  const e = err as { status?: number; code?: string; message?: string };
  return e?.status === 404 || e?.code === "not_found" || /not.?found/i.test(e?.message ?? "");
}

Deno.serve(async (_req) => {
  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const endpoints = parseEndpoints(Deno.env.toObject());
  const clients = endpoints.map((e) => ({
    id: e.id,
    rs: new RoomServiceClient(httpHost(e.url), e.key, e.secret),
  }));

  const { data: queue, error } = await admin
    .from("pending_av_cleanups")
    .select("id, room_id, user_id, attempts")
    .order("id", { ascending: true })
    .limit(100);
  if (error) {
    console.error("reading pending_av_cleanups failed", error);
    return new Response(JSON.stringify({ error: "queue_read_failed" }), { status: 500 });
  }

  let cleaned = 0;
  let failed = 0;
  for (const item of queue ?? []) {
    const failures: string[] = [];
    for (const { id, rs } of clients) {
      try {
        if (item.user_id) {
          await rs.removeParticipant(item.room_id, item.user_id);
        } else {
          await rs.deleteRoom(item.room_id);
        }
      } catch (err) {
        if (!isNotFound(err)) failures.push(`${id}: ${(err as Error)?.message ?? err}`);
      }
    }
    if (failures.length === 0 || item.attempts + 1 >= MAX_ATTEMPTS) {
      if (failures.length > 0) {
        console.error(`giving up on av cleanup ${item.id}`, failures);
        failed++;
      } else {
        cleaned++;
      }
      await admin.from("pending_av_cleanups").delete().eq("id", item.id);
    } else {
      failed++;
      await admin
        .from("pending_av_cleanups")
        .update({ attempts: item.attempts + 1 })
        .eq("id", item.id);
    }
  }

  return new Response(JSON.stringify({ cleaned, failed }), {
    headers: { "Content-Type": "application/json" },
  });
});
