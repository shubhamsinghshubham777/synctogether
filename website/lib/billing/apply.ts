import {
  eventTargetsRow,
  isRedundantGrant,
  shouldApplyEvent,
  type BillingDetails,
  type ExistingRow,
} from "./core.ts";
import type { NormalizedEvent } from "./types.ts";

/**
 * The single writer of `subscriptions` for provider events. The webhook route
 * and the fulfil fallback both end up here, so the two paths cannot drift - they
 * used to, and the fulfil path invented a 30-day period and never wrote the
 * provider ids or the event cursor.
 *
 * Revoking sets `tier` to free and dates the row rather than deleting it. The
 * row carries the provider ids the cancel route addresses and the event cursor
 * that makes replay safe, and deleting it threw both away - which is how a
 * redelivered `subscription.activated` could undo a cancellation.
 */

type Row = ExistingRow &
  Partial<BillingDetails> & { last_event_id?: string | null; last_event_at?: string | null };

/** The narrow slice of the Supabase client this needs; a fake can satisfy it. */
export interface SubscriptionsDb {
  from(table: "subscriptions"): {
    select(columns: string): {
      eq(column: string, value: string): { maybeSingle(): Promise<{ data: Row | null }> };
    };
    update(values: Record<string, unknown>): {
      eq(column: string, value: string): PromiseLike<{ error: unknown }>;
    };
    upsert(
      values: Record<string, unknown>,
      options: { onConflict: string }
    ): PromiseLike<{ error: unknown }>;
  };
}

export type ApplyResult = { status: number; body: Record<string, unknown> };

const SELECT =
  "tier, source, current_period_end, provider_subscription_id, last_event_id, last_event_at, price_id, unit_amount, currency, billing_interval, billing_frequency, provider_status, scheduled_cancel_at";

export async function applyEvent(
  db: SubscriptionsDb,
  event: NormalizedEvent,
  now: Date = new Date()
): Promise<ApplyResult> {
  const { userId } = event;
  if (!userId) {
    // Not worth retrying: a subscription with no user id attached cannot be
    // applied to anybody, so 200 stops the provider redelivering it.
    console.warn(`${event.provider} webhook without a user id:`, event.rawType);
    return { status: 200, body: { received: true } };
  }

  const table = db.from("subscriptions");
  const { data: existing } = await table.select(SELECT).eq("user_id", userId).maybeSingle();

  if (!eventTargetsRow(event, existing, now)) {
    console.warn(
      `${event.provider} ${event.rawType} for ${userId} ignored: row is premium from ${existing?.source}`
    );
    return { status: 200, body: { success: true, skipped: "other_provider_owns_row" } };
  }

  if (
    !shouldApplyEvent({
      eventId: event.eventId,
      occurredAt: event.occurredAt,
      lastEventId: existing?.last_event_id,
      lastEventAt: existing?.last_event_at,
    })
  ) {
    return { status: 200, body: { success: true, skipped: "stale_event" } };
  }

  // The cursor advances even for events that change nothing, so a later replay
  // of this one cannot be mistaken for news.
  const stamp = now.toISOString();
  // A lookup (the fulfil fallback) has no event id or time. It must not move
  // the cursor to "now", or the real webhook that follows - which happened a
  // moment earlier - would be dropped as stale; it keeps what is there.
  const cursor = {
    last_event_id: event.eventId ?? existing?.last_event_id ?? null,
    last_event_at: event.occurredAt ?? existing?.last_event_at ?? null,
    updated_at: stamp,
  };

  const { action } = event;

  if (action === "ignore" || action === "grace") {
    if (!existing) return { status: 200, body: { success: true, action } };
    // past_due is recorded so revenue figures can leave it out; entitlement is
    // untouched, per the grace rule.
    const update =
      action === "grace"
        ? { ...cursor, provider_status: event.billing.provider_status ?? "past_due" }
        : cursor;
    const { error } = await db.from("subscriptions").update(update).eq("user_id", userId);
    if (error) {
      console.error("Failed to advance subscription event cursor:", error);
      return { status: 500, body: { error: "Database error" } };
    }
    return { status: 200, body: { success: true, action } };
  }

  if (action === "revoke") {
    const { error } = await db
      .from("subscriptions")
      .update({
        ...cursor,
        tier: "free",
        current_period_end: stamp,
        provider_status: event.billing.provider_status,
        scheduled_cancel_at: null,
      })
      .eq("user_id", userId);
    if (error) {
      console.error("Failed to revoke subscription:", error);
      return { status: 500, body: { error: "Database error" } };
    }
    return { status: 200, body: { success: true, action } };
  }

  const { periodEnd } = event;
  if (!periodEnd) {
    // Better to leave the row alone and be told about it than to invent a month
    // and silently record an annual plan as monthly.
    console.error(`${event.provider} ${event.rawType} for ${userId} carried no billing period; not granting`);
    return { status: 422, body: { error: "No billing period on event" } };
  }

  if (isRedundantGrant(existing, periodEnd, event.billing)) {
    // Nothing about entitlement changed; still move the cursor so the event is
    // not reconsidered on redelivery.
    await db.from("subscriptions").update(cursor).eq("user_id", userId);
    return { status: 200, body: { success: true, deduplicated: true } };
  }

  const { error } = await db.from("subscriptions").upsert(
    {
      ...cursor,
      user_id: userId,
      tier: "premium",
      source: event.provider,
      current_period_end: periodEnd,
      ...event.billing,
      provider_subscription_id: event.subscriptionId,
      provider_customer_id: event.customerId,
    },
    { onConflict: "user_id" }
  );
  if (error) {
    console.error("Failed to upsert subscription:", error);
    return { status: 500, body: { error: "Database error" } };
  }
  return { status: 200, body: { success: true, action } };
}
