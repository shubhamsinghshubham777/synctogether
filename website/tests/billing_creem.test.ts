import test from "node:test";
import assert from "node:assert/strict";
import crypto from "crypto";
import { readFileSync } from "node:fs";
import {
  verifyCreemSignature,
  classifyCreemEvent,
  parseCreemWebhook,
  resolveCreemBilling,
  creemProductId,
} from "../lib/billing/providers/creem.ts";

// Hand-written to match Creem's documented payloads - NOT captured from test
// mode. Replace with real captures from the Creem test-mode run (plan, Phase 2)
// before trusting the field mapping.
const fixture = (name: string) =>
  readFileSync(new URL(`./fixtures/creem/${name}.json`, import.meta.url), "utf8");

const SECRET = "whsec_creem_test";
const BODY = fixture("subscription_paid");
const sign = (body: string, secret = SECRET) =>
  crypto.createHmac("sha256", secret).update(body).digest("hex");

test("a missing secret rejects rather than skipping verification", () => {
  for (const secret of [undefined, "", "  "]) {
    const v = verifyCreemSignature({ rawBody: BODY, signatureHeader: sign(BODY), secret });
    assert.deepEqual(v, { ok: false, reason: "missing_secret" });
  }
});

test("a missing signature header is rejected, not trusted", () => {
  for (const header of [null, undefined, ""]) {
    const v = verifyCreemSignature({ rawBody: BODY, signatureHeader: header, secret: SECRET });
    assert.deepEqual(v, { ok: false, reason: "missing_signature" });
  }
});

test("a non-hex or wrong-length signature is malformed, without throwing", () => {
  for (const header of ["zz".repeat(32), "abc", sign(BODY) + "00", "sha256=" + sign(BODY)]) {
    const v = verifyCreemSignature({ rawBody: BODY, signatureHeader: header, secret: SECRET });
    assert.deepEqual(v, { ok: false, reason: "malformed_signature" }, header);
  }
});

test("a signature from the wrong secret or for a different body is rejected", () => {
  assert.deepEqual(
    verifyCreemSignature({ rawBody: BODY, signatureHeader: sign(BODY, "other"), secret: SECRET }),
    { ok: false, reason: "bad_digest" }
  );
  assert.deepEqual(
    verifyCreemSignature({ rawBody: BODY + " ", signatureHeader: sign(BODY), secret: SECRET }),
    { ok: false, reason: "bad_digest" }
  );
});

test("a correct signature passes", () => {
  assert.deepEqual(verifyCreemSignature({ rawBody: BODY, signatureHeader: sign(BODY), secret: SECRET }), { ok: true });
  assert.deepEqual(
    verifyCreemSignature({ rawBody: BODY, signatureHeader: sign(BODY).toUpperCase(), secret: SECRET }),
    { ok: true },
    "hex case is not significant"
  );
});

test("event classification", () => {
  for (const t of ["subscription.paid", "subscription.active", "subscription.trialing", "subscription.scheduled_cancel"]) {
    assert.equal(classifyCreemEvent(t, "active"), "grant", t);
  }
  assert.equal(classifyCreemEvent("subscription.update", "active"), "grant");
  assert.equal(classifyCreemEvent("subscription.update", "trialing"), "grant");
  assert.equal(classifyCreemEvent("subscription.update", "scheduled_cancel"), "grant");
  for (const t of ["subscription.past_due", "subscription.unpaid", "subscription.expired"]) {
    assert.equal(classifyCreemEvent(t), "grace", `${t} is grace, never a revocation`);
  }
  assert.equal(classifyCreemEvent("subscription.update", "past_due"), "grace");
  assert.equal(classifyCreemEvent("subscription.canceled"), "revoke");
  assert.equal(classifyCreemEvent("subscription.paused"), "revoke");
  assert.equal(classifyCreemEvent("subscription.update", "canceled"), "revoke");
  assert.equal(classifyCreemEvent("subscription.update", "unknown"), "ignore");
  for (const t of ["checkout.completed", "refund.created", "dispute.created", "credits.added"]) {
    assert.equal(classifyCreemEvent(t, "active"), "ignore", t);
  }
});

test("subscription.paid normalises to a priced grant", () => {
  const e = parseCreemWebhook(fixture("subscription_paid"));
  assert.equal(e.provider, "creem");
  assert.equal(e.action, "grant");
  assert.equal(e.eventId, "evt_paid");
  assert.equal(e.occurredAt, new Date(1790000000000).toISOString(), "epoch ms becomes ISO");
  assert.equal(e.userId, "user_abc");
  assert.equal(e.subscriptionId, "sub_creem_1");
  assert.equal(e.customerId, "cust_1");
  assert.equal(e.periodEnd, "2026-11-01T00:00:00.000Z");
  assert.deepEqual(
    [e.billing.unit_amount, e.billing.currency, e.billing.billing_interval, e.billing.billing_frequency, e.billing.price_id, e.billing.provider_status],
    [399, "USD", "month", 1, "prod_monthly", "active"]
  );
  assert.equal(e.billing.scheduled_cancel_at, null);
});

test("a scheduled cancel is a grant that records when it will end", () => {
  const e = parseCreemWebhook(fixture("subscription_scheduled_cancel"));
  assert.equal(e.action, "grant");
  assert.equal(e.billing.scheduled_cancel_at, "2026-11-01T00:00:00.000Z");
});

test("past_due is grace and canceled revokes", () => {
  assert.equal(parseCreemWebhook(fixture("subscription_past_due")).action, "grace");
  assert.equal(parseCreemWebhook(fixture("subscription_canceled")).action, "revoke");
});

test("checkout.completed is ignored and its object is never read as a subscription", () => {
  const e = parseCreemWebhook(fixture("checkout_completed"));
  assert.equal(e.action, "ignore");
});

test("annual and multi-month products map their interval", () => {
  const year = resolveCreemBilling({ product: { id: "p", price: 2999, currency: "usd", billing_period: "every-year" } }, false);
  assert.deepEqual([year.billing_interval, year.billing_frequency, year.currency], ["year", 1, "USD"]);
  const quarter = resolveCreemBilling({ product: { billing_period: "every-three-months" } }, false);
  assert.deepEqual([quarter.billing_interval, quarter.billing_frequency], ["month", 3]);
  const none = resolveCreemBilling({}, false);
  assert.deepEqual([none.unit_amount, none.currency, none.billing_interval], [null, null, null]);
});

test("a body that is not JSON throws rather than being trusted", () => {
  assert.throws(() => parseCreemWebhook("not json"));
});

test("Creem sells one product per plan, whatever the buyer's country", () => {
  const env = process.env;
  process.env = {
    ...env,
    CREEM_API_KEY: "k",
    CREEM_PRODUCT_MONTHLY: "prod_std_m",
    CREEM_PRODUCT_ANNUAL: "prod_std_a",
  };
  try {
    assert.equal(creemProductId("monthly"), "prod_std_m");
    assert.equal(creemProductId("annual"), "prod_std_a");
    delete process.env.CREEM_PRODUCT_ANNUAL;
    assert.throws(() => creemProductId("annual"), /not configured/);
  } finally {
    process.env = env;
  }
});
