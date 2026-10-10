import crypto from "crypto";
import type { BillingDetails, EventAction } from "../core.ts";
import { EMPTY_BILLING } from "../core.ts";
import type {
  BillingProvider,
  CheckoutInput,
  NormalizedEvent,
  SignatureVerdict,
} from "../types.ts";

/**
 * The Creem adapter (https://docs.creem.io).
 *
 * Creem signs the raw body with HMAC-SHA256 and sends the hex digest in
 * `creem-signature`. There is **no timestamp**, so replay
 * protection rests entirely on the event-id / `created_at` cursor in
 * `shouldApplyEvent`. And Creem publishes no static IPs, so there is no
 * `checkSource`.
 */

// ---- environment ----------------------------------------------------------

export function creemApiHost(): string {
  return process.env.CREEM_ENVIRONMENT === "test"
    ? "https://test-api.creem.io"
    : "https://api.creem.io";
}

function usable(value: string | undefined): value is string {
  return Boolean(value && value.trim() !== "" && !value.includes("xxx"));
}

export function isCreemConfigured(): boolean {
  return (
    usable(process.env.CREEM_API_KEY) &&
    usable(process.env.CREEM_PRODUCT_MONTHLY) &&
    usable(process.env.CREEM_PRODUCT_ANNUAL)
  );
}

/**
 * One USD price for everyone. Creem has no per-country overrides and only bills
 * USD/EUR, so a local-currency promise (INR 199, parity tiers) cannot be kept;
 * rather than ship a price that drifts with the exchange rate, there is none.
 */
export function creemProductId(plan: "monthly" | "annual"): string {
  const base = plan === "annual" ? "CREEM_PRODUCT_ANNUAL" : "CREEM_PRODUCT_MONTHLY";
  const value = process.env[base];
  if (!usable(value)) {
    throw new Error(`CREEM_PRODUCT_${plan.toUpperCase()} is not configured; refusing to open a checkout.`);
  }
  return value;
}

// ---- signature ------------------------------------------------------------

const HEX_64 = /^[0-9a-f]{64}$/i;

export function verifyCreemSignature({
  rawBody,
  signatureHeader,
  secret,
}: {
  rawBody: string;
  signatureHeader: string | null | undefined;
  secret: string | undefined;
}): SignatureVerdict {
  // A missing secret is our misconfiguration and must never be the reason a
  // body is trusted.
  if (!secret || secret.trim() === "") return { ok: false, reason: "missing_secret" };
  if (!signatureHeader) return { ok: false, reason: "missing_signature" };

  const provided = signatureHeader.trim();
  // `Buffer.from(x, "hex")` truncates silently on anything non-hex.
  if (!HEX_64.test(provided)) return { ok: false, reason: "malformed_signature" };

  const expected = crypto.createHmac("sha256", secret).update(rawBody).digest();
  const given = Buffer.from(provided, "hex");
  if (given.length !== expected.length || !crypto.timingSafeEqual(expected, given)) {
    return { ok: false, reason: "bad_digest" };
  }
  return { ok: true };
}

// ---- event mapping --------------------------------------------------------

const REVOKE_STATUSES = new Set(["canceled", "cancelled", "paused"]);
// `expired` is grace, not revoke: Creem says retries can still follow, so the
// row is left to lapse on its own period end.
const GRACE_STATUSES = new Set(["past_due", "unpaid", "expired"]);
const GRANT_TYPES = new Set([
  "subscription.paid",
  "subscription.active",
  "subscription.trialing",
  "subscription.scheduled_cancel",
  "subscription.update",
]);
const LIVE_STATUSES = new Set(["active", "trialing", "scheduled_cancel"]);

export function classifyCreemEvent(eventType: string, status?: string | null): EventAction {
  if (eventType === "subscription.canceled" || eventType === "subscription.paused") return "revoke";
  if (
    eventType === "subscription.past_due" ||
    eventType === "subscription.unpaid" ||
    eventType === "subscription.expired"
  ) {
    return "grace";
  }

  // `subscription.update` carries every lifecycle change, so the status on the
  // payload decides rather than the event name.
  if (status && REVOKE_STATUSES.has(status)) return "revoke";
  if (status && GRACE_STATUSES.has(status)) return "grace";

  if (GRANT_TYPES.has(eventType)) {
    if (status && !LIVE_STATUSES.has(status)) return "ignore";
    return "grant";
  }

  // `checkout.completed` is deliberately ignored, the same doctrine as a
  // payment-completed event: the subscription.* events cover the lifecycle.
  // `refund.created` is logged by the caller; dispute.* and credits.* are not
  // entitlement events.
  return "ignore";
}

interface CreemProduct {
  id?: string;
  price?: number | null;
  currency?: string | null;
  billing_period?: string | null;
}

interface CreemSubscription {
  id?: string;
  status?: string | null;
  product?: CreemProduct | string | null;
  customer?: { id?: string } | string | null;
  metadata?: { user_id?: string } | null;
  current_period_end_date?: string | number | null;
  scheduled_cancel_at?: string | number | null;
}

/** Creem timestamps are ISO strings on entities and epoch milliseconds on events. */
function toIso(value: string | number | null | undefined): string | null {
  if (value == null || value === "") return null;
  const ms = typeof value === "number" ? value : Number.isNaN(Number(value)) ? Date.parse(value) : Number(value);
  return Number.isFinite(ms) ? new Date(ms).toISOString() : null;
}

const PERIODS: Record<string, { interval: string; frequency: number }> = {
  "every-month": { interval: "month", frequency: 1 },
  "every-three-months": { interval: "month", frequency: 3 },
  "every-six-months": { interval: "month", frequency: 6 },
  "every-year": { interval: "year", frequency: 1 },
};

export function resolveCreemBilling(
  sub: CreemSubscription | null | undefined,
  scheduledCancel: boolean
): BillingDetails {
  const product = typeof sub?.product === "object" ? sub.product : null;
  const period = product?.billing_period ? PERIODS[product.billing_period] : undefined;
  const currency = product?.currency?.toUpperCase() ?? null;
  const price = product?.price;
  return {
    ...EMPTY_BILLING,
    price_id: product?.id ?? (typeof sub?.product === "string" ? sub.product : null),
    unit_amount: typeof price === "number" && Number.isInteger(price) && price >= 0 ? price : null,
    currency: currency && /^[A-Z]{3}$/.test(currency) ? currency : null,
    billing_interval: period?.interval ?? null,
    billing_frequency: period?.frequency ?? null,
    provider_status: sub?.status ?? null,
    scheduled_cancel_at: scheduledCancel ? toIso(sub?.scheduled_cancel_at) ?? toIso(sub?.current_period_end_date) : null,
  };
}

function normalize(
  sub: CreemSubscription,
  meta: { eventId: string | null; occurredAt: string | null; rawType: string; action: EventAction }
): NormalizedEvent {
  const scheduledCancel = sub?.status === "scheduled_cancel" || meta.rawType === "subscription.scheduled_cancel";
  return {
    provider: "creem",
    eventId: meta.eventId,
    occurredAt: meta.occurredAt,
    action: meta.action,
    userId: sub?.metadata?.user_id ?? null,
    subscriptionId: sub?.id ?? null,
    customerId: typeof sub?.customer === "string" ? sub.customer : sub?.customer?.id ?? null,
    periodEnd: toIso(sub?.current_period_end_date),
    billing: resolveCreemBilling(sub, scheduledCancel),
    rawType: meta.rawType,
  };
}

export function parseCreemWebhook(rawBody: string): NormalizedEvent {
  const event = JSON.parse(rawBody);
  const type: string = event?.eventType ?? event?.event_type ?? "";
  const object: CreemSubscription = event?.object ?? {};
  if (type.startsWith("refund.")) console.warn("Creem refund event:", event?.id);
  return normalize(object, {
    eventId: event?.id ?? null,
    occurredAt: toIso(event?.created_at),
    rawType: type,
    // Only subscription objects are entitlement events; a checkout/refund/
    // dispute object has a different shape and must never be read as one.
    action: type.startsWith("subscription.") ? classifyCreemEvent(type, object?.status) : "ignore",
  });
}

// ---- operations -----------------------------------------------------------

function headers() {
  return { "x-api-key": process.env.CREEM_API_KEY ?? "", "Content-Type": "application/json" };
}

async function createCheckout(input: CheckoutInput): Promise<{ url: string }> {
  const res = await fetch(`${creemApiHost()}/v1/checkouts`, {
    method: "POST",
    headers: headers(),
    body: JSON.stringify({
      product_id: creemProductId(input.plan),
      request_id: input.userId,
      metadata: { user_id: input.userId },
      ...(input.email ? { customer: { email: input.email } } : {}),
      success_url: input.successUrl,
    }),
  });
  if (!res.ok) throw new Error(`Creem checkout create failed (${res.status}): ${await res.text()}`);
  const url: string | undefined = (await res.json())?.checkout_url;
  if (!url) throw new Error("Creem returned no checkout_url");
  return { url };
}

async function cancelAtPeriodEnd(subscriptionId: string) {
  const res = await fetch(`${creemApiHost()}/v1/subscriptions/${encodeURIComponent(subscriptionId)}/cancel`, {
    method: "POST",
    headers: headers(),
    body: JSON.stringify({ mode: "scheduled", onExecute: "cancel" }),
  });
  if (!res.ok) {
    console.error(`Creem cancellation failed (${res.status}): ${await res.text()}`);
    return { ok: false as const, status: res.status };
  }
  return { ok: true as const };
}

/** With no checkout id there is nothing safe to look up, so the webhook is relied on. */
async function findActiveSubscription(
  userId: string,
  hint?: { checkoutId?: string }
): Promise<NormalizedEvent | null> {
  if (!hint?.checkoutId) return null;
  const res = await fetch(
    `${creemApiHost()}/v1/checkouts?checkout_id=${encodeURIComponent(hint.checkoutId)}`,
    { headers: headers() }
  );
  // An unknown checkout id is simply "nothing found", not an outage.
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`Creem API responded with status ${res.status}`);
  const checkout = await res.json();

  // Ownership: the checkout must have been created for this user. `request_id`
  // is what createCheckout set to the user id.
  const owner = checkout?.metadata?.user_id ?? checkout?.request_id;
  if (owner !== userId) return null;

  let sub: CreemSubscription | string | null = checkout?.subscription ?? null;
  if (typeof sub === "string") {
    const subRes = await fetch(
      `${creemApiHost()}/v1/subscriptions?subscription_id=${encodeURIComponent(sub)}`,
      { headers: headers() }
    );
    if (!subRes.ok) throw new Error(`Creem API responded with status ${subRes.status}`);
    sub = await subRes.json();
  }
  if (!sub || typeof sub === "string") return null;
  if (sub.status !== "active" && sub.status !== "trialing") return null;

  // The subscription may not carry our metadata; the checkout vouched for it.
  const withOwner: CreemSubscription = { ...sub, metadata: { ...(sub.metadata ?? {}), user_id: userId } };
  return normalize(withOwner, { eventId: null, occurredAt: null, rawType: "lookup", action: "grant" });
}

export const creemProvider: BillingProvider = {
  id: "creem",
  isConfigured: isCreemConfigured,

  verifyWebhook(rawBody, requestHeaders) {
    return verifyCreemSignature({
      rawBody,
      signatureHeader: requestHeaders.get("creem-signature"),
      secret: process.env.CREEM_WEBHOOK_SECRET,
    });
  },

  parseWebhook: parseCreemWebhook,
  createCheckout,
  cancelAtPeriodEnd,
  findActiveSubscription,
  // No previewPrices: the static localised table is used.
};
