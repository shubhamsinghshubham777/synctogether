import test from "node:test";
import assert from "node:assert/strict";
import crypto from "crypto";
import {
  verifyPaddleSignature,
  parseSignatureHeader,
  classifyEvent,
  shouldApplyEvent,
  resolvePeriodEnd,
  isRedundantGrant,
  resolveBilling,
  MAX_WEBHOOK_AGE_SECONDS,
} from "../lib/paddle_webhook.ts";

const SECRET = "pdl_ntfset_test_secret";
const BODY = JSON.stringify({
  event_type: "subscription.activated",
  data: { custom_data: { user_id: "user_abc" }, status: "active" },
});

function sign(body: string, ts: number, secret = SECRET) {
  const h1 = crypto
    .createHmac("sha256", secret)
    .update(`${ts}:${body}`)
    .digest("hex");
  return `ts=${ts};h1=${h1}`;
}

const NOW = 1_800_000_000;

/*
 * The regression these exist for: both guards in the old handler were
 * `if (thing_we_need)`, so omitting the header - or deploying without the
 * secret - skipped verification entirely and granted premium to whatever user
 * id the body named. Every case below must fail closed.
 */

test("a body with no signature header is rejected, not trusted", () => {
  const verdict = verifyPaddleSignature({
    rawBody: BODY,
    signatureHeader: null,
    secret: SECRET,
    nowSeconds: NOW,
  });
  assert.equal(verdict.ok, false);
  assert.equal(verdict.ok === false && verdict.reason, "missing_signature");
});

test("a missing webhook secret rejects rather than skipping verification", () => {
  for (const secret of [undefined, "", "   "]) {
    const verdict = verifyPaddleSignature({
      rawBody: BODY,
      signatureHeader: sign(BODY, NOW),
      secret,
      nowSeconds: NOW,
    });
    assert.equal(verdict.ok, false, `secret ${JSON.stringify(secret)} must reject`);
    assert.equal(verdict.ok === false && verdict.reason, "missing_secret");
  }
});

test("a header missing ts or h1 is malformed, not a pass", () => {
  for (const header of ["", "ts=123", "h1=abc", "garbage", ";;", "ts=;h1="]) {
    const verdict = verifyPaddleSignature({
      rawBody: BODY,
      signatureHeader: header,
      secret: SECRET,
      nowSeconds: NOW,
    });
    assert.equal(verdict.ok, false, `header ${JSON.stringify(header)} must reject`);
  }
});

test("a non-hex or wrong-length digest is rejected without throwing", () => {
  // Buffer.from(x, "hex") truncates silently, so these must be caught by shape.
  for (const h1 of ["zz", "abc", "not-hex".repeat(9), "a".repeat(63), "a".repeat(65)]) {
    const verdict = verifyPaddleSignature({
      rawBody: BODY,
      signatureHeader: `ts=${NOW};h1=${h1}`,
      secret: SECRET,
      nowSeconds: NOW,
    });
    assert.equal(verdict.ok, false, `h1 ${h1.slice(0, 12)} must reject`);
  }
});

test("a signature computed with the wrong secret is rejected", () => {
  const verdict = verifyPaddleSignature({
    rawBody: BODY,
    signatureHeader: sign(BODY, NOW, "the_wrong_secret"),
    secret: SECRET,
    nowSeconds: NOW,
  });
  assert.equal(verdict.ok, false);
  assert.equal(verdict.ok === false && verdict.reason, "bad_digest");
});

test("a signature valid for a different body is rejected", () => {
  const tampered = BODY.replace("user_abc", "user_attacker");
  const verdict = verifyPaddleSignature({
    rawBody: tampered,
    signatureHeader: sign(BODY, NOW),
    secret: SECRET,
    nowSeconds: NOW,
  });
  assert.equal(verdict.ok, false);
  assert.equal(verdict.ok === false && verdict.reason, "bad_digest");
});

test("a correctly signed, fresh request passes", () => {
  const verdict = verifyPaddleSignature({
    rawBody: BODY,
    signatureHeader: sign(BODY, NOW),
    secret: SECRET,
    nowSeconds: NOW,
  });
  assert.equal(verdict.ok, true);
});

test("a captured signature goes stale in both directions", () => {
  const old = verifyPaddleSignature({
    rawBody: BODY,
    signatureHeader: sign(BODY, NOW - MAX_WEBHOOK_AGE_SECONDS - 1),
    secret: SECRET,
    nowSeconds: NOW,
  });
  assert.equal(old.ok, false);
  assert.equal(old.ok === false && old.reason, "stale_timestamp");

  const future = verifyPaddleSignature({
    rawBody: BODY,
    signatureHeader: sign(BODY, NOW + MAX_WEBHOOK_AGE_SECONDS + 1),
    secret: SECRET,
    nowSeconds: NOW,
  });
  assert.equal(future.ok, false);

  const edge = verifyPaddleSignature({
    rawBody: BODY,
    signatureHeader: sign(BODY, NOW - MAX_WEBHOOK_AGE_SECONDS),
    secret: SECRET,
    nowSeconds: NOW,
  });
  assert.equal(edge.ok, true, "exactly at the window is still fresh");
});

test("parseSignatureHeader keeps a base64 h1 intact despite '=' padding", () => {
  const parsed = parseSignatureHeader("ts=123;h1=abc==");
  assert.deepEqual(parsed, { ts: "123", h1: "abc==" });
});

test("past_due is a grace state, never a revocation", () => {
  assert.equal(classifyEvent("subscription.past_due"), "grace");
  assert.equal(classifyEvent("subscription.updated", "past_due"), "grace");
});

test("cancellation and pause revoke, however they arrive", () => {
  assert.equal(classifyEvent("subscription.canceled"), "revoke");
  assert.equal(classifyEvent("subscription.paused"), "revoke");
  assert.equal(classifyEvent("subscription.updated", "canceled"), "revoke");
  assert.equal(classifyEvent("subscription.updated", "paused"), "revoke");
});

test("active and trialing subscriptions grant; resumed is not forgotten", () => {
  assert.equal(classifyEvent("subscription.activated", "active"), "grant");
  assert.equal(classifyEvent("subscription.created", "active"), "grant");
  assert.equal(classifyEvent("subscription.updated", "active"), "grant");
  assert.equal(classifyEvent("subscription.resumed", "active"), "grant");
  assert.equal(classifyEvent("subscription.updated", "trialing"), "grant");
});

test("transaction.completed no longer grants a flat month", () => {
  assert.equal(classifyEvent("transaction.completed", "completed"), "ignore");
});

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

test("a payload with no billing period yields null rather than a fabricated month", () => {
  assert.equal(resolvePeriodEnd({}), null);
  assert.equal(
    resolvePeriodEnd({ current_billing_period: { ends_at: "2027-01-01T00:00:00Z" } }),
    "2027-01-01T00:00:00Z"
  );
  assert.equal(
    resolvePeriodEnd({ billing_period: { ends_at: "2026-10-01T00:00:00Z" } }),
    "2026-10-01T00:00:00Z"
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

// --- Billing details (revenue on the internal dashboard) ---------------------

const INR_ANNUAL = {
  status: "active",
  currency_code: "INR",
  items: [
    {
      quantity: 1,
      price: {
        id: "pri_annual",
        billing_cycle: { interval: "year", frequency: 1 },
        unit_price: { amount: "2999", currency_code: "USD" },
        unit_price_overrides: [
          { unit_price: { amount: "99900", currency_code: "INR" } },
        ],
      },
    },
  ],
};

test("resolveBilling records the localised override, not the base USD price", () => {
  const b = resolveBilling(INR_ANNUAL);
  assert.equal(b.unit_amount, 99900);
  assert.equal(b.currency, "INR");
  assert.equal(b.billing_interval, "year");
  assert.equal(b.billing_frequency, 1);
  assert.equal(b.price_id, "pri_annual");
  assert.equal(b.paddle_status, "active");
  assert.equal(b.scheduled_cancel_at, null);
});

test("resolveBilling leaves the amount null when no unit price is in the subscription currency", () => {
  const b = resolveBilling({ ...INR_ANNUAL, currency_code: "EUR" });
  assert.equal(b.unit_amount, null, "an unmatched currency must not fall back to USD");
  assert.equal(b.currency, "EUR");
});

test("resolveBilling multiplies by quantity and reads a scheduled cancellation", () => {
  const b = resolveBilling({
    status: "active",
    currency_code: "USD",
    scheduled_change: { action: "cancel", effective_at: "2026-10-27T00:00:00Z" },
    items: [
      {
        quantity: 2,
        price: { id: "pri_m", billing_cycle: { interval: "month", frequency: 1 }, unit_price: { amount: "399", currency_code: "USD" } },
      },
    ],
  });
  assert.equal(b.unit_amount, 798);
  assert.equal(b.scheduled_cancel_at, "2026-10-27T00:00:00Z");
});

test("resolveBilling survives a payload with no items", () => {
  const b = resolveBilling({ status: "active" });
  assert.deepEqual(
    [b.price_id, b.unit_amount, b.currency, b.billing_interval],
    [null, null, null, null]
  );
});

test("a grant whose price or cancellation changed is not redundant", () => {
  const periodEnd = "2026-10-27T00:00:00Z";
  const billing = resolveBilling(INR_ANNUAL);
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
    "the same instant in Postgres and Paddle spelling is not a change"
  );
});
