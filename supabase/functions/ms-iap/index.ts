// Microsoft Store in-app purchase: the Windows rail beside apple-iap.
//
//   POST /ms-iap/ticket  - the app, before minting a Store ID key. Caller's JWT
//                          required; answers { service_ticket }, a short-lived
//                          Entra token whose audience lets the client call
//                          StoreContext.GetCustomerPurchaseIdAsync.
//   POST /ms-iap/verify  - the app, after a purchase or on launch. Caller's JWT
//                          required; body { store_id_key }.
//
// Subscriptions are read from the Store *purchase* API (recurrences/query), not
// the collections API: collections only lists Application / Durable / Game /
// UnmanagedConsumable products and never returned our subscription add-ons.
//
// The Store sends no server notifications for subscriptions, so the app
// re-verifies on every launch and the row's expires_at runs out on its own
// when it stops doing so.
//
// Trust: the Store ID key is the beneficiary of an authenticated query to the
// Store (Entra client credentials), so Microsoft decides what that key owns.
// Binding to the account comes from the key itself: the client mints it with
// the Supabase user id as publisherUserId, and `keyBindsTo` refuses a key that
// does not carry the caller's id - a key is replayable.
//
// Secrets: MS_STORE_TENANT_ID, MS_STORE_CLIENT_ID, MS_STORE_CLIENT_SECRET
// (the Entra app tied to the Partner Center account, and listed under the
// app's "Product collections and purchases"), MS_STORE_PRODUCT_IDS
// (comma-separated Store ids of the subscription add-on(s)).

import { createClient } from "npm:@supabase/supabase-js@2.58.0";
import { decodeJwtPayload, entitlementFromRecurrences, keyBindsTo, type Recurrence } from "./ms_subscriptions.ts";

const tenant = Deno.env.get("MS_STORE_TENANT_ID") ?? "";
const clientId = Deno.env.get("MS_STORE_CLIENT_ID") ?? "";
const clientSecret = Deno.env.get("MS_STORE_CLIENT_SECRET") ?? "";
const productIds = new Set(
  (Deno.env.get("MS_STORE_PRODUCT_IDS") ?? "").split(",").map((s) => s.trim()).filter(Boolean),
);

/** Audience for authenticating our own calls to the Store. */
const STORE_AUDIENCE = "https://onestore.microsoft.com";
/** Audience the *client* needs to mint a Store ID key for the purchase API. */
const PURCHASE_KEY_AUDIENCE = "https://onestore.microsoft.com/b2b/keys/create/purchase";

async function entraToken(resource: string): Promise<string> {
  const res = await fetch(`https://login.microsoftonline.com/${tenant}/oauth2/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "client_credentials",
      client_id: clientId,
      client_secret: clientSecret,
      resource,
    }),
  });
  if (!res.ok) throw new Error(`entra token ${res.status}: ${(await res.text()).slice(0, 300)}`);
  return (await res.json()).access_token as string;
}

/** Subscriptions the key's owner is entitled to, with Microsoft's raw answer
 * (truncated, never containing the key) so an unexpected shape can be read. */
async function queryRecurrences(
  token: string,
  storeIdKey: string,
): Promise<{ items: Recurrence[]; raw: string }> {
  const items: Recurrence[] = [];
  let raw = "";
  let continuationToken: string | undefined;
  do {
    const res = await fetch("https://purchase.mp.microsoft.com/v8.0/b2b/recurrences/query", {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({ b2bKey: storeIdKey, ...(continuationToken ? { continuationToken } : {}) }),
    });
    if (!res.ok) throw new Error(`recurrences query ${res.status}: ${(await res.text()).slice(0, 300)}`);
    const answer = await res.json();
    if (!raw) raw = JSON.stringify(answer).slice(0, 600);
    items.push(...((answer.items ?? []) as Recurrence[]));
    continuationToken = typeof answer.continuationToken === "string" ? answer.continuationToken : undefined;
  } while (continuationToken);
  return { items, raw };
}

async function signedInUser(req: Request) {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return null;
  const userClient = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data } = await userClient.auth.getUser();
  return data?.user ?? null;
}

async function ticket(req: Request): Promise<Response> {
  const user = await signedInUser(req);
  if (!user) return json({ error: "not_authenticated" }, 401);
  if (user.is_anonymous) return json({ error: "guest_cannot_purchase" }, 403);
  const serviceTicket = await entraToken(PURCHASE_KEY_AUDIENCE);
  console.log(`ms-iap ticket: issued for ${user.id}`);
  return json({ service_ticket: serviceTicket });
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

  let key: unknown;
  try {
    key = (await req.json())?.store_id_key;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  if (typeof key !== "string" || key.length === 0) return json({ error: "invalid_body" }, 400);

  const claims = decodeJwtPayload(key);
  if (!keyBindsTo(claims, user.id)) {
    console.warn(`ms-iap verify: key not minted for ${user.id}`);
    return json({ error: "account_mismatch" }, 403);
  }

  const { items, raw } = await queryRecurrences(await entraToken(STORE_AUDIENCE), key);
  const now = Date.now();
  const entitlement = entitlementFromRecurrences(items, productIds, now);
  // Ids and states only, never the key: enough to diagnose a "nothing_to_restore".
  console.log(
    `ms-iap verify: ${items.length} subscription(s) for ${user.id}; matched=${entitlement ? "yes" : "no"}`,
    JSON.stringify(items.map((i) => ({ productId: i.productId, state: i.recurrenceState, expires: i.expirationTime }))),
  );
  if (!entitlement) {
    // A key for the wrong API (collections vs purchase) is the likely culprit
    // when this is empty for an account that does hold a subscription.
    console.log("ms-iap verify: empty", JSON.stringify({ aud: claims?.aud, answer: raw }));
    return json({ error: "nothing_to_restore" }, 404);
  }

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data, error } = await admin.rpc("apply_microsoft_subscription", {
    p_user_id: user.id,
    p_purchase_id: entitlement.purchaseId,
    p_product_id: entitlement.productId,
    p_sku_id: entitlement.skuId,
    p_expires_at: entitlement.expiresAt,
    p_revoked_at: entitlement.revokedAt,
    p_auto_renew: entitlement.autoRenew,
    p_observed_at: new Date(now).toISOString(),
  });
  if (error) throw error;
  if (data === "owned_elsewhere") return json({ error: "owned_elsewhere" }, 409);
  // Whether the subscription is live right now, so the app does not celebrate
  // a cancelled or lapsed one just because the row was written.
  const active = entitlement.revokedAt === null && !!entitlement.expiresAt && Date.parse(entitlement.expiresAt) > now;
  return json({ outcome: data, active });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  if (!tenant || !clientId || !clientSecret || productIds.size === 0) {
    // Our misconfiguration: 500 so the app leaves the purchase unfinished and retries.
    console.error("ms-iap: Store credentials or MS_STORE_PRODUCT_IDS are not set");
    return json({ error: "not_configured" }, 500);
  }
  try {
    const path = new URL(req.url).pathname;
    if (path.endsWith("/verify")) return await verify(req);
    if (path.endsWith("/ticket")) return await ticket(req);
    return json({ error: "not_found" }, 404);
  } catch (e) {
    console.error("ms-iap failed:", e);
    return json({ error: "server_error" }, 500);
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
