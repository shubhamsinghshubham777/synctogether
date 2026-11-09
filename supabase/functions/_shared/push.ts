// Push delivery: APNs (iOS, macOS), FCM (Android) and WNS (Windows).
//
// The database decides what to send and when (public.push_outbox); this file
// only turns a row into each provider's request and classifies the answer. It
// takes `fetch` as a parameter so every path is testable without a network.
//
// Every provider is optional. A platform whose credentials are not set is
// skipped, never failed, so a fork that only ships on one platform needs only
// that platform's secrets.

export type Platform = "ios" | "macos" | "android" | "windows";
export type Token = { platform: Platform; token: string; environment: "production" | "sandbox" };
export type PushRow = {
  id: number;
  user_id: string;
  kind: string;
  title: string;
  body: string;
  data: Record<string, unknown>;
  expires_at: string | null;
  tokens: Token[];
};

// ok: delivered. invalid: the token is dead, drop it. retry: try again later.
// skipped: this platform is not configured here.
export type Outcome = "ok" | "invalid" | "retry" | "skipped";

export type Fetch = typeof fetch;

const encoder = new TextEncoder();

function b64url(bytes: Uint8Array | string): string {
  const raw = typeof bytes === "string" ? encoder.encode(bytes) : bytes;
  let s = "";
  for (const b of raw) s += String.fromCharCode(b);
  return btoa(s).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

function pemToDer(pem: string): Uint8Array<ArrayBuffer> {
  const body = pem.replace(/-----[A-Z ]+-----/g, "").replace(/\\n/g, "").replace(/\s+/g, "");
  const bin = atob(body);
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}

/** Secrets arrive with literal "\n" when set through an env file; undo that. */
export function normalizePem(pem: string): string {
  return pem.replaceAll("\\n", "\n");
}

function secondsUntil(iso: string | null, fallback: number, now = Date.now()): number {
  if (!iso) return fallback;
  return Math.max(0, Math.floor((Date.parse(iso) - now) / 1000));
}

const isUrgent = (row: PushRow) => row.kind === "call";

// ---------------------------------------------------------------------------
// APNs
// ---------------------------------------------------------------------------
export type ApnsConfig = {
  keyId: string;
  teamId: string;
  privateKey: string;
  topics: { ios?: string; macos?: string };
};

export function apnsConfigFromEnv(env: (k: string) => string | undefined): ApnsConfig | null {
  const keyId = env("APNS_KEY_ID");
  const teamId = env("APNS_TEAM_ID");
  const privateKey = env("APNS_PRIVATE_KEY");
  const bundle = env("APNS_BUNDLE_ID");
  if (!keyId || !teamId || !privateKey) return null;
  return {
    keyId,
    teamId,
    privateKey,
    topics: { ios: env("APNS_TOPIC_IOS") ?? bundle, macos: env("APNS_TOPIC_MACOS") ?? bundle },
  };
}

export function apnsPayload(row: PushRow): Record<string, unknown> {
  return {
    aps: {
      alert: { title: row.title, body: row.body },
      sound: "default",
      "thread-id": row.kind,
      // A call is the one push worth breaking through a Focus mode.
      "interruption-level": isUrgent(row) ? "time-sensitive" : "active",
    },
    kind: row.kind,
    ...row.data,
  };
}

export function apnsHeaders(row: PushRow, topic: string, jwt: string, now = Date.now()): Record<string, string> {
  const ttl = secondsUntil(row.expires_at, 86400, now);
  return {
    authorization: `bearer ${jwt}`,
    "apns-topic": topic,
    "apns-push-type": "alert",
    "apns-priority": isUrgent(row) || row.kind === "date_night_reminder" ? "10" : "5",
    // Absolute epoch seconds; 0 would mean "deliver once, never store".
    "apns-expiration": String(Math.floor(now / 1000) + ttl),
    "apns-collapse-id": row.kind.slice(0, 64),
    "content-type": "application/json",
  };
}

let apnsJwtCache: { jwt: string; at: number; key: string } | null = null;

export async function apnsJwt(cfg: ApnsConfig, now = Date.now()): Promise<string> {
  const cacheKey = `${cfg.keyId}:${cfg.teamId}`;
  // Apple refuses tokens older than an hour and throttles reissuing them.
  if (apnsJwtCache && apnsJwtCache.key === cacheKey && now - apnsJwtCache.at < 50 * 60_000) {
    return apnsJwtCache.jwt;
  }
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(normalizePem(cfg.privateKey)),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const header = b64url(JSON.stringify({ alg: "ES256", kid: cfg.keyId }));
  const claims = b64url(JSON.stringify({ iss: cfg.teamId, iat: Math.floor(now / 1000) }));
  const sig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    encoder.encode(`${header}.${claims}`),
  );
  const jwt = `${header}.${claims}.${b64url(new Uint8Array(sig))}`;
  apnsJwtCache = { jwt, at: now, key: cacheKey };
  return jwt;
}

export function resetApnsJwtCache() {
  apnsJwtCache = null;
}

const APNS_DEAD = new Set(["BadDeviceToken", "Unregistered", "DeviceTokenNotForTopic", "TopicDisallowed"]);

export async function sendApns(cfg: ApnsConfig, row: PushRow, t: Token, f: Fetch, now = Date.now()): Promise<Outcome> {
  const topic = t.platform === "macos" ? cfg.topics.macos : cfg.topics.ios;
  if (!topic) return "skipped";
  const host = t.environment === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
  const res = await f(`https://${host}/3/device/${encodeURIComponent(t.token)}`, {
    method: "POST",
    headers: apnsHeaders(row, topic, await apnsJwt(cfg, now), now),
    body: JSON.stringify(apnsPayload(row)),
  });
  if (res.status === 200) return "ok";
  let reason = "";
  try {
    reason = (await res.json()).reason ?? "";
  } catch { /* no body */ }
  if (res.status === 410 || APNS_DEAD.has(reason)) return "invalid";
  if (reason === "ExpiredProviderToken" || reason === "InvalidProviderToken") resetApnsJwtCache();
  return "retry";
}

// ---------------------------------------------------------------------------
// FCM (HTTP v1)
// ---------------------------------------------------------------------------
export type FcmConfig = { projectId: string; clientEmail: string; privateKey: string };

export function fcmConfigFromEnv(env: (k: string) => string | undefined): FcmConfig | null {
  const raw = env("FCM_SERVICE_ACCOUNT");
  if (!raw) return null;
  try {
    const j = JSON.parse(raw);
    if (!j.project_id || !j.client_email || !j.private_key) return null;
    return { projectId: j.project_id, clientEmail: j.client_email, privateKey: j.private_key };
  } catch {
    return null;
  }
}

export function fcmMessage(row: PushRow, token: string, now = Date.now()): Record<string, unknown> {
  const data: Record<string, string> = { kind: row.kind };
  for (const [k, v] of Object.entries(row.data)) data[k] = String(v);
  return {
    message: {
      token,
      notification: { title: row.title, body: row.body },
      data,
      android: {
        priority: isUrgent(row) || row.kind === "date_night_reminder" ? "HIGH" : "NORMAL",
        ttl: `${secondsUntil(row.expires_at, 86400, now)}s`,
        collapse_key: row.kind.slice(0, 64),
        notification: { channel_id: isUrgent(row) ? "calls" : "default", tag: row.kind },
      },
    },
  };
}

let fcmTokenCache: { token: string; exp: number; email: string } | null = null;

async function fcmAccessToken(cfg: FcmConfig, f: Fetch, now = Date.now()): Promise<string> {
  if (fcmTokenCache && fcmTokenCache.email === cfg.clientEmail && fcmTokenCache.exp > now + 60_000) {
    return fcmTokenCache.token;
  }
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(normalizePem(cfg.privateKey)),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const iat = Math.floor(now / 1000);
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64url(JSON.stringify({
    iss: cfg.clientEmail,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat,
    exp: iat + 3600,
  }));
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, encoder.encode(`${header}.${claims}`));
  const assertion = `${header}.${claims}.${b64url(new Uint8Array(sig))}`;
  const res = await f("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
  });
  if (!res.ok) throw new Error(`fcm_oauth_${res.status}`);
  const j = await res.json();
  fcmTokenCache = { token: j.access_token, exp: now + (j.expires_in ?? 3600) * 1000, email: cfg.clientEmail };
  return j.access_token;
}

export function resetFcmTokenCache() {
  fcmTokenCache = null;
}

export async function sendFcm(cfg: FcmConfig, row: PushRow, t: Token, f: Fetch, now = Date.now()): Promise<Outcome> {
  let access: string;
  try {
    access = await fcmAccessToken(cfg, f, now);
  } catch {
    return "retry";
  }
  const res = await f(`https://fcm.googleapis.com/v1/projects/${cfg.projectId}/messages:send`, {
    method: "POST",
    headers: { authorization: `Bearer ${access}`, "content-type": "application/json" },
    body: JSON.stringify(fcmMessage(row, t.token, now)),
  });
  if (res.ok) return "ok";
  let code = "";
  try {
    const j = await res.json();
    code = j?.error?.details?.find?.((d: { errorCode?: string }) => d.errorCode)?.errorCode ?? j?.error?.status ?? "";
  } catch { /* no body */ }
  if (res.status === 404 || code === "UNREGISTERED" || code === "INVALID_ARGUMENT") return "invalid";
  if (res.status === 401) resetFcmTokenCache();
  return "retry";
}

// ---------------------------------------------------------------------------
// WNS
// ---------------------------------------------------------------------------
export type WnsConfig = { packageSid: string; clientSecret: string };

export function wnsConfigFromEnv(env: (k: string) => string | undefined): WnsConfig | null {
  const packageSid = env("WNS_PACKAGE_SID");
  const clientSecret = env("WNS_CLIENT_SECRET");
  return packageSid && clientSecret ? { packageSid, clientSecret } : null;
}

/** Channel URIs come from clients, so only Microsoft's own push hosts are called. */
export function isWnsChannel(uri: string): boolean {
  try {
    const u = new URL(uri);
    return u.protocol === "https:" && (u.hostname === "notify.windows.com" || u.hostname.endsWith(".notify.windows.com"));
  } catch {
    return false;
  }
}

export function xmlEscape(s: string): string {
  return s.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;").replaceAll("'", "&apos;");
}

export function wnsToast(row: PushRow): string {
  const route = typeof row.data.route === "string" ? row.data.route : "lobby";
  const night = typeof row.data.night === "string" ? `&night=${encodeURIComponent(row.data.night)}` : "";
  const launch = xmlEscape(`synctogether://push?route=${encodeURIComponent(route)}${night}`);
  const scenario = isUrgent(row) ? ' scenario="incomingCall"' : "";
  return `<toast launch="${launch}" activationType="protocol"${scenario}><visual><binding template="ToastGeneric">` +
    `<text>${xmlEscape(row.title)}</text><text>${xmlEscape(row.body)}</text></binding></visual></toast>`;
}

let wnsTokenCache: { token: string; exp: number; sid: string } | null = null;

async function wnsAccessToken(cfg: WnsConfig, f: Fetch, now = Date.now()): Promise<string> {
  if (wnsTokenCache && wnsTokenCache.sid === cfg.packageSid && wnsTokenCache.exp > now + 60_000) {
    return wnsTokenCache.token;
  }
  const res = await f("https://login.live.com/accesstoken.srf", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "client_credentials",
      client_id: cfg.packageSid,
      client_secret: cfg.clientSecret,
      scope: "notify.windows.com",
    }),
  });
  if (!res.ok) throw new Error(`wns_oauth_${res.status}`);
  const j = await res.json();
  wnsTokenCache = { token: j.access_token, exp: now + (j.expires_in ?? 86400) * 1000, sid: cfg.packageSid };
  return j.access_token;
}

export function resetWnsTokenCache() {
  wnsTokenCache = null;
}

export async function sendWns(cfg: WnsConfig, row: PushRow, t: Token, f: Fetch, now = Date.now()): Promise<Outcome> {
  if (!isWnsChannel(t.token)) return "invalid";
  let access: string;
  try {
    access = await wnsAccessToken(cfg, f, now);
  } catch {
    return "retry";
  }
  const res = await f(t.token, {
    method: "POST",
    headers: {
      authorization: `Bearer ${access}`,
      "content-type": "text/xml",
      "x-wns-type": "wns/toast",
      "x-wns-ttl": String(secondsUntil(row.expires_at, 86400, now)),
      "x-wns-tag": row.kind.slice(0, 16),
    },
    body: wnsToast(row),
  });
  if (res.status === 200) return "ok";
  if (res.status === 404 || res.status === 410) return "invalid";
  if (res.status === 401) resetWnsTokenCache();
  return "retry";
}

// ---------------------------------------------------------------------------
// One row, every device
// ---------------------------------------------------------------------------
export type Providers = { apns: ApnsConfig | null; fcm: FcmConfig | null; wns: WnsConfig | null };

export function providersFromEnv(env: (k: string) => string | undefined): Providers {
  return { apns: apnsConfigFromEnv(env), fcm: fcmConfigFromEnv(env), wns: wnsConfigFromEnv(env) };
}

export async function sendToToken(p: Providers, row: PushRow, t: Token, f: Fetch, now = Date.now()): Promise<Outcome> {
  try {
    switch (t.platform) {
      case "ios":
      case "macos":
        return p.apns ? await sendApns(p.apns, row, t, f, now) : "skipped";
      case "android":
        return p.fcm ? await sendFcm(p.fcm, row, t, f, now) : "skipped";
      case "windows":
        return p.wns ? await sendWns(p.wns, row, t, f, now) : "skipped";
    }
  } catch {
    return "retry";
  }
}

/**
 * done: stop trying this row (delivered somewhere, or nothing left to try).
 * dead: tokens to delete. A row retries only when something might still work.
 */
export function settle(outcomes: { token: Token; outcome: Outcome }[]): { done: boolean; dead: Token[] } {
  const dead = outcomes.filter((o) => o.outcome === "invalid").map((o) => o.token);
  const anyOk = outcomes.some((o) => o.outcome === "ok");
  const anyRetry = outcomes.some((o) => o.outcome === "retry");
  return { done: anyOk || !anyRetry, dead };
}
