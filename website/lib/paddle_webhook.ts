import crypto from "crypto";

/**
 * The parts of webhook handling that are decisions over plain values, kept
 * apart from the route so they can be tested without a database - the same
 * seam `paddle_fulfillment.ts` already uses.
 *
 * This exists because the previous verification failed *open*. Both of its
 * guards were `if (thing_we_need)`, so a caller who simply omitted the
 * `paddle-signature` header, or a deployment missing PADDLE_WEBHOOK_SECRET_KEY,
 * skipped verification entirely and reached the handler - which then granted
 * premium to whatever `custom_data.user_id` the body named. Everything here
 * fails closed instead: the only way out of `verifyPaddleSignature` with
 * `ok: true` is a well-formed, fresh, correct digest.
 */

/** Paddle signs `${ts}:${rawBody}`; five minutes is their documented guidance. */
export const MAX_WEBHOOK_AGE_SECONDS = 300;

const HEX_64 = /^[0-9a-f]{64}$/i;

export type SignatureFailure =
  | "missing_secret"
  | "missing_signature"
  | "malformed_signature"
  | "stale_timestamp"
  | "bad_digest";

export type SignatureVerdict =
  | { ok: true }
  | { ok: false; reason: SignatureFailure };

export function parseSignatureHeader(
  header: string | null | undefined
): { ts: string; h1: string } | null {
  if (!header) return null;
  const parts: Record<string, string> = {};
  for (const segment of header.split(";")) {
    const index = segment.indexOf("=");
    if (index <= 0) continue;
    parts[segment.slice(0, index).trim()] = segment.slice(index + 1).trim();
  }
  const { ts, h1 } = parts;
  if (!ts || !h1) return null;
  return { ts, h1 };
}

export function verifyPaddleSignature({
  rawBody,
  signatureHeader,
  secret,
  nowSeconds = Math.floor(Date.now() / 1000),
  maxAgeSeconds = MAX_WEBHOOK_AGE_SECONDS,
}: {
  rawBody: string;
  signatureHeader: string | null | undefined;
  secret: string | undefined;
  nowSeconds?: number;
  maxAgeSeconds?: number;
}): SignatureVerdict {
  // A missing secret is our misconfiguration, not a hostile caller, and it must
  // never be the reason a body is trusted.
  if (!secret || secret.trim() === "") {
    return { ok: false, reason: "missing_secret" };
  }
  if (!signatureHeader) return { ok: false, reason: "missing_signature" };

  const parsed = parseSignatureHeader(signatureHeader);
  if (!parsed) return { ok: false, reason: "malformed_signature" };

  // `Buffer.from(x, "hex")` truncates silently on anything non-hex, which would
  // turn a malformed signature into a short buffer rather than a rejection.
  if (!HEX_64.test(parsed.h1)) return { ok: false, reason: "malformed_signature" };

  const ts = Number(parsed.ts);
  if (!Number.isFinite(ts)) return { ok: false, reason: "malformed_signature" };

  // Without this a captured webhook replays forever; paired with the event
  // ordering below, that meant a replayed `activated` could undo a cancellation.
  if (Math.abs(nowSeconds - ts) > maxAgeSeconds) {
    return { ok: false, reason: "stale_timestamp" };
  }

  const expected = crypto
    .createHmac("sha256", secret)
    .update(`${parsed.ts}:${rawBody}`)
    .digest();
  const provided = Buffer.from(parsed.h1, "hex");

  if (provided.length !== expected.length) {
    return { ok: false, reason: "bad_digest" };
  }
  if (!crypto.timingSafeEqual(expected, provided)) {
    return { ok: false, reason: "bad_digest" };
  }
  return { ok: true };
}

/**
 * What an event should do to the stored subscription.
 *
 * `grace` is the one worth explaining. `past_due` used to be grouped with
 * `canceled` into a single "deactivate" branch that hard-deleted the row, so
 * the first failed retry on an expired card revoked premium from somebody who
 * had every intention of paying. Paddle dunns for days; the row should simply
 * be left alone and allowed to lapse on `current_period_end` if the payment
 * never recovers.
 */
export type EventAction = "grant" | "revoke" | "grace" | "ignore";

const GRANTING_EVENTS = new Set([
  "subscription.activated",
  "subscription.created",
  "subscription.updated",
  "subscription.resumed",
]);

export function classifyEvent(eventType: string, status?: string): EventAction {
  if (eventType === "subscription.canceled" || eventType === "subscription.paused") {
    return "revoke";
  }
  if (eventType === "subscription.past_due") return "grace";

  // `subscription.updated` carries every lifecycle change, so the status on the
  // payload decides rather than the event name.
  if (status === "canceled" || status === "paused") return "revoke";
  if (status === "past_due") return "grace";

  if (GRANTING_EVENTS.has(eventType)) {
    if (status && status !== "active" && status !== "trialing") return "ignore";
    return "grant";
  }

  // `transaction.completed` is deliberately absent: it used to grant a flat
  // 30 days when the payload carried no billing period, which recorded an
  // annual purchase as monthly. The subscription.* events already cover the
  // whole lifecycle.
  return "ignore";
}

/**
 * Webhooks arrive at least once and out of order, so an event is applied only
 * if it is strictly newer than the last one applied to that row. A repeat of
 * the same event id is never newer, which covers replay.
 */
export function shouldApplyEvent({
  eventId,
  occurredAt,
  lastEventId,
  lastEventAt,
}: {
  eventId?: string | null;
  occurredAt?: string | null;
  lastEventId?: string | null;
  lastEventAt?: string | null;
}): boolean {
  if (eventId && lastEventId && eventId === lastEventId) return false;
  if (!occurredAt || !lastEventAt) return true;

  const incoming = Date.parse(occurredAt);
  const applied = Date.parse(lastEventAt);
  if (!Number.isFinite(incoming) || !Number.isFinite(applied)) return true;
  return incoming > applied;
}

/**
 * The period end to store. Deliberately returns null rather than inventing
 * "now + 30 days" when the payload has no billing period: a null here means
 * the row cannot be dated, which is a state worth seeing, whereas a fabricated
 * month silently misrecords an annual plan.
 */
export function resolvePeriodEnd(data: {
  current_billing_period?: { ends_at?: string | null } | null;
  billing_period?: { ends_at?: string | null } | null;
}): string | null {
  return (
    data?.current_billing_period?.ends_at ||
    data?.billing_period?.ends_at ||
    null
  );
}

/**
 * Whether a grant would change nothing. Suppressing the write matters because
 * `subscriptions` is published to `supabase_realtime`, so a redundant upsert
 * wakes every subscribed client's `EntitlementService` for no reason.
 */
export function isRedundantGrant(
  existing: { tier?: string | null; current_period_end?: string | null } | null,
  periodEnd: string
): boolean {
  return existing?.tier === "premium" && existing?.current_period_end === periodEnd;
}
