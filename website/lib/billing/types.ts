import type { BillingDetails, EventAction } from "./core.ts";

export type ProviderId = "creem";

export type SignatureFailure =
  | "missing_secret"
  | "missing_signature"
  | "malformed_signature"
  | "stale_timestamp"
  | "bad_digest";

export type SignatureVerdict =
  | { ok: true }
  | { ok: false; reason: SignatureFailure };

/**
 * What every provider's webhook is reduced to before it touches the database.
 * `apply.ts` only ever sees this, which is what keeps the two providers from
 * drifting apart in how they grant, grace and revoke.
 */
export type NormalizedEvent = {
  provider: ProviderId;
  eventId: string | null;
  /** ISO timestamp of when the provider says it happened. */
  occurredAt: string | null;
  action: EventAction;
  userId: string | null;
  subscriptionId: string | null;
  customerId: string | null;
  /** ISO. Null means "cannot be dated" - never invented. */
  periodEnd: string | null;
  billing: BillingDetails;
  rawType: string;
};

export type CheckoutInput = {
  userId: string;
  email?: string;
  /** The provider's customer id when we already have one on file. */
  customerId?: string;
  plan: "monthly" | "annual";
  successUrl: string;
};

export interface BillingProvider {
  id: ProviderId;
  isConfigured(): boolean;
  /** Must fail closed. `now` is epoch milliseconds, injectable for tests. */
  verifyWebhook(rawBody: string, headers: Headers, now?: number): SignatureVerdict;
  parseWebhook(rawBody: string): NormalizedEvent;
  createCheckout(input: CheckoutInput): Promise<{ url: string }>;
  cancelAtPeriodEnd(
    subscriptionId: string
  ): Promise<{ ok: true } | { ok: false; status: number }>;
  /** The fulfil fallback, for a webhook that has not landed yet. */
  findActiveSubscription(
    userId: string,
    hint?: { checkoutId?: string }
  ): Promise<NormalizedEvent | null>;
}
