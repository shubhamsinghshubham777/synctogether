// Token scheme shared with supabase/functions/_shared/media_edge.ts.
// message = `${objectKey}\n${exp}`  (objectKey decoded, exp unix seconds)
// sig     = base64url(HMAC-SHA256(secret, message)), no padding.
// Keep both copies byte-identical in behaviour: each has the same test vector.

const enc = new TextEncoder();

export function b64urlEncode(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function b64urlDecode(s: string): Uint8Array | null {
  if (!/^[A-Za-z0-9_-]+$/.test(s)) return null;
  const pad = "=".repeat((4 - (s.length % 4)) % 4);
  try {
    const bin = atob(s.replace(/-/g, "+").replace(/_/g, "/") + pad);
    return Uint8Array.from(bin, (c) => c.charCodeAt(0));
  } catch {
    return null;
  }
}

function hmacKey(secret: string, usage: "sign" | "verify"): Promise<CryptoKey> {
  return crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, [usage]);
}

const message = (objectKey: string, exp: number) => enc.encode(`${objectKey}\n${exp}`);

export async function signToken(secret: string, objectKey: string, exp: number): Promise<string> {
  const mac = await crypto.subtle.sign("HMAC", await hmacKey(secret, "sign"), message(objectKey, exp));
  return b64urlEncode(new Uint8Array(mac));
}

export type TokenVerdict = "ok" | "malformed" | "expired" | "too_far" | "bad_signature";

/** crypto.subtle.verify compares in constant time; there is no string compare of the MAC. */
export async function verifyToken(
  secret: string,
  objectKey: string,
  expRaw: string | null,
  sigRaw: string | null,
  nowSeconds: number,
  maxTtlSeconds: number,
): Promise<TokenVerdict> {
  if (!expRaw || !sigRaw || !/^\d{1,12}$/.test(expRaw)) return "malformed";
  const exp = Number(expRaw);
  const sig = b64urlDecode(sigRaw);
  if (!sig || sig.length !== 32) return "malformed";
  // Check the signature first so expiry/ttl state is not an oracle for forged tokens.
  const ok = await crypto.subtle.verify("HMAC", await hmacKey(secret, "verify"), sig, message(objectKey, exp));
  if (!ok) return "bad_signature";
  if (exp <= nowSeconds) return "expired";
  if (exp - nowSeconds > maxTtlSeconds) return "too_far";
  return "ok";
}
