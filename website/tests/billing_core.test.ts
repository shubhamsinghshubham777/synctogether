import test from "node:test";
import assert from "node:assert/strict";
import {
  shouldApplyEvent,
  isRedundantGrant,
  eventTargetsRow,
  EMPTY_BILLING,
  type BillingDetails,
} from "../lib/billing/core.ts";

// A fully-priced billing block, standing in for what an adapter produces.
const billing: BillingDetails = {
  price_id: "pri_annual",
  unit_amount: 99900,
  currency: "INR",
  billing_interval: "year",
  billing_frequency: 1,
  provider_status: "active",
  scheduled_cancel_at: null,
};
void EMPTY_BILLING;

test("an event is applied only when strictly newer than the last one", () => {
  const last = { lastEventId: "evt_1", lastEventAt: "2026-09-21T12:00:00Z" };

  assert.equal(
    shouldApplyEvent({ eventId: "evt_1", occurredAt: "2026-09-21T13:00:00Z", ...last }),
    false,
    "the same event id is a replay whatever its timestamp claims"
  );
  assert.equal(
    shouldApplyEvent({ eventId: "evt_0", occurredAt: "2026-09-21T11:00:00Z", ...last }),
    false,
    "an out-of-order updated must not resurrect a cancellation"
  );
  assert.equal(
    shouldApplyEvent({ eventId: "evt_2", occurredAt: "2026-09-21T12:00:00Z", ...last }),
    false,
    "equal timestamps are not newer"
  );
  assert.equal(
    shouldApplyEvent({ eventId: "evt_2", occurredAt: "2026-09-21T12:00:01Z", ...last }),
    true
  );
  assert.equal(
    shouldApplyEvent({ eventId: "evt_2", occurredAt: "2026-09-21T12:00:01Z" }),
    true,
    "a row with no cursor yet accepts the event"
  );
});

test("a grant that changes nothing is suppressed, but a renewal is not", () => {
  const existing = { tier: "premium", current_period_end: "2026-09-15T00:00:00.000Z" };

  assert.equal(isRedundantGrant(existing, "2026-09-15T00:00:00.000Z"), true);
  assert.equal(
    isRedundantGrant(existing, "2026-10-15T00:00:00.000Z"),
    false,
    "a renewal moves the period end and must be written"
  );
  assert.equal(
    isRedundantGrant({ tier: "free", current_period_end: "2026-09-15T00:00:00.000Z" }, "2026-09-15T00:00:00.000Z"),
    false,
    "re-granting after a revocation is not redundant"
  );
  assert.equal(isRedundantGrant(null, "2026-09-15T00:00:00.000Z"), false);
});

test("a grant whose price or cancellation changed is not redundant", () => {
  const periodEnd = "2026-10-27T00:00:00Z";
    const existing = { tier: "premium", current_period_end: periodEnd, ...billing };
  assert.equal(isRedundantGrant(existing, periodEnd, billing), true);
  assert.equal(
    isRedundantGrant({ ...existing, unit_amount: null }, periodEnd, billing),
    false,
    "a row predating the billing columns must be backfilled"
  );
  assert.equal(
    isRedundantGrant(existing, periodEnd, { ...billing, scheduled_cancel_at: periodEnd }),
    false,
    "scheduling a cancellation must be recorded"
  );
  assert.equal(
    isRedundantGrant(
      { ...existing, scheduled_cancel_at: "2026-10-27T00:00:00+00:00" },
      periodEnd,
      { ...billing, scheduled_cancel_at: "2026-10-27T00:00:00Z" }
    ),
    true,
    "the same instant in Postgres and provider spelling is not a change"
  );
});

// --- Cross-provider guard ----------------------------------------------------

const FUTURE = "2999-01-01T00:00:00Z";
const PAST = "2000-01-01T00:00:00Z";

test("an event may always change a row that does not exist yet", () => {
  assert.equal(eventTargetsRow({ provider: "acme", subscriptionId: "sub_1" }, null), true);
});

test("a canceled from one provider cannot revoke a live grant from another", () => {
  const row = { tier: "premium", source: "creem", current_period_end: FUTURE, provider_subscription_id: "sub_c" };
  assert.equal(eventTargetsRow({ provider: "acme", subscriptionId: "sub_p" }, row), false);
});

test("the same provider and subscription always targets its own row", () => {
  const row = { tier: "premium", source: "creem", current_period_end: FUTURE, provider_subscription_id: "sub_c" };
  assert.equal(eventTargetsRow({ provider: "creem", subscriptionId: "sub_c" }, row), true);
});

test("a lapsed or free row from another provider can be taken over", () => {
  assert.equal(
    eventTargetsRow(
      { provider: "acme", subscriptionId: "sub_p" },
      { tier: "premium", source: "creem", current_period_end: PAST, provider_subscription_id: "sub_c" }
    ),
    true,
    "an expired premium row protects nothing"
  );
  assert.equal(
    eventTargetsRow(
      { provider: "acme", subscriptionId: "sub_p" },
      { tier: "free", source: "creem", current_period_end: FUTURE, provider_subscription_id: "sub_c" }
    ),
    true,
    "a revoked row protects nothing"
  );
});

test("a manual or debug grant is not a provider, so a real purchase replaces it", () => {
  for (const source of ["manual", "debug"]) {
    assert.equal(
      eventTargetsRow({ provider: "acme", subscriptionId: "sub_p" }, { tier: "premium", source, current_period_end: FUTURE }),
      true
    );
  }
});
