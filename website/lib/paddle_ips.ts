/**
 * Paddle's webhook source IP allowlist, fetched from Paddle rather than
 * hard-coded.
 *
 * https://api.paddle.com/ips is the source of truth and Paddle changes it, so a
 * literal list in the repo is a list that silently goes stale and one day
 * rejects every live webhook. The addresses arrive in `data.ipv4_cidrs` as /32
 * CIDRs; we compare on the bare address, since a /32 is a single host and
 * parsing prefix lengths we know to be 32 would be inventing work.
 *
 * This is defence in depth *behind* signature verification, never instead of
 * it: an allowlisted IP still has to present a valid `paddle-signature`. It
 * exists so an unsigned flood from anywhere else is dropped before it reaches
 * the HMAC, the JSON parse or the database.
 *
 * Fails **open** on a fetch error, deliberately. If Paddle's own IP endpoint is
 * unreachable we cannot distinguish a hostile caller from a caller we simply
 * cannot classify, and rejecting everything would discard real subscription
 * events - which is worse than falling back to the signature check that is
 * already mandatory and already fails closed.
 */

const IPS_ENDPOINT = "https://api.paddle.com/ips";
/** Paddle changes this rarely; an hour bounds staleness without hammering them. */
const TTL_MS = 60 * 60 * 1000;

type Cache = { addresses: Set<string>; fetchedAt: number };
let cache: Cache | null = null;
let inFlight: Promise<Cache | null> | null = null;

export function parseIpv4Cidrs(payload: unknown): string[] {
  const cidrs = (payload as { data?: { ipv4_cidrs?: unknown } })?.data?.ipv4_cidrs;
  if (!Array.isArray(cidrs)) return [];
  return cidrs
    .filter((c): c is string => typeof c === "string")
    // "34.237.3.244/32" -> "34.237.3.244". A bare address is accepted too.
    .map((c) => c.split("/")[0].trim())
    .filter((a) => a.length > 0);
}

async function loadAddresses(): Promise<Cache | null> {
  const response = await fetch(IPS_ENDPOINT, {
    headers: { Accept: "application/json" },
    cache: "no-store",
  });
  if (!response.ok) {
    throw new Error(`Paddle IP endpoint returned ${response.status}`);
  }
  const addresses = parseIpv4Cidrs(await response.json());
  if (addresses.length === 0) {
    // An empty list would allowlist nothing and reject every webhook, so treat
    // it as a bad response rather than as "Paddle has no IPs".
    throw new Error("Paddle IP endpoint returned no addresses");
  }
  return { addresses: new Set(addresses), fetchedAt: Date.now() };
}

/** The allowlist, cached for an hour. Null when it could not be determined. */
export async function paddleWebhookIps(): Promise<Set<string> | null> {
  if (cache && Date.now() - cache.fetchedAt < TTL_MS) return cache.addresses;

  // One fetch at a time: a burst of webhooks must not become a burst of
  // requests to Paddle.
  if (!inFlight) {
    inFlight = loadAddresses()
      .then((fresh) => {
        if (fresh) cache = fresh;
        return fresh;
      })
      .catch((error) => {
        console.error("Could not refresh Paddle webhook IP allowlist:", error);
        return null;
      })
      .finally(() => {
        inFlight = null;
      });
  }
  const result = await inFlight;
  // A failed refresh falls back to a stale list before it gives up entirely -
  // a list from an hour ago is far better information than none.
  return result?.addresses ?? cache?.addresses ?? null;
}

/**
 * The caller's address, read from the proxy headers Vercel sets.
 * `x-forwarded-for` is a comma-separated chain appended to by each hop, and the
 * *first* entry is the original client.
 */
export function callerAddress(headers: Headers): string | null {
  const real = headers.get("x-real-ip");
  if (real) return real.trim();
  const forwarded = headers.get("x-forwarded-for");
  if (!forwarded) return null;
  const first = forwarded.split(",")[0]?.trim();
  return first || null;
}

export type IpVerdict = "allowed" | "rejected" | "unverifiable";

export function classifyCaller(
  address: string | null,
  allowlist: Set<string> | null
): IpVerdict {
  if (!allowlist) return "unverifiable";
  if (!address) return "unverifiable";
  return allowlist.has(address) ? "allowed" : "rejected";
}
