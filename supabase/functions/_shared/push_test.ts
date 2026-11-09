import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import {
  apnsConfigFromEnv,
  apnsHeaders,
  apnsJwt,
  apnsPayload,
  fcmMessage,
  isWnsChannel,
  type PushRow,
  resetApnsJwtCache,
  resetFcmTokenCache,
  resetWnsTokenCache,
  sendToToken,
  settle,
  type Token,
  wnsToast,
  xmlEscape,
} from "./push.ts";

const NOW = Date.parse("2026-11-07T12:00:00Z");

const row = (over: Partial<PushRow> = {}): PushRow => ({
  id: 1,
  user_id: "u",
  kind: "call",
  title: "Sam is calling",
  body: "Our Room is open. Tap to join.",
  data: { route: "our-room" },
  expires_at: new Date(NOW + 90_000).toISOString(),
  tokens: [],
  ...over,
});

function pem(label: string, der: ArrayBuffer): string {
  const b64 = btoa(String.fromCharCode(...new Uint8Array(der)));
  return `-----BEGIN ${label}-----\n${b64.match(/.{1,64}/g)!.join("\n")}\n-----END ${label}-----`;
}

async function ecKeyPem(): Promise<string> {
  const k = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign"]);
  return pem("PRIVATE KEY", await crypto.subtle.exportKey("pkcs8", k.privateKey));
}

async function rsaKeyPem(): Promise<string> {
  const k = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign"],
  );
  return pem("PRIVATE KEY", await crypto.subtle.exportKey("pkcs8", k.privateKey));
}

Deno.test("APNs: a call is time-sensitive and high priority; the rest are not", () => {
  const call = apnsPayload(row());
  assertEquals((call.aps as Record<string, unknown>)["interruption-level"], "time-sensitive");
  assertEquals(call.route, "our-room");
  const wl = apnsPayload(row({ kind: "reunion" }));
  assertEquals((wl.aps as Record<string, unknown>)["interruption-level"], "active");
  assertEquals(apnsHeaders(row(), "app.x", "J", NOW)["apns-priority"], "10");
  assertEquals(apnsHeaders(row({ kind: "reunion" }), "app.x", "J", NOW)["apns-priority"], "5");
});

Deno.test("APNs: expiry is an absolute epoch, so a stale call is never delivered late", () => {
  const h = apnsHeaders(row(), "app.x", "J", NOW);
  assertEquals(h["apns-expiration"], String(Math.floor(NOW / 1000) + 90));
  assertEquals(h["apns-push-type"], "alert");
});

Deno.test("APNs: the provider token is a real ES256 JWT and is reused", async () => {
  resetApnsJwtCache();
  const cfg = { keyId: "KEY123", teamId: "TEAM45", privateKey: await ecKeyPem(), topics: { ios: "app.x" } };
  const a = await apnsJwt(cfg, NOW);
  const [h, c, s] = a.split(".");
  assertEquals(JSON.parse(atob(h.replaceAll("-", "+").replaceAll("_", "/"))), { alg: "ES256", kid: "KEY123" });
  assertEquals(JSON.parse(atob(c.replaceAll("-", "+").replaceAll("_", "/"))).iss, "TEAM45");
  assertEquals(atob(s.replaceAll("-", "+").replaceAll("_", "/")).length, 64, "raw r||s, 64 bytes");
  assertEquals(await apnsJwt(cfg, NOW + 10 * 60_000), a, "reused inside the hour");
  assert((await apnsJwt(cfg, NOW + 51 * 60_000)) !== a, "reissued before Apple's hour is up");
});

Deno.test("APNs: sandbox tokens go to the sandbox gateway, and outcomes are classified", async () => {
  resetApnsJwtCache();
  const cfg = { keyId: "K", teamId: "T", privateKey: await ecKeyPem(), topics: { ios: "app.x", macos: "app.x.mac" } };
  const seen: string[] = [];
  const answer = (status: number, reason?: string) => (url: string | URL | Request, init?: RequestInit) => {
    seen.push(String(url) + "|" + (init?.headers as Record<string, string>)["apns-topic"]);
    return Promise.resolve(new Response(reason ? JSON.stringify({ reason }) : "{}", { status }));
  };
  const tok = (platform: "ios" | "macos", environment: "production" | "sandbox"): Token => ({ platform, token: "abc", environment });
  const p = { apns: cfg, fcm: null, wns: null };

  assertEquals(await sendToToken(p, row(), tok("ios", "sandbox"), answer(200), NOW), "ok");
  assertEquals(seen[0], "https://api.sandbox.push.apple.com/3/device/abc|app.x");
  assertEquals(await sendToToken(p, row(), tok("macos", "production"), answer(200), NOW), "ok");
  assertEquals(seen[1], "https://api.push.apple.com/3/device/abc|app.x.mac");
  assertEquals(await sendToToken(p, row(), tok("ios", "production"), answer(410, "Unregistered"), NOW), "invalid");
  assertEquals(await sendToToken(p, row(), tok("ios", "production"), answer(400, "BadDeviceToken"), NOW), "invalid");
  assertEquals(await sendToToken(p, row(), tok("ios", "production"), answer(503), NOW), "retry");
  assertEquals(await sendToToken(p, row(), tok("ios", "production"), answer(429, "TooManyRequests"), NOW), "retry");
});

Deno.test("an unconfigured platform is skipped, never failed", async () => {
  const none = { apns: null, fcm: null, wns: null };
  const fetchNever = () => Promise.reject(new Error("must not be called"));
  for (const platform of ["ios", "macos", "android", "windows"] as const) {
    assertEquals(await sendToToken(none, row(), { platform, token: "t", environment: "production" }, fetchNever, NOW), "skipped");
  }
});

Deno.test("env parsing: each provider is optional", () => {
  assertEquals(apnsConfigFromEnv(() => undefined), null);
  const env: Record<string, string> = { APNS_KEY_ID: "k", APNS_TEAM_ID: "t", APNS_PRIVATE_KEY: "p", APNS_BUNDLE_ID: "app.x", APNS_TOPIC_MACOS: "app.x.mac" };
  const cfg = apnsConfigFromEnv((k) => env[k])!;
  assertEquals(cfg.topics, { ios: "app.x", macos: "app.x.mac" });
});

Deno.test("FCM: calls use the high-priority channel, with a short ttl", () => {
  const m = fcmMessage(row({ data: { route: "our-room", urgent: true } }), "tok", NOW).message as Record<string, any>;
  assertEquals(m.token, "tok");
  assertEquals(m.android.priority, "HIGH");
  assertEquals(m.android.ttl, "90s");
  assertEquals(m.android.notification.channel_id, "calls");
  assertEquals(m.data, { kind: "call", route: "our-room", urgent: "true" }, "data values are strings");
  const wl = fcmMessage(row({ kind: "reunion" }), "tok", NOW).message as Record<string, any>;
  assertEquals(wl.android.notification.channel_id, "default");
  assertEquals(wl.android.priority, "NORMAL");
});

Deno.test("FCM: exchanges a service-account JWT, then sends; UNREGISTERED drops the token", async () => {
  resetFcmTokenCache();
  const cfg = { projectId: "proj", clientEmail: "sa@proj.iam", privateKey: await rsaKeyPem() };
  const calls: string[] = [];
  const f = (url: string | URL | Request, init?: RequestInit) => {
    calls.push(String(url));
    if (String(url).includes("oauth2")) {
      const body = String(init?.body);
      assertStringIncludes(body, "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer");
      return Promise.resolve(new Response(JSON.stringify({ access_token: "A", expires_in: 3600 })));
    }
    return Promise.resolve(new Response(JSON.stringify({ error: { status: "NOT_FOUND", details: [{ errorCode: "UNREGISTERED" }] } }), { status: 404 }));
  };
  const p = { apns: null, fcm: cfg, wns: null };
  assertEquals(await sendToToken(p, row(), { platform: "android", token: "t", environment: "production" }, f, NOW), "invalid");
  assertEquals(calls.length, 2);
  await sendToToken(p, row(), { platform: "android", token: "t", environment: "production" }, f, NOW);
  assertEquals(calls.filter((c) => c.includes("oauth2")).length, 1, "the access token is cached");
});

Deno.test("WNS: only Microsoft's own hosts are ever called (clients supply the channel URI)", async () => {
  assert(isWnsChannel("https://db5.notify.windows.com/?token=abc"));
  assert(isWnsChannel("https://notify.windows.com/x"));
  assert(!isWnsChannel("http://db5.notify.windows.com/x"), "https only");
  assert(!isWnsChannel("https://evil.example/notify.windows.com"));
  assert(!isWnsChannel("https://notify.windows.com.evil.example/x"));
  assert(!isWnsChannel("not a url"));

  resetWnsTokenCache();
  const p = { apns: null, fcm: null, wns: { packageSid: "ms-app://s-1", clientSecret: "secret" } };
  const never = () => Promise.reject(new Error("must not be called"));
  assertEquals(await sendToToken(p, row(), { platform: "windows", token: "https://evil.example/x", environment: "production" }, never, NOW), "invalid");
});

Deno.test("WNS: toast carries a deep link, escapes text, and a call uses the call scenario", () => {
  const xml = wnsToast(row({ title: 'Sam & "Lee" <3', data: { route: "date-night", night: "n 1" } }));
  assertStringIncludes(xml, "Sam &amp; &quot;Lee&quot; &lt;3");
  assertStringIncludes(xml, 'launch="synctogether://push?route=date-night&amp;night=n%201"');
  assertStringIncludes(xml, 'scenario="incomingCall"');
  assert(!wnsToast(row({ kind: "reunion" })).includes("incomingCall"));
  assertEquals(xmlEscape("a<b&c"), "a&lt;b&amp;c");
});

Deno.test("WNS: 410 drops the channel, 401 refreshes the token and retries", async () => {
  resetWnsTokenCache();
  const p = { apns: null, fcm: null, wns: { packageSid: "ms-app://s-1", clientSecret: "secret" } };
  let status = 410;
  const f = (url: string | URL | Request) =>
    Promise.resolve(String(url).includes("login.live.com")
      ? new Response(JSON.stringify({ access_token: "W", expires_in: 86400 }))
      : new Response("", { status }));
  const t: Token = { platform: "windows", token: "https://db5.notify.windows.com/?token=abc", environment: "production" };
  assertEquals(await sendToToken(p, row(), t, f, NOW), "invalid");
  status = 401;
  assertEquals(await sendToToken(p, row(), t, f, NOW), "retry");
  status = 200;
  assertEquals(await sendToToken(p, row(), t, f, NOW), "ok");
});

Deno.test("settle: delivered anywhere is done; retry only while something might still work", () => {
  const t = (n: string): Token => ({ platform: "ios", token: n, environment: "production" });
  assertEquals(settle([{ token: t("a"), outcome: "ok" }, { token: t("b"), outcome: "retry" }]).done, true);
  assertEquals(settle([{ token: t("a"), outcome: "retry" }]).done, false);
  assertEquals(settle([{ token: t("a"), outcome: "invalid" }]).done, true, "nothing left to try");
  assertEquals(settle([{ token: t("a"), outcome: "skipped" }]).done, true, "an unconfigured platform must not clog the queue");
  assertEquals(settle([]).done, true);
  assertEquals(settle([{ token: t("a"), outcome: "invalid" }, { token: t("b"), outcome: "retry" }]).dead.map((x) => x.token), ["a"]);
});
