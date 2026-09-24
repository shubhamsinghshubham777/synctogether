// deno test supabase/functions/apple-iap/apple_jws_test.ts
//
// Runs on Deno on purpose: the previous verifier type-checked and passed its
// imports, then failed on the first real payload because Deno does not
// implement part of node:crypto. A chain shaped like Apple's (root ->
// intermediate with the WWDR OID -> leaf with the receipt-signing OID) is
// minted here and pushed through the real code path.

import "npm:reflect-metadata@0.2.2";
import * as x509 from "npm:@peculiar/x509@2.1.0";
import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { verifyAppleJws } from "./apple_jws.ts";

const alg = { name: "ECDSA", namedCurve: "P-256", hash: "SHA-256" };
const appleOid = (oid: string) => new x509.Extension(oid, false, new Uint8Array([5, 0]));
const now = Date.now();
const notBefore = new Date(now - 86_400_000);
const notAfter = new Date(now + 86_400_000);

async function chain(opts: { leafOid?: string; intermediateOid?: string } = {}) {
  const rootKeys = await crypto.subtle.generateKey(alg, true, ["sign", "verify"]);
  const intKeys = await crypto.subtle.generateKey(alg, true, ["sign", "verify"]);
  const leafKeys = await crypto.subtle.generateKey(alg, true, ["sign", "verify"]);
  const root = await x509.X509CertificateGenerator.createSelfSigned({
    serialNumber: "01", name: "CN=Test Root", notBefore, notAfter, keys: rootKeys, signingAlgorithm: alg,
  });
  const intermediate = await x509.X509CertificateGenerator.create({
    serialNumber: "02", subject: "CN=Test WWDR", issuer: root.subject, notBefore, notAfter,
    publicKey: intKeys.publicKey, signingKey: rootKeys.privateKey, signingAlgorithm: alg,
    extensions: [appleOid(opts.intermediateOid ?? "1.2.840.113635.100.6.2.1")],
  });
  const leaf = await x509.X509CertificateGenerator.create({
    serialNumber: "03", subject: "CN=Test Leaf", issuer: intermediate.subject, notBefore, notAfter,
    publicKey: leafKeys.publicKey, signingKey: intKeys.privateKey, signingAlgorithm: alg,
    extensions: [appleOid(opts.leafOid ?? "1.2.840.113635.100.6.11.1")],
  });
  return { root, intermediate, leaf, leafKey: leafKeys.privateKey };
}

const b64url = (b: Uint8Array) => btoa(String.fromCharCode(...b)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const b64 = (buf: ArrayBuffer) => btoa(String.fromCharCode(...new Uint8Array(buf)));

async function sign(c: Awaited<ReturnType<typeof chain>>, payload: object, x5cRoot = c.root) {
  const header = { alg: "ES256", x5c: [c.leaf.rawData, c.intermediate.rawData, x5cRoot.rawData].map(b64) };
  const h = b64url(new TextEncoder().encode(JSON.stringify(header)));
  const p = b64url(new TextEncoder().encode(JSON.stringify(payload)));
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, c.leafKey, new TextEncoder().encode(`${h}.${p}`));
  return `${h}.${p}.${b64url(new Uint8Array(sig))}`;
}

const rootOf = (c: Awaited<ReturnType<typeof chain>>) => new Uint8Array(c.root.rawData);
const payload = { productId: "app.synctogether.premium.monthly", signedDate: now };

Deno.test("a genuine chain verifies and returns the payload", async () => {
  const c = await chain();
  const decoded = await verifyAppleJws<typeof payload>(await sign(c, payload), rootOf(c));
  assertEquals(decoded.productId, payload.productId);
});

Deno.test("a chain ending in any other root is refused", async () => {
  const c = await chain();
  const other = await chain();
  await assertRejects(async () => verifyAppleJws(await sign(c, payload, other.root), rootOf(c)), Error, "untrusted_root");
  await assertRejects(async () => verifyAppleJws(await sign(c, payload), rootOf(other)), Error, "untrusted_root");
});

Deno.test("a tampered payload is refused", async () => {
  const c = await chain();
  const [h, , s] = (await sign(c, payload)).split(".");
  const forged = b64url(new TextEncoder().encode(JSON.stringify({ ...payload, productId: "free.money" })));
  await assertRejects(() => verifyAppleJws(`${h}.${forged}.${s}`, rootOf(c)), Error, "bad_signature");
});

Deno.test("certificates without Apple's OIDs are refused", async () => {
  const noLeafOid = await chain({ leafOid: "1.2.3.4" });
  await assertRejects(async () => verifyAppleJws(await sign(noLeafOid, payload), rootOf(noLeafOid)), Error, "leaf_not_apple_receipt_signer");
  const noIntOid = await chain({ intermediateOid: "1.2.3.4" });
  await assertRejects(async () => verifyAppleJws(await sign(noIntOid, payload), rootOf(noIntOid)), Error, "intermediate_not_apple_wwdr");
});

Deno.test("a payload signed outside the certificates' validity is refused", async () => {
  const c = await chain();
  await assertRejects(
    async () => verifyAppleJws(await sign(c, { ...payload, signedDate: now + 10 * 86_400_000 }), rootOf(c)),
    Error,
    "certificate_not_valid_at_signed_date",
  );
});
