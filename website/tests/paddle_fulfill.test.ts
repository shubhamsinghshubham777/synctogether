import test from "node:test";
import assert from "node:assert/strict";
import { validateAndResolveFulfillment } from "../lib/paddle_fulfillment.ts";

test("validateAndResolveFulfillment rejects unauthenticated callers with 401", async () => {
  const result = await validateAndResolveFulfillment({
    user: null,
    existingSub: null,
    paddleApiKey: "pdl_live_apikey_123",
    fetchPaddleSubs: async () => ({ data: [] }),
  });

  assert.equal(result.status, 401);
  assert.equal(result.success, false);
  assert.equal(result.shouldUpsert, false);
  assert.equal(result.error, "Unauthorized");
});

test("validateAndResolveFulfillment returns existing active premium subscription without calling Paddle", async () => {
  let paddleApiCalled = false;
  const existing = {
    user_id: "user_123",
    tier: "premium",
    current_period_end: "2026-10-01T00:00:00.000Z",
  };

  const result = await validateAndResolveFulfillment({
    user: { id: "user_123" },
    existingSub: existing,
    paddleApiKey: "pdl_live_apikey_123",
    fetchPaddleSubs: async () => {
      paddleApiCalled = true;
      return { data: [] };
    },
  });

  assert.equal(result.status, 200);
  assert.equal(result.success, true);
  assert.equal(result.shouldUpsert, false);
  assert.equal(paddleApiCalled, false);
  assert.deepEqual(result.subscription, existing);
});

test("validateAndResolveFulfillment rejects when Paddle API key is missing or unconfigured", async () => {
  const result = await validateAndResolveFulfillment({
    user: { id: "user_123" },
    existingSub: null,
    paddleApiKey: undefined,
    fetchPaddleSubs: async () => ({ data: [] }),
  });

  assert.equal(result.status, 500);
  assert.equal(result.success, false);
  assert.equal(result.shouldUpsert, false);
  assert.match(result.error || "", /unconfigured/i);
});

test("validateAndResolveFulfillment rejects when Paddle returns no matching subscription for user (P0 loophole fix)", async () => {
  const result = await validateAndResolveFulfillment({
    user: { id: "attacker_user_456" },
    existingSub: null,
    paddleApiKey: "pdl_live_apikey_123",
    fetchPaddleSubs: async () => ({
      data: [
        {
          id: "sub_other",
          status: "active",
          custom_data: { user_id: "different_user_789" },
          current_billing_period: { ends_at: "2026-10-01T00:00:00.000Z" },
        },
      ],
    }),
  });

  // MUST reject with 404 and NEVER allow upsert!
  assert.equal(result.status, 404);
  assert.equal(result.success, false);
  assert.equal(result.shouldUpsert, false);
  assert.equal(result.error, "No active Paddle subscription found for user");
});

test("validateAndResolveFulfillment rejects when user subscription is canceled or past_due", async () => {
  const nonActiveStatuses = ["canceled", "past_due", "paused"];

  for (const status of nonActiveStatuses) {
    const result = await validateAndResolveFulfillment({
      user: { id: "user_123" },
      existingSub: null,
      paddleApiKey: "pdl_live_apikey_123",
      fetchPaddleSubs: async () => ({
        data: [
          {
            id: "sub_1",
            status,
            custom_data: { user_id: "user_123" },
            current_billing_period: { ends_at: "2026-10-01T00:00:00.000Z" },
          },
        ],
      }),
    });

    assert.equal(result.status, 404, `Status ${status} should be rejected with 404`);
    assert.equal(result.success, false);
    assert.equal(result.shouldUpsert, false);
  }
});

test("validateAndResolveFulfillment successfully fulfills when Paddle returns an active subscription", async () => {
  const targetEndsAt = "2026-10-06T12:00:00.000Z";

  const result = await validateAndResolveFulfillment({
    user: { id: "paying_user_999" },
    existingSub: null,
    paddleApiKey: "pdl_live_apikey_123",
    fetchPaddleSubs: async () => ({
      data: [
        {
          id: "sub_valid_123",
          status: "active",
          custom_data: { user_id: "paying_user_999" },
          current_billing_period: { ends_at: targetEndsAt },
        },
      ],
    }),
  });

  assert.equal(result.status, 200);
  assert.equal(result.success, true);
  assert.equal(result.shouldUpsert, true);
  assert.equal(result.periodEnd, targetEndsAt);
  assert.equal(result.tier, "premium");
});

test("validateAndResolveFulfillment also supports trialing status from Paddle", async () => {
  const trialEndsAt = "2026-09-20T12:00:00.000Z";

  const result = await validateAndResolveFulfillment({
    user: { id: "trial_user_555" },
    existingSub: null,
    paddleApiKey: "pdl_live_apikey_123",
    fetchPaddleSubs: async () => ({
      data: [
        {
          id: "sub_trial_123",
          status: "trialing",
          custom_data: { user_id: "trial_user_555" },
          current_billing_period: { ends_at: trialEndsAt },
        },
      ],
    }),
  });

  assert.equal(result.status, 200);
  assert.equal(result.success, true);
  assert.equal(result.shouldUpsert, true);
  assert.equal(result.periodEnd, trialEndsAt);
  assert.equal(result.tier, "premium");
});
