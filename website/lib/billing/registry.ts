import type { BillingProvider, ProviderId } from "./types.ts";
import { creemProvider } from "./providers/creem.ts";

/**
 * Creem is the only seller of record, but the seam stays: every `subscriptions`
 * row records its provider in `source`, and cancel, fulfil and webhook handling
 * dispatch on that. Adding a provider is one adapter and one entry here - never
 * a plugin registry. A saved card belongs to the seller of record, so moving
 * subscribers between providers is impossible; a second provider would run
 * beside Creem until its subscriptions lapse.
 */
const PROVIDERS: Record<ProviderId, BillingProvider> = {
  creem: creemProvider,
};

export function isProviderId(value: string | null | undefined): value is ProviderId {
  return value === "creem";
}

export function providerFor(id: string | null | undefined): BillingProvider | null {
  return isProviderId(id) ? PROVIDERS[id] : null;
}

/** Where new checkouts go. */
export function activeProvider(): BillingProvider {
  const provider = creemProvider;
  if (!provider.isConfigured() && process.env.NODE_ENV === "production") {
    // Loudly, rather than opening a checkout nobody configured.
    throw new Error("Creem is not configured; refusing to open a checkout.");
  }
  return provider;
}
