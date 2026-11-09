// Delivers the rows in public.push_outbox. Invoked by pg_net (see
// invoke_push_dispatch) with the service-role key, so the gateway's JWT check is
// the only authentication it needs. Secrets: see supabase/functions/.env.example.
import { createClient } from "npm:@supabase/supabase-js@2.58.0";
import { providersFromEnv, type PushRow, sendToToken, settle } from "../_shared/push.ts";

const admin = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
);

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "method_not_allowed" }), { status: 405 });
  }
  const providers = providersFromEnv((k) => Deno.env.get(k));
  const stats = { sent: 0, retried: 0, dropped_tokens: 0 };

  // A few passes so a burst drains in one invocation without running forever.
  for (let pass = 0; pass < 5; pass++) {
    const { data, error } = await admin.rpc("claim_push_batch", { p_limit: 50 });
    if (error) {
      console.error("claim_push_batch failed", error.message);
      return new Response(JSON.stringify({ error: "claim_failed" }), { status: 500 });
    }
    const rows = (data ?? []) as PushRow[];
    if (rows.length === 0) break;

    await Promise.all(rows.map(async (row) => {
      const outcomes = await Promise.all(
        row.tokens.map(async (token) => ({ token, outcome: await sendToToken(providers, row, token, fetch) })),
      );
      const { done, dead } = settle(outcomes);
      for (const t of dead) {
        await admin.rpc("drop_push_token", { p_platform: t.platform, p_token: t.token });
        stats.dropped_tokens++;
      }
      await admin.rpc("complete_push", { p_id: row.id, p_done: done });
      if (done) stats.sent++;
      else stats.retried++;
    }));
    if (rows.length < 50) break;
  }

  return new Response(JSON.stringify(stats), { headers: { "content-type": "application/json" } });
});
