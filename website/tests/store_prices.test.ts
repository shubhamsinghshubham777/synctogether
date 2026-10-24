import test from "node:test";
import assert from "node:assert/strict";
import { createPrivateKey, generateKeyPairSync, sign, verify } from "node:crypto";
import {
  currentPriceByTerritory,
  decodePrivateKey,
  signAscJwt,
  subscriptionIdsByProduct,
} from "../lib/store_prices_logic.ts";

const point = (id: string, customerPrice: string) => ({ id, type: "subscriptionPricePoints", attributes: { customerPrice } });
const price = (territory: string, pointId: string, startDate: string | null) => ({
  id: `${territory}-${pointId}`,
  type: "subscriptionPrices",
  attributes: { startDate },
  relationships: {
    territory: { data: { id: territory, type: "territories" } },
    subscriptionPricePoint: { data: { id: pointId, type: "subscriptionPricePoints" } },
  },
});

test("the price in force wins over a scheduled one and over the original", () => {
  const body = {
    data: [
      price("PAK", "a", null),
      price("PAK", "b", "2026-01-01"),
      price("PAK", "c", "2099-01-01"),
      price("IND", "d", null),
    ],
    included: [point("a", "581"), point("b", "600"), point("c", "999"), point("d", "199.00")],
  };
  assert.deepEqual(currentPriceByTerritory(body, new Date("2026-10-24")), { PAK: 600, IND: 199 });
});

test("unreadable or non-positive price points are ignored", () => {
  const body = { data: [price("PAK", "a", null)], included: [point("a", "free")] };
  assert.deepEqual(currentPriceByTerritory(body, new Date()), {});
});

test("subscriptions are found by product id", () => {
  const ids = subscriptionIdsByProduct({
    included: [
      { id: "1", type: "subscriptions", attributes: { productId: "app.x.monthly" } },
      { id: "2", type: "subscriptionGroups", attributes: { productId: "ignored" } },
    ],
  });
  assert.deepEqual(ids, { "app.x.monthly": "1" });
});

test("the private key decodes from base64 and from an escaped PEM alike", () => {
  const pem = generateKeyPairSync("ec", { namedCurve: "P-256" }).privateKey.export({ type: "pkcs8", format: "pem" }) as string;
  const fromB64 = decodePrivateKey(Buffer.from(pem).toString("base64"));
  const fromEscaped = decodePrivateKey(pem.trim().replace(/\n/g, "\\n"));
  assert.equal(fromB64.trim(), pem.trim());
  assert.equal(fromEscaped.trim(), pem.trim());
});

test("the JWT carries the Apple claims and verifies as ES256", () => {
  const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
  const key = createPrivateKey(privateKey.export({ type: "pkcs8", format: "pem" }));
  const jwt = signAscJwt((d) => sign("sha256", Buffer.from(d), { key, dsaEncoding: "ieee-p1363" }), "KID", "ISS", 1000);
  const [h, p, sig] = jwt.split(".");
  assert.deepEqual(JSON.parse(Buffer.from(h, "base64url").toString()), { alg: "ES256", kid: "KID", typ: "JWT" });
  assert.deepEqual(JSON.parse(Buffer.from(p, "base64url").toString()), { iss: "ISS", iat: 1000, exp: 1300, aud: "appstoreconnect-v1" });
  assert.equal(
    verify("sha256", Buffer.from(`${h}.${p}`), { key: publicKey, dsaEncoding: "ieee-p1363" }, Buffer.from(sig, "base64url")),
    true,
  );
});

import { currencyForCountry } from "../lib/constants.ts";

test("the pricing picker defaults by country, and unknown means USD", () => {
  assert.equal(currencyForCountry("IN"), "INR");
  assert.equal(currencyForCountry("pk"), "PKR");
  assert.equal(currencyForCountry("US"), "USD");
  assert.equal(currencyForCountry(null), "USD");
  assert.equal(currencyForCountry(undefined), "USD");
});
