import { createPrivateKey, sign } from "node:crypto";
import { PATRON_PRICES, type PatronCurrency, type PatronPriceTable } from "./constants";
import {
  currentPriceByTerritory,
  decodePrivateKey,
  signAscJwt,
  subscriptionIdsByProduct,
} from "./store_prices_logic";

const ASC = "https://api.appstoreconnect.apple.com/v1";
// Numeric app id from the App Store URL, and the two product ids from
// lib/profile/apple_iap_service.dart (permanent once created in App Store Connect).
const APP_ID = process.env.APPLE_APP_APPLE_ID || "6809185202";
const MONTHLY = "app.synctogether.premium.monthly";
const ANNUAL = "app.synctogether.premium.annual";
const TERRITORIES: Record<string, PatronCurrency> = { USA: "USD", IND: "INR", PAK: "PKR" };

async function ascGet(path: string, token: string) {
  const res = await fetch(`${ASC}${path}`, {
    headers: { Authorization: `Bearer ${token}` },
    next: { revalidate: 86400 },
  });
  if (!res.ok) throw new Error(`App Store Connect ${res.status} for ${path.split("?")[0]}`);
  return res.json();
}

/**
 * Patron prices as Apple charges them, overlaid on the constants. Server-only:
 * the key never leaves this module. Any failure (no key, Apple down, a role
 * that cannot read pricing) returns the constants, so the page always renders.
 * Microsoft's per-market steps can differ from Apple's by a rupee or so, which
 * the pricing copy says; Apple is the one source shown.
 */
export async function getPatronPrices(): Promise<{ prices: PatronPriceTable; live: boolean }> {
  const keyId = process.env.ASC_KEY_ID;
  const issuerId = process.env.ASC_ISSUER_ID;
  const rawKey = process.env.ASC_PRIVATE_KEY;
  if (!keyId || !issuerId || !rawKey) return { prices: PATRON_PRICES, live: false };

  try {
    const key = createPrivateKey(decodePrivateKey(rawKey));
    const token = signAscJwt(
      (data) => sign("sha256", Buffer.from(data), { key, dsaEncoding: "ieee-p1363" }),
      keyId,
      issuerId,
      Math.floor(Date.now() / 1000),
    );

    const groups = await ascGet(
      `/apps/${APP_ID}/subscriptionGroups?include=subscriptions&fields[subscriptions]=productId&limit=50`,
      token,
    );
    const ids = subscriptionIdsByProduct(groups);
    if (!ids[MONTHLY] || !ids[ANNUAL]) throw new Error("subscription products not found");

    const territories = Object.keys(TERRITORIES).join(",");
    const [monthly, annual] = await Promise.all(
      [ids[MONTHLY], ids[ANNUAL]].map(async (id) =>
        currentPriceByTerritory(
          await ascGet(
            `/subscriptions/${id}/prices?filter[territory]=${territories}&include=subscriptionPricePoint,territory&limit=200`,
            token,
          ),
          new Date(),
        ),
      ),
    );

    const prices: PatronPriceTable = structuredClone(PATRON_PRICES);
    let live = false;
    for (const [territory, currency] of Object.entries(TERRITORIES)) {
      if (monthly[territory] && annual[territory]) {
        prices[currency] = { monthly: monthly[territory], annual: annual[territory] };
        live = true;
      }
    }
    return { prices, live };
  } catch (e) {
    console.error("store prices unavailable, using constants:", e instanceof Error ? e.message : e);
    return { prices: PATRON_PRICES, live: false };
  }
}
