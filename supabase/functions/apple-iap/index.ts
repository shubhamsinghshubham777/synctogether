// App Store In-App Purchase: the Apple rail beside the Paddle webhook.
//
//   POST /apple-iap/verify  - the app, right after a purchase or restore.
//                             Caller's JWT required; body { signed_transaction }.
//   POST /apple-iap/notify  - App Store Server Notifications V2. No JWT; the
//                             signed payload is the authentication.
//
// Trust comes from one place: `verifyAppleJws` (apple_jws.ts) checks every
// JWS chains to a pinned Apple Root CA - G3, and `decode` then checks it
// belongs to our bundle id (and, in Production, our app id). Nothing unsigned
// reaches `apply_apple_transaction`, which then decides binding and ordering.
//
// The account binding is `appAccountToken`, which the client sets to the
// Supabase user id at purchase. `/verify` refuses a transaction whose token is
// not the caller - a signed transaction is replayable, so without that check
// anyone holding one could attach somebody else's purchase to themselves.
//
// Both environments are accepted in production on purpose: App Review buys
// with sandbox accounts against the production build, and Apple's guidance is
// to fall back to sandbox rather than reject.
//
// Secrets: APPLE_BUNDLE_ID, APPLE_APP_APPLE_ID (numeric; required by Apple to
// verify Production payloads).

import { createClient } from "npm:@supabase/supabase-js@2.58.0";
import { JwsVerificationError, verifyAppleJws } from "./apple_jws.ts";
import { APPLE_ROOT_CA_G3_BASE64 } from "./apple_root_ca_g3.ts";

const bundleId = Deno.env.get("APPLE_BUNDLE_ID") ?? "";
const appAppleId = Number(Deno.env.get("APPLE_APP_APPLE_ID") ?? "") || undefined;
const root = Uint8Array.from(atob(APPLE_ROOT_CA_G3_BASE64), (c) => c.charCodeAt(0));

type Environment = "Production" | "Sandbox";

type AppleTransaction = {
  originalTransactionId: string;
  transactionId: string;
  productId: string;
  bundleId: string;
  environment: Environment;
  appAccountToken?: string;
  expiresDate?: number;
  revocationDate?: number;
  signedDate?: number;
};

type AppleRenewalInfo = {
  autoRenewStatus?: number;
  gracePeriodExpiresDate?: number;
  environment?: Environment;
  signedDate?: number;
};

type AppleNotification = {
  notificationType: string;
  subtype?: string;
  notificationUUID?: string;
  signedDate?: number;
  data?: {
    bundleId?: string;
    appAppleId?: number;
    environment?: Environment;
    signedTransactionInfo?: string;
    signedRenewalInfo?: string;
  };
};

/**
 * Verifies `jws` and applies the bundle/app checks for its payload. Returns
 * null for anything that is not ours; the reason is logged, because a refusal
 * looks identical from outside and that is what hid the Deno X509 failure.
 */
async function decode<T extends { signedDate?: number }>(
  jws: string,
  kind: string,
  check: (payload: T) => string | null,
): Promise<T | null> {
  try {
    const payload = await verifyAppleJws<T>(jws, root);
    const problem = check(payload);
    if (problem) {
      console.warn(`apple-iap: ${kind} refused: ${problem}`);
      return null;
    }
    return payload;
  } catch (e) {
    const reason = e instanceof JwsVerificationError ? e.message : String(e);
    console.warn(`apple-iap: ${kind} failed verification: ${reason}`);
    if (!(e instanceof JwsVerificationError)) console.error(e);
    return null;
  }
}

function checkEnvironment(env: unknown): string | null {
  return env === "Production" || env === "Sandbox" ? null : `unexpected environment ${env}`;
}

const decodeTransaction = (jws: string) =>
  decode<AppleTransaction>(jws, "transaction", (tx) =>
    tx.bundleId !== bundleId ? `bundle ${tx.bundleId}` : checkEnvironment(tx.environment));

const decodeRenewal = (jws: string) => decode<AppleRenewalInfo>(jws, "renewal info", () => null);

const decodeNotification = (jws: string) =>
  decode<AppleNotification>(jws, "notification", (n) => {
    if (n.data?.bundleId !== bundleId) return `bundle ${n.data?.bundleId}`;
    // Apple's rule: a Production payload must also name our app.
    if (n.data?.environment === "Production" && appAppleId && n.data.appAppleId !== appAppleId) {
      return `app ${n.data.appAppleId}`;
    }
    return checkEnvironment(n.data?.environment);
  });

const admin = () =>
  createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

type Outcome = "applied" | "stale" | "owned_elsewhere" | "unbound";

async function apply(
  userId: string | null,
  tx: AppleTransaction,
  renewal: AppleRenewalInfo | null,
  signedAt: number,
): Promise<Outcome> {
  // A failed renewal inside Apple's billing grace period keeps premium until
  // the grace end - the Paddle `past_due` rule: a card problem is not a
  // revocation.
  const entitledUntil = Math.max(tx.expiresDate ?? 0, renewal?.gracePeriodExpiresDate ?? 0);
  const { data, error } = await admin().rpc("apply_apple_transaction", {
    p_user_id: userId,
    p_original_transaction_id: tx.originalTransactionId,
    p_transaction_id: tx.transactionId,
    p_product_id: tx.productId,
    p_environment: tx.environment,
    p_expires_at: entitledUntil ? new Date(entitledUntil).toISOString() : null,
    p_revoked_at: tx.revocationDate ? new Date(tx.revocationDate).toISOString() : null,
    p_auto_renew: renewal ? renewal.autoRenewStatus === 1 : null,
    p_signed_at: new Date(signedAt).toISOString(),
  });
  if (error) throw error;
  return data as Outcome;
}

async function verify(req: Request): Promise<Response> {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "not_authenticated" }, 401);
  const userClient = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData } = await userClient.auth.getUser();
  const user = userData?.user;
  if (!user) return json({ error: "not_authenticated" }, 401);
  if (user.is_anonymous) return json({ error: "guest_cannot_purchase" }, 403);

  let signed: unknown;
  try {
    signed = (await req.json())?.signed_transaction;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  if (typeof signed !== "string" || signed.length === 0) return json({ error: "invalid_body" }, 400);

  const tx = await decodeTransaction(signed);
  if (!tx || !tx.originalTransactionId || !tx.transactionId) {
    return json({ error: "invalid_transaction" }, 400);
  }
  if (tx.appAccountToken?.toLowerCase() !== user.id.toLowerCase()) {
    console.warn(`apple-iap verify: token mismatch for ${user.id} on ${tx.originalTransactionId}`);
    return json({ error: "account_mismatch" }, 403);
  }

  const outcome = await apply(user.id, tx, null, tx.signedDate ?? Date.now());
  if (outcome === "owned_elsewhere") return json({ error: "owned_elsewhere" }, 409);
  return json({ outcome });
}

async function notify(req: Request): Promise<Response> {
  let signedPayload: unknown;
  try {
    signedPayload = (await req.json())?.signedPayload;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  if (typeof signedPayload !== "string") return json({ error: "invalid_body" }, 400);

  const payload = await decodeNotification(signedPayload);
  if (!payload) {
    console.error("apple-iap notify: payload failed verification");
    return json({ error: "invalid_signature" }, 401);
  }

  const signedTx = payload.data?.signedTransactionInfo;
  if (!signedTx) {
    // TEST, and the summary notifications that carry no transaction.
    return json({ received: true, type: payload.notificationType });
  }
  const tx = await decodeTransaction(signedTx);
  if (!tx) return json({ error: "invalid_transaction" }, 401);
  const signedRenewal = payload.data?.signedRenewalInfo;
  const renewal = signedRenewal ? await decodeRenewal(signedRenewal) : null;

  const outcome = await apply(tx.appAccountToken ?? null, tx, renewal, payload.signedDate ?? Date.now());
  if (outcome === "owned_elsewhere" || outcome === "unbound") {
    // Permanent for this payload; 200 so Apple stops redelivering it.
    console.warn(`apple-iap notify: ${outcome} ${payload.notificationType} ${tx.originalTransactionId}`);
  }
  return json({ outcome, type: payload.notificationType });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  if (!bundleId) {
    // Our misconfiguration: 500 so Apple keeps retrying until it is fixed.
    console.error("apple-iap: APPLE_BUNDLE_ID is not set");
    return json({ error: "not_configured" }, 500);
  }
  const path = new URL(req.url).pathname;
  try {
    if (path.endsWith("/verify")) return await verify(req);
    if (path.endsWith("/notify")) return await notify(req);
    return json({ error: "not_found" }, 404);
  } catch (e) {
    console.error("apple-iap failed:", e);
    return json({ error: "server_error" }, 500);
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
