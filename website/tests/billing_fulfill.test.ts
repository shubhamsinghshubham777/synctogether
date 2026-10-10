import test from "node:test";
import assert from "node:assert/strict";
import { resolveFulfillment } from "../lib/billing/fulfill.ts";
import { EMPTY_BILLING } from "../lib/billing/core.ts";
import { creemProvider } from "../lib/billing/providers/creem.ts";
import type { NormalizedEvent } from "../lib/billing/types.ts";

function grant(over: Partial<NormalizedEvent> = {}): NormalizedEvent {
  return {
    provider: "creem",
    eventId: null,
    occurredAt: null,
    action: "grant",
    userId: "user_123",
    subscriptionId: "sub_1",
    customerId: "ctm_1",
    periodEnd: "2026-10-06T12:00:00.000Z",
    billing: EMPTY_BILLING,
    rawType: "lookup",
    ...over,
  };
}

test("rejects unauthenticated callers with 401", async () => {
  const r = await resolveFulfillment({ user: null, existingSub: null, configured: true, lookup: async () => grant() });
  assert.equal(r.status, 401);
  assert.equal(r.success, false);
});

test("a current premium row is returned without calling the provider", async () => {
  let called = false;
  const existing = { tier: "premium", current_period_end: "2026-10-01T00:00:00.000Z" };
  const r = await resolveFulfillment({
    user: { id: "user_123" },
    existingSub: existing,
    configured: true,
    now: new Date("2026-09-01T00:00:00.000Z"),
    lookup: async () => {
      called = true;
      return null;
    },
  });
  assert.equal(r.status, 200);
  assert.equal(called, false);
  assert.deepEqual(r.subscription, existing);
  assert.equal(r.event, undefined, "nothing to write");
});

test("a lapsed premium row is not reported as premium forever", async () => {
  const r = await resolveFulfillment({
    user: { id: "user_123" },
    existingSub: { tier: "premium", current_period_end: "2026-10-01T00:00:00.000Z" },
    configured: true,
    now: new Date("2026-11-01T00:00:00.000Z"),
    lookup: async () => null,
  });
  assert.equal(r.status, 404);
});

test("an unconfigured provider answers 500", async () => {
  const r = await resolveFulfillment({ user: { id: "user_123" }, existingSub: null, configured: false, lookup: async () => grant() });
  assert.equal(r.status, 500);
  assert.match(r.error ?? "", /unconfigured/i);
});

test("a subscription belonging to someone else is never applied (P0 loophole)", async () => {
  const r = await resolveFulfillment({
    user: { id: "attacker" },
    existingSub: null,
    configured: true,
    lookup: async () => grant({ userId: "someone_else" }),
  });
  assert.equal(r.status, 404);
  assert.equal(r.event, undefined);
});

test("a lookup that finds nothing is a 404", async () => {
  const r = await resolveFulfillment({ user: { id: "user_123" }, existingSub: null, configured: true, lookup: async () => null });
  assert.equal(r.status, 404);
});

test("a found subscription is handed back as an event, with its real period", async () => {
  const r = await resolveFulfillment({ user: { id: "user_123" }, existingSub: null, configured: true, lookup: async () => grant() });
  assert.equal(r.status, 200);
  assert.equal(r.event?.periodEnd, "2026-10-06T12:00:00.000Z");
});

test("no period end answers 202 and invents nothing", async () => {
  const r = await resolveFulfillment({
    user: { id: "user_123" },
    existingSub: null,
    configured: true,
    lookup: async () => grant({ periodEnd: null }),
  });
  assert.equal(r.status, 202);
  assert.equal(r.pending, true);
  assert.equal(r.event, undefined, "the webhook writes the row, not a guess");
});

test("a provider failure is a 502, not a grant", async () => {
  const r = await resolveFulfillment({
    user: { id: "user_123" },
    existingSub: null,
    configured: true,
    lookup: async () => {
      throw new Error("boom");
    },
  });
  assert.equal(r.status, 502);
});

// --- The Creem lookup itself ---------------------------------------------------

async function withCreem(checkout: unknown, run: () => Promise<void>) {
  const realFetch = globalThis.fetch;
  process.env.CREEM_API_KEY = "creem_test_key";
  globalThis.fetch = (async () => new Response(JSON.stringify(checkout), { status: 200 })) as typeof fetch;
  try {
    await run();
  } finally {
    globalThis.fetch = realFetch;
  }
}

const creemSub = (status: string) => ({
  id: "sub_1",
  status,
  product: { id: "prod_m", price: 399, currency: "USD", billing_period: "every-month" },
  customer: { id: "cust_1" },
  current_period_end_date: "2026-10-06T12:00:00.000Z",
});
const checkoutFor = (userId: string, status: string) => ({
  id: "ch_1",
  request_id: userId,
  metadata: { user_id: userId },
  subscription: creemSub(status),
});

test("creem lookup without a checkout id finds nothing and relies on the webhook", async () => {
  assert.equal(await creemProvider.findActiveSubscription("u1"), null);
});

test("creem lookup grants only an active or trialing subscription from the caller's own checkout", async () => {
  for (const status of ["active", "trialing"]) {
    await withCreem(checkoutFor("u1", status), async () => {
      const e = await creemProvider.findActiveSubscription("u1", { checkoutId: "ch_1" });
      assert.equal(e?.userId, "u1");
      assert.equal(e?.periodEnd, "2026-10-06T12:00:00.000Z");
      assert.equal(e?.eventId, null, "a lookup must not move the event cursor");
    });
  }
  for (const status of ["canceled", "past_due", "paused"]) {
    await withCreem(checkoutFor("u1", status), async () => {
      assert.equal(await creemProvider.findActiveSubscription("u1", { checkoutId: "ch_1" }), null, status);
    });
  }
});

test("creem lookup refuses someone else's checkout (P0 loophole)", async () => {
  await withCreem(checkoutFor("victim", "active"), async () => {
    assert.equal(await creemProvider.findActiveSubscription("attacker", { checkoutId: "ch_1" }), null);
  });
});

test("creem lookup treats an unknown checkout id as nothing found, not an outage", async () => {
  const realFetch = globalThis.fetch;
  process.env.CREEM_API_KEY = "creem_test_key";
  globalThis.fetch = (async () => new Response("{}", { status: 404 })) as typeof fetch;
  try {
    assert.equal(await creemProvider.findActiveSubscription("u1", { checkoutId: "ch_nope" }), null);
  } finally {
    globalThis.fetch = realFetch;
  }
});
