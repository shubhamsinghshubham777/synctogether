// Verification of App Store signed payloads (JWS), on WebCrypto.
//
// This replaces `SignedDataVerifier` from @apple/app-store-server-library,
// which cannot run on the Edge runtime: it calls
// `crypto.X509Certificate.prototype.toString`, which Deno's node compat layer
// throws `ERR_NOT_IMPLEMENTED` for - so every genuine Apple payload was
// rejected. The checks are the same ones Apple's library makes:
//
//   1. `alg` is ES256 and `x5c` is exactly [leaf, intermediate, root].
//   2. The root is byte-for-byte Apple Root CA - G3 (pinned, not merely
//      "some root that validates").
//   3. Leaf is signed by intermediate, intermediate by root.
//   4. Leaf carries Apple's receipt-signing OID, intermediate Apple's WWDR
//      intermediate OID - without these, any certificate Apple ever issued
//      under G3 could sign a "transaction".
//   5. Both certificates were valid at the payload's own `signedDate` (Apple's
//      rule: an old transaction stays verifiable after its leaf expires).
//   6. The JWS signature verifies with the leaf key.
//
// Bundle id and environment are checked by the caller, which knows which
// field carries them for each payload type.

import "npm:reflect-metadata@0.2.2";
import { X509Certificate } from "npm:@peculiar/x509@2.1.0";

const LEAF_OID = "1.2.840.113635.100.6.11.1";
const INTERMEDIATE_OID = "1.2.840.113635.100.6.2.1";

export class JwsVerificationError extends Error {}

function b64urlDecode(s: string): Uint8Array<ArrayBuffer> {
  const b64 = s.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((s.length + 3) % 4);
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
}

function b64Decode(s: string): Uint8Array<ArrayBuffer> {
  return Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
}

function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

function validAt(cert: X509Certificate, at: Date): boolean {
  return cert.notBefore <= at && at <= cert.notAfter;
}

/**
 * Verifies an App Store JWS against `rootDer` and returns its decoded payload.
 * Throws `JwsVerificationError` for anything that is not a genuine payload.
 */
export async function verifyAppleJws<T extends { signedDate?: number }>(
  jws: string,
  rootDer: Uint8Array<ArrayBuffer>,
): Promise<T> {
  const parts = jws.split(".");
  if (parts.length !== 3) throw new JwsVerificationError("malformed_jws");
  const [h, p, sig] = parts;

  let header: { alg?: string; x5c?: string[] };
  let payload: T;
  try {
    header = JSON.parse(new TextDecoder().decode(b64urlDecode(h)));
    payload = JSON.parse(new TextDecoder().decode(b64urlDecode(p)));
  } catch {
    throw new JwsVerificationError("malformed_jws");
  }
  if (header.alg !== "ES256") throw new JwsVerificationError("unsupported_alg");
  if (!Array.isArray(header.x5c) || header.x5c.length !== 3) {
    throw new JwsVerificationError(
      `bad_chain_length (x5c ${Array.isArray(header.x5c) ? header.x5c.length : typeof header.x5c}, header keys ${Object.keys(header).join(",")})`,
    );
  }

  const [leafDer, intermediateDer, chainRootDer] = header.x5c.map(b64Decode);
  if (!bytesEqual(chainRootDer, rootDer)) throw new JwsVerificationError("untrusted_root");

  const leaf = new X509Certificate(leafDer);
  const intermediate = new X509Certificate(intermediateDer);
  const root = new X509Certificate(rootDer);

  if (!leaf.getExtension(LEAF_OID)) throw new JwsVerificationError("leaf_not_apple_receipt_signer");
  if (!intermediate.getExtension(INTERMEDIATE_OID)) {
    throw new JwsVerificationError("intermediate_not_apple_wwdr");
  }

  const at = new Date(typeof payload.signedDate === "number" ? payload.signedDate : Date.now());
  if (!validAt(leaf, at) || !validAt(intermediate, at)) {
    throw new JwsVerificationError("certificate_not_valid_at_signed_date");
  }

  const chainOk =
    (await intermediate.verify({ publicKey: root, signatureOnly: true })) &&
    (await leaf.verify({ publicKey: intermediate, signatureOnly: true }));
  if (!chainOk) throw new JwsVerificationError("bad_chain_signature");

  // JWS ES256 signatures are raw r||s, which is exactly what WebCrypto takes.
  const key = await leaf.publicKey.export({ name: "ECDSA", namedCurve: "P-256" }, ["verify"]);
  const ok = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    b64urlDecode(sig),
    new TextEncoder().encode(`${h}.${p}`),
  );
  if (!ok) throw new JwsVerificationError("bad_signature");
  return payload;
}
