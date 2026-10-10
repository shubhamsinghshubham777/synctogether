import test from "node:test";
import assert from "node:assert/strict";
import { applyEvent, type SubscriptionsDb } from "../lib/billing/apply.ts";
import { EMPTY_BILLING } from "../lib/billing/core.ts";
import type { NormalizedEvent } from "../lib/billing/types.ts";

type Row = Record<string, unknown>;

/** An in-memory `subscriptions` table behind the narrow slice `applyEvent` uses. */
function fakeDb(rows: Record<string, Row> = {}) {
  const writes: { kind: string; values: Row }[] = [];
  const db: SubscriptionsDb = {
    from: () => ({
      select: () => ({
        eq: (_c, id) => ({ maybeSingle: async () => ({ data: (rows[id] as never) ?? null }) }),
      }),
      update: (values) => ({
        eq: async (_c, id) => {
          writes.push({ kind: "update", values });
          if (rows[id]) rows[id] = { ...rows[id], ...values };
          return { error: null };
        },
      }),
      upsert: async (values) => {
        writes.push({ kind: "upsert", values });
        rows[values.user_id as string] = { ...rows[values.user_id as string], ...values };
        return { error: null };
      },
    }),
  };
  return { db, rows, writes };
}

function event(over: Partial<NormalizedEvent> = {}): NormalizedEvent {
  return {
    provider: "creem",
    eventId: "evt_2",
    occurredAt: "2026-10-02T00:00:00Z",
    action: "grant",
    userId: "u1",
    subscriptionId: "sub_1",
    customerId: "ctm_1",
    periodEnd: "2999-11-01T00:00:00Z",
    billing: { ...EMPTY_BILLING, provider_status: "active" },
    rawType: "subscription.activated",
    ...over,
  };
}

test("a grant upserts the row with the provider as its source", async () => {
  const { db, rows } = fakeDb();
  const r = await applyEvent(db, event());
  assert.equal(r.status, 200);
  assert.equal(rows.u1.tier, "premium");
  assert.equal(rows.u1.source, "creem");
  assert.equal(rows.u1.provider_subscription_id, "sub_1");
  assert.equal(rows.u1.provider_customer_id, "ctm_1");
  assert.equal(rows.u1.last_event_id, "evt_2");
});

test("an event with no user id is acknowledged and writes nothing", async () => {
  const { db, writes } = fakeDb();
  const r = await applyEvent(db, event({ userId: null }));
  assert.equal(r.status, 200);
  assert.equal(writes.length, 0);
});

test("a grant with no period end is refused with 422 and writes nothing", async () => {
  const { db, writes } = fakeDb();
  const r = await applyEvent(db, event({ periodEnd: null }));
  assert.equal(r.status, 422);
  assert.equal(writes.length, 0);
});

test("revoke sets the tier to free and dates the row; it never deletes it", async () => {
  const { db, rows } = fakeDb({
    u1: { tier: "premium", source: "creem", provider_subscription_id: "sub_1", current_period_end: "2999-01-01T00:00:00Z", last_event_id: "evt_1", last_event_at: "2026-10-01T00:00:00Z" },
  });
  const r = await applyEvent(db, event({ action: "revoke" }), new Date("2026-10-03T00:00:00Z"));
  assert.equal(r.status, 200);
  assert.equal(rows.u1.tier, "free");
  assert.equal(rows.u1.current_period_end, "2026-10-03T00:00:00.000Z");
  assert.equal(rows.u1.provider_subscription_id, "sub_1", "the ids survive");
  assert.equal(rows.u1.last_event_id, "evt_2", "the cursor advances");
});

test("grace leaves entitlement alone and only records the status", async () => {
  const { db, rows } = fakeDb({
    u1: { tier: "premium", source: "creem", provider_subscription_id: "sub_1", current_period_end: "2999-01-01T00:00:00Z", last_event_at: "2026-10-01T00:00:00Z" },
  });
  await applyEvent(db, event({ action: "grace", billing: { ...EMPTY_BILLING, provider_status: "past_due" } }));
  assert.equal(rows.u1.tier, "premium");
  assert.equal(rows.u1.current_period_end, "2999-01-01T00:00:00Z");
  assert.equal(rows.u1.provider_status, "past_due");
});

test("a stale or replayed event changes nothing", async () => {
  const base = { tier: "free", source: "creem", provider_subscription_id: "sub_1", last_event_id: "evt_5", last_event_at: "2026-10-05T00:00:00Z" };
  const { db, writes } = fakeDb({ u1: { ...base } });
  const older = await applyEvent(db, event({ eventId: "evt_3", occurredAt: "2026-10-03T00:00:00Z" }));
  assert.deepEqual(older.body, { success: true, skipped: "stale_event" });
  const replay = await applyEvent(db, event({ eventId: "evt_5", occurredAt: "2026-10-09T00:00:00Z" }));
  assert.deepEqual(replay.body, { success: true, skipped: "stale_event" });
  assert.equal(writes.length, 0, "an updated that overtakes a canceled must not resurrect it");
});

test("a redundant grant moves only the cursor", async () => {
  const billing = { ...EMPTY_BILLING, provider_status: "active" };
  const { db, writes } = fakeDb({
    u1: { tier: "premium", source: "creem", provider_subscription_id: "sub_1", current_period_end: "2999-11-01T00:00:00Z", last_event_id: "evt_1", last_event_at: "2026-10-01T00:00:00Z", ...billing },
  });
  const r = await applyEvent(db, event());
  assert.equal(r.body.deduplicated, true);
  assert.deepEqual(writes.map((w) => w.kind), ["update"]);
});

test("a canceled from another provider cannot revoke a live grant (cross-provider guard, against a hypothetical second provider)", async () => {
  const { db, rows, writes } = fakeDb({
    u1: { tier: "premium", source: "acme", provider_subscription_id: "sub_c", current_period_end: "2999-01-01T00:00:00Z" },
  });
  const r = await applyEvent(db, event({ action: "revoke", provider: "creem", subscriptionId: "sub_p" }));
  assert.deepEqual(r.body, { success: true, skipped: "other_provider_owns_row" });
  assert.equal(rows.u1.tier, "premium");
  assert.equal(writes.length, 0, "not even the cursor moves");
});

test("a lookup (no event id or time) does not drag the cursor to now", async () => {
  const { db, rows } = fakeDb({
    u1: { tier: "free", source: "creem", last_event_id: "evt_1", last_event_at: "2026-10-01T00:00:00Z" },
  });
  await applyEvent(db, event({ eventId: null, occurredAt: null, rawType: "lookup" }), new Date("2026-10-09T00:00:00Z"));
  assert.equal(rows.u1.last_event_at, "2026-10-01T00:00:00Z");
  assert.equal(rows.u1.last_event_id, "evt_1");
  assert.equal(rows.u1.tier, "premium");
});
