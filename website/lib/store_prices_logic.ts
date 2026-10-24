// Pure helpers for reading Apple's App Store Connect subscription prices. No
// network and no Next.js imports, so `node --test` can exercise them directly.

export type TerritoryPrices = Record<string, { monthly?: number; annual?: number }>;

/** The key is stored base64-encoded (one line, safe in any env UI); a raw PEM
 *  with real or `\n`-escaped newlines is accepted too. */
export function decodePrivateKey(raw: string): string {
  const v = raw.trim();
  if (v.includes("BEGIN")) return v.replace(/\\n/g, "\n");
  return Buffer.from(v, "base64").toString("utf8");
}

function b64url(input: Buffer | string): string {
  return Buffer.from(input).toString("base64url");
}

/** ES256 JWT for the App Store Connect API (5 minute life; Apple allows 20). */
export function signAscJwt(
  sign: (data: string) => Buffer,
  keyId: string,
  issuerId: string,
  nowSeconds: number,
): string {
  const header = b64url(JSON.stringify({ alg: "ES256", kid: keyId, typ: "JWT" }));
  const payload = b64url(
    JSON.stringify({ iss: issuerId, iat: nowSeconds, exp: nowSeconds + 300, aud: "appstoreconnect-v1" }),
  );
  const data = `${header}.${payload}`;
  return `${data}.${b64url(sign(data))}`;
}

interface JsonApiResource {
  id: string;
  type: string;
  attributes?: Record<string, unknown>;
  relationships?: Record<string, { data?: { id: string; type: string } | null }>;
}

/** subscriptions in a group listing -> productId -> subscription id */
export function subscriptionIdsByProduct(body: { included?: JsonApiResource[] }): Record<string, string> {
  const out: Record<string, string> = {};
  for (const r of body.included ?? []) {
    const productId = r.attributes?.productId;
    if (r.type === "subscriptions" && typeof productId === "string") out[productId] = r.id;
  }
  return out;
}

/**
 * One subscription's `prices?include=subscriptionPricePoint,territory`
 * response -> the price in force today per territory. A territory can carry a
 * scheduled future price, so take the latest `startDate` that has begun; a null
 * start is the original price and loses to any dated one.
 */
export function currentPriceByTerritory(
  body: { data?: JsonApiResource[]; included?: JsonApiResource[] },
  now: Date,
): Record<string, number> {
  const points = new Map<string, number>();
  for (const r of body.included ?? []) {
    const price = Number(r.attributes?.customerPrice);
    if (r.type === "subscriptionPricePoints" && Number.isFinite(price) && price > 0) points.set(r.id, price);
  }

  const best: Record<string, { start: number; price: number }> = {};
  for (const r of body.data ?? []) {
    const territory = r.relationships?.territory?.data?.id;
    const pointId = r.relationships?.subscriptionPricePoint?.data?.id;
    const price = pointId ? points.get(pointId) : undefined;
    if (!territory || price === undefined) continue;

    const startDate = r.attributes?.startDate;
    const start = typeof startDate === "string" ? Date.parse(startDate) : -Infinity;
    if (start > now.getTime()) continue;
    if (!best[territory] || start > best[territory].start) best[territory] = { start, price };
  }
  return Object.fromEntries(Object.entries(best).map(([t, v]) => [t, v.price]));
}
