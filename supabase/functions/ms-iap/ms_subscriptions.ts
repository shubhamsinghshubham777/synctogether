// Pure decisions for the Microsoft Store rail, kept free of I/O so Deno tests
// can cover them without the Store.
//
// Subscriptions live in the Store *purchase* API (`recurrences/query`), not the
// collections API: collections lists only Application / Durable / Game /
// UnmanagedConsumable products and never returned our subscription add-ons.

/** One subscription as `purchase.mp.microsoft.com/v8.0/b2b/recurrences/query` reports it. */
export type Recurrence = {
  id?: string;
  productId?: string;
  skuId?: string;
  /** None | Active | Inactive | Canceled | InDunning | Failed */
  recurrenceState?: string;
  expirationTime?: string;
  /** Expiry including the billing-retry grace period. */
  expirationTimeWithGrace?: string;
  cancellationDate?: string;
  autoRenew?: boolean;
  isTrial?: boolean;
};

export type Entitlement = {
  purchaseId: string;
  productId: string;
  skuId: string;
  expiresAt: string | null;
  revokedAt: string | null;
  autoRenew: boolean | null;
};

/** A perpetual subscription (state `None`) has no expiry to report. */
const FAR_FUTURE = "9999-12-31T23:59:59.000Z";

/** The payload of a Store ID key (a JWT). The signature is not checked here:
 * the key is only ever used as the beneficiary of an authenticated Store
 * query, and Microsoft rejects a forged one. */
export function decodeJwtPayload(jwt: string): Record<string, unknown> | null {
  const parts = jwt.split(".");
  if (parts.length < 2) return null;
  try {
    const b64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const padded = b64 + "=".repeat((4 - (b64.length % 4)) % 4);
    const parsed = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(padded), (c) => c.charCodeAt(0))));
    return parsed && typeof parsed === "object" ? parsed : null;
  } catch {
    return null;
  }
}

/**
 * Whether a Store ID key was minted for `userId`. The client passes the
 * Supabase user id as the key's publisherUserId; rather than trust one claim
 * name, any string claim equal to the caller's id counts. Confirm which claim
 * Microsoft uses with a real key and tighten this to it (see docs).
 */
export function keyBindsTo(payload: Record<string, unknown> | null, userId: string): boolean {
  if (!payload) return false;
  const want = userId.toLowerCase();
  return Object.values(payload).some((v) => typeof v === "string" && v.toLowerCase() === want);
}

function iso(value: string | undefined): string | null {
  const ms = value ? Date.parse(value) : NaN;
  return Number.isNaN(ms) ? null : new Date(ms).toISOString();
}

/**
 * The entitlement to record among the items that are ours: one that is live
 * now beats one that is not, then the latest-ending wins.
 *
 * Billing retry (`InDunning`) is grace, not loss, so it runs to
 * `expirationTimeWithGrace`; `Canceled` and `Failed` are revocations, dated;
 * `Inactive` is a subscription that simply ran out, so it is not.
 */
export function entitlementFromRecurrences(
  items: Recurrence[],
  productIds: Set<string>,
  now: number,
): Entitlement | null {
  let best: Entitlement | null = null;
  let bestLive = false;
  let bestEnd = -Infinity;
  for (const item of items) {
    if (!item.id || !item.productId || !productIds.has(item.productId)) continue;
    const state = item.recurrenceState ?? "";
    const expiration = iso(item.expirationTime);
    const graceExpiration = iso(item.expirationTimeWithGrace);

    let expiresAt: string | null;
    let revokedAt: string | null = null;
    switch (state) {
      case "None":
        expiresAt = FAR_FUTURE;
        break;
      case "Active":
        // Grace is for a failed renewal, not a courtesy on one that is healthy.
        expiresAt = expiration ?? graceExpiration;
        break;
      case "InDunning":
        expiresAt = graceExpiration ?? expiration;
        break;
      case "Inactive":
        expiresAt = expiration;
        break;
      case "Canceled":
      case "Failed":
        expiresAt = expiration ?? new Date(now).toISOString();
        revokedAt = iso(item.cancellationDate) ?? new Date(now).toISOString();
        break;
      default:
        continue; // A state we do not know is not one to grant premium on.
    }
    if (!expiresAt) continue; // Cannot date it, so cannot honour it.

    const end = Date.parse(expiresAt);
    const live = revokedAt === null && end > now;
    if (best !== null && (bestLive !== live ? bestLive : end <= bestEnd)) continue;
    best = {
      purchaseId: item.id,
      productId: item.productId,
      skuId: item.skuId ?? "",
      expiresAt,
      revokedAt,
      autoRenew: item.autoRenew ?? null,
    };
    bestLive = live;
    bestEnd = end;
  }
  return best;
}
