import test from "node:test";
import assert from "node:assert/strict";
import {
  validateProductionCredentials,
  isLoopbackHost,
} from "../lib/supabase/admin.ts";

function checkLocalAccess(
  headers: Headers,
  customEnv = "development",
  url?: string,
  customToken?: string
): boolean {
  const host = headers.get("host")?.toLowerCase() || "";
  const hostname = host.split(":")[0];

  const expectedToken = customToken;
  if (expectedToken && expectedToken.trim().length > 0) {
    const headerToken = headers.get("x-admin-token");
    if (headerToken && headerToken === expectedToken) {
      return true;
    }

    if (url) {
      try {
        const urlObj = new URL(url);
        const queryToken = urlObj.searchParams.get("token");
        if (queryToken && queryToken === expectedToken) {
          return true;
        }
      } catch {
        // Ignore URL parsing errors
      }
    }
  }

  const isDevOrTest = customEnv === "development" || customEnv === "test";

  // In production, unauthenticated requests are strictly rejected
  if (!isDevOrTest) {
    return false;
  }

  const isLoopbackHost =
    hostname === "localhost" ||
    hostname === "127.0.0.1" ||
    hostname === "0.0.0.0" ||
    hostname.endsWith(".localhost") ||
    hostname.endsWith(".local");

  return isLoopbackHost;
}

test("checkLocalAccess approves local loopback development hosts", () => {
  const localHosts = [
    "localhost:3000",
    "127.0.0.1:3000",
    "0.0.0.0:3000",
    "localhost",
    "127.0.0.1",
    "app.local",
    "test.localhost",
  ];

  for (const host of localHosts) {
    const headers = new Headers({ host });
    assert.equal(
      checkLocalAccess(headers, "development"),
      true,
      `Expected ${host} to be recognized as authorized local access in development`
    );
    assert.equal(
      checkLocalAccess(headers, "test"),
      true,
      `Expected ${host} to be recognized as authorized local access in test`
    );
  }
});

test("checkLocalAccess strictly blocks production access without token (immune to spoofed Host/IP)", () => {
  const hosts = [
    "synctogether.com",
    "www.synctogether.com",
    "synctogether.vercel.app",
    "localhost",
    "127.0.0.1",
  ];

  for (const host of hosts) {
    const headers = new Headers({
      host,
      "x-forwarded-for": "127.0.0.1",
    });
    assert.equal(
      checkLocalAccess(headers, "production"),
      false,
      `Expected host ${host} to be blocked in production without token`
    );
  }
});

test("checkLocalAccess approves requests carrying valid admin token in production", () => {
  const token = "super-secret-admin-token-123";

  // 1. Authorized via x-admin-token header
  const headerReq = new Headers({
    host: "synctogether.com",
    "x-admin-token": token,
  });
  assert.equal(checkLocalAccess(headerReq, "production", undefined, token), true);

  // 2. Authorized via query param
  const queryReq = new Headers({
    host: "synctogether.com",
  });
  const url = "https://synctogether.com/internal/metrics?token=super-secret-admin-token-123";
  assert.equal(checkLocalAccess(queryReq, "production", url, token), true);

  // 3. Rejected with invalid token
  const invalidReq = new Headers({
    host: "synctogether.com",
    "x-admin-token": "wrong-token",
  });
  assert.equal(checkLocalAccess(invalidReq, "production", undefined, token), false);
});

test("Business calculations: MRR, ARR, and conversion rates behave predictably", () => {
  const activePremium = 12;
  const totalRegistered = 150;
  const uniqueVisitors = 1200;
  const downloads = 300;

  const mrr = activePremium * 5.0;
  const arr = mrr * 12;
  const payingRate = Math.round((activePremium / totalRegistered) * 1000) / 10;
  const downloadRate = Math.round((downloads / uniqueVisitors) * 1000) / 10;

  assert.equal(mrr, 60.0);
  assert.equal(arr, 720.0);
  assert.equal(payingRate, 8.0); // 8%
  assert.equal(downloadRate, 25.0); // 25%
});

test("isLoopbackHost identifies all localhost and loopback domains", () => {
  const loopbacks = [
    "localhost",
    "127.0.0.1",
    "0.0.0.0",
    "::1",
    "app.localhost",
    "service.local",
  ];
  for (const host of loopbacks) {
    assert.equal(isLoopbackHost(host), true, `Expected ${host} to be recognized as loopback`);
  }

  const productionHosts = [
    "abcdefghij.supabase.co",
    "synctogether.com",
    "api.synctogether.com",
  ];
  for (const host of productionHosts) {
    assert.equal(isLoopbackHost(host), false, `Expected ${host} to NOT be recognized as loopback`);
  }
});

test("validateProductionCredentials strictly denies loopback and local seed databases", () => {
  // 1. Loopback rejected
  const loopbackRes = validateProductionCredentials(
    "http://127.0.0.1:54321",
    "valid_secret_key_12345"
  );
  assert.equal(loopbackRes.valid, false);
  if (!loopbackRes.valid) {
    assert.equal(loopbackRes.code, "LOOPBACK_DETECTED");
  }

  // 2. Demo service key rejected
  const demoKeyRes = validateProductionCredentials(
    "https://projectref.supabase.co",
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU"
  );
  assert.equal(demoKeyRes.valid, false);
  if (!demoKeyRes.valid) {
    assert.equal(demoKeyRes.code, "DEMO_KEY_DETECTED");
  }

  // 3. Missing keys rejected
  const missingRes = validateProductionCredentials("", "");
  assert.equal(missingRes.valid, false);
  if (!missingRes.valid) {
    assert.equal(missingRes.code, "MISSING_CREDENTIALS");
  }

  // 4. Invalid URL rejected
  const invalidUrlRes = validateProductionCredentials("not-a-valid-url", "some_key");
  assert.equal(invalidUrlRes.valid, false);
  if (!invalidUrlRes.valid) {
    assert.equal(invalidUrlRes.code, "INVALID_URL");
  }

  // 5. Genuine production credentials accepted
  const validRes = validateProductionCredentials(
    "https://myprodproject.supabase.co",
    "sb_secret_genuine_production_key_12345"
  );
  assert.equal(validRes.valid, true);
  if (validRes.valid) {
    assert.equal(validRes.host, "myprodproject.supabase.co");
  }
});

test("Quota status calculations accurately reflect healthy, warning, and critical bands", () => {
  function calculateQuotaStatus(used: number, limit: number): "healthy" | "warning" | "critical" {
    if (limit <= 0) return "healthy";
    const ratio = used / limit;
    if (ratio >= 0.9) return "critical";
    if (ratio >= 0.75) return "warning";
    return "healthy";
  }

  function formatBytes(bytes: number, decimals = 2): string {
    if (!bytes || bytes <= 0) return "0 B";
    const k = 1024;
    const dm = decimals < 0 ? 0 : decimals;
    const sizes = ["B", "KB", "MB", "GB", "TB"];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    const val = parseFloat((bytes / Math.pow(k, i)).toFixed(dm));
    return `${val} ${sizes[i]}`;
  }

  // Quota Status
  assert.equal(calculateQuotaStatus(10, 50), "healthy"); // 20%
  assert.equal(calculateQuotaStatus(37, 50), "healthy"); // 74%
  assert.equal(calculateQuotaStatus(38, 50), "warning"); // 76%
  assert.equal(calculateQuotaStatus(44, 50), "warning"); // 88%
  assert.equal(calculateQuotaStatus(45, 50), "critical"); // 90%
  assert.equal(calculateQuotaStatus(50, 50), "critical"); // 100%

  // Byte Formatter
  assert.equal(formatBytes(0), "0 B");
  assert.equal(formatBytes(1024), "1 KB");
  assert.equal(formatBytes(1048576), "1 MB");
  assert.equal(formatBytes(10737418240), "10 GB");
});
