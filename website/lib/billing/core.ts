/**
 * The provider-neutral decisions behind subscription webhooks, kept apart from
 * any route or database so they can be tested over plain values.
 *
 * Written for Paddle first and kept provider-neutral.
 */

/**
 * What an event should do to the stored subscription.
 *
 * `grace` is the one worth explaining. `past_due` used to be grouped with
 * `canceled` into a single "deactivate" branch that hard-deleted the row, so
 * the first failed retry on an expired card revoked premium from somebody who
 * had every intention of paying. Providers dun for days; the row is left alone
 * and allowed to lapse on `current_period_end` if the payment never recovers.
 */
export type EventAction = "grant" | "revoke" | "grace" | "ignore";

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

/** Columns on `subscriptions` that record what a provider subscription charges. */
export interface BillingDetails {
  price_id: string | null;
  unit_amount: number | null;
  currency: string | null;
  billing_interval: string | null;
  billing_frequency: number | null;
  provider_status: string | null;
  scheduled_cancel_at: string | null;
}

const BILLING_KEYS: (keyof BillingDetails)[] = [
  "price_id",
  "unit_amount",
  "currency",
  "billing_interval",
  "billing_frequency",
  "provider_status",
  "scheduled_cancel_at",
];

export const EMPTY_BILLING: BillingDetails = {
  price_id: null,
  unit_amount: null,
  currency: null,
  billing_interval: null,
  billing_frequency: null,
  provider_status: null,
  scheduled_cancel_at: null,
};

/**
 * Whether a grant would change nothing. Suppressing the write matters because
 * `subscriptions` is published to `supabase_realtime`, so a redundant upsert
 * wakes every subscribed client's `EntitlementService` for no reason. A change
 * of price, status or scheduled cancellation is not redundant even when the
 * entitlement is unchanged - the revenue figures depend on it.
 */
export function isRedundantGrant(
  existing:
    | ({ tier?: string | null; current_period_end?: string | null } & Partial<BillingDetails>)
    | null,
  periodEnd: string,
  billing?: BillingDetails
): boolean {
  if (existing?.tier !== "premium" || existing?.current_period_end !== periodEnd) return false;
  if (!billing) return true;
  return BILLING_KEYS.every((k) => {
    const a = existing[k] ?? null;
    const b = billing[k];
    // Postgres answers `+00:00`, providers send `Z`: compare the instant.
    if (k === "scheduled_cancel_at" && a && b) return Date.parse(String(a)) === Date.parse(String(b));
    return a === b;
  });
}

/** Rows that came from a person at a console rather than a seller of record. */
export const NON_PROVIDER_SOURCES = new Set(["manual", "debug"]);

export interface ExistingRow {
  tier?: string | null;
  source?: string | null;
  current_period_end?: string | null;
  provider_subscription_id?: string | null;
}

/**
 * May this event change this row? A `canceled` from provider A must never
 * revoke a grant that provider B made, and a stray subscription from one
 * provider must not overwrite a live one from another.
 *
 * The row is protected only while it is *currently premium from a different
 * provider*. A manual or debug grant is not a provider, so a real purchase may
 * replace it; a lapsed or free row is up for grabs. An event naming the very
 * subscription the row holds always targets it.
 */
export function eventTargetsRow(
  event: { provider: string; subscriptionId: string | null },
  existing: ExistingRow | null,
  now: Date = new Date()
): boolean {
  if (!existing) return true;
  if (
    existing.source === event.provider &&
    event.subscriptionId &&
    existing.provider_subscription_id === event.subscriptionId
  ) {
    return true;
  }
  if (!existing.source || existing.source === event.provider) return true;
  if (NON_PROVIDER_SOURCES.has(existing.source)) return true;

  const premium = existing.tier === "premium";
  const current =
    existing.current_period_end == null || new Date(existing.current_period_end) > now;
  return !(premium && current);
}
