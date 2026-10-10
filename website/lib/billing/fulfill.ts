import type { NormalizedEvent } from "./types.ts";

/**
 * The fulfil fallback's decisions, apart from the route so they run without a
 * database or a provider. It exists for the gap between a checkout completing
 * and its webhook landing: the account page polls it.
 *
 * It never writes the row itself. A found subscription is handed back as a
 * `NormalizedEvent` for `applyEvent`, so there is one writer. And it never
 * invents a billing period: a subscription with no period end answers 202 and
 * leaves the row to the webhook, where it used to fabricate thirty days and so
 * record an annual plan as monthly.
 */
export interface FulfillmentInput {
  user: { id: string } | null;
  existingSub: { tier: string; current_period_end?: string | null } | null;
  /** Injectable so the expiry branch is testable without freezing the clock. */
  now?: Date;
  configured: boolean;
  lookup: () => Promise<NormalizedEvent | null>;
}

export interface FulfillmentResult {
  status: number;
  success: boolean;
  error?: string;
  /** Present only when the caller should hand it to `applyEvent`. */
  event?: NormalizedEvent;
  subscription?: unknown;
  tier?: string;
  /** True when a subscription exists but the webhook has to date it. */
  pending?: boolean;
}

export async function resolveFulfillment(input: FulfillmentInput): Promise<FulfillmentResult> {
  const { user, existingSub, configured, lookup, now = new Date() } = input;

  if (!user?.id) return { status: 401, success: false, error: "Unauthorized" };

  // A premium row only short-circuits while it is still current. Without the
  // expiry check a lapsed row would be reported as premium forever.
  const current =
    existingSub?.tier === "premium" &&
    (existingSub.current_period_end == null || new Date(existingSub.current_period_end) > now);
  if (current && existingSub) {
    return { status: 200, success: true, subscription: existingSub, tier: "premium" };
  }

  if (!configured) {
    return { status: 500, success: false, error: "Billing integration is unconfigured" };
  }

  try {
    const event = await lookup();
    if (!event || event.userId !== user.id) {
      return { status: 404, success: false, error: "No active subscription found for user" };
    }
    if (event.action !== "grant") {
      return { status: 404, success: false, error: "No active subscription found for user" };
    }
    if (!event.periodEnd) {
      return { status: 202, success: false, pending: true, error: "Waiting for the provider to confirm" };
    }
    return { status: 200, success: true, event, tier: "premium" };
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : "verification error";
    return { status: 502, success: false, error: `Verification failed: ${message}` };
  }
}
