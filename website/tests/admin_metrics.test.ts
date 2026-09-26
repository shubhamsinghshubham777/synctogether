import test from "node:test";
import assert from "node:assert/strict";
import { validateProductionCredentials, isLoopbackHost } from "../lib/supabase/admin.ts";
import { isAuthorizedLocalAccess } from "../lib/admin-guard.ts";
import {
  computeMrr,
  formatBytes,
  monthsPerCycle,
  percent,
  summariseReleaseFetches,
} from "../lib/metrics_logic.ts";

const req = (h: Record<string, string>) => ({ headers: new Headers(h) });

test("the guard admits loopback hosts in development and test", () => {
  for (const host of ["localhost:3000", "127.0.0.1:3000", "0.0.0.0", "app.local", "test.localhost"]) {
    assert.equal(isAuthorizedLocalAccess(req({ host }), "development"), true, host);
    assert.equal(isAuthorizedLocalAccess(req({ host }), "test"), true, host);
  }
});

test("the guard refuses non-loopback hosts in development", () => {
  assert.equal(isAuthorizedLocalAccess(req({ host: "synctogether.app" }), "development"), false);
  assert.equal(isAuthorizedLocalAccess(req({}), "development"), false);
});

test("the guard refuses every production request, token or spoofed host alike", () => {
  const secret = "super-secret-admin-token-123";
  process.env.INTERNAL_ADMIN_TOKEN = secret;
  try {
    const cases: Record<string, string>[] = [
      { host: "localhost" },
      { host: "127.0.0.1", "x-forwarded-for": "127.0.0.1" },
      { host: "synctogether.app", "x-admin-token": secret },
    ];
    for (const h of cases) {
      assert.equal(isAuthorizedLocalAccess(req(h), "production"), false, JSON.stringify(h));
    }
  } finally {
    delete process.env.INTERNAL_ADMIN_TOKEN;
  }
});

test("percent is null rather than 0 when the denominator is missing", () => {
  assert.equal(percent(3, 0), null);
  assert.equal(percent(null, 10), null);
  assert.equal(percent(1, 3), 33.3);
});

test("monthsPerCycle normalises annual to twelve months", () => {
  assert.equal(monthsPerCycle("month", 1), 1);
  assert.equal(monthsPerCycle("year", 1), 12);
  assert.equal(monthsPerCycle("month", 3), 3);
  assert.equal(monthsPerCycle("fortnight", 1), null);
});

test("MRR sums real prices, annual / 12, INR at the fixed rate", () => {
  const mrr = computeMrr(
    [
      { currency: "USD", interval: "month", frequency: 1, subscribers: 2, unit_amount_sum: 798 },
      { currency: "USD", interval: "year", frequency: 1, subscribers: 1, unit_amount_sum: 2999 },
      { currency: "INR", interval: "month", frequency: 1, subscribers: 1, unit_amount_sum: 19900 },
    ],
    100
  );
  // 7.98 + 29.99/12 (2.4991...) + 199/100
  assert.equal(mrr.usdEquivalent, 12.47);
  assert.equal(mrr.unconvertedSubscribers, 0);
  assert.deepEqual(mrr.byCurrency.find((c) => c.currency === "INR"), { currency: "INR", monthly: 199, subscribers: 1 });
});

test("MRR never converts a currency it has no rate for, and is null with no rows", () => {
  const mrr = computeMrr([{ currency: "EUR", interval: "month", frequency: 1, subscribers: 4, unit_amount_sum: 1596 }]);
  assert.equal(mrr.usdEquivalent, null);
  assert.equal(mrr.unconvertedSubscribers, 4);
  assert.equal(computeMrr([]).usdEquivalent, null);
});

test("GitHub fetches are summed per OS from asset names", () => {
  const s = summariseReleaseFetches([
    {
      tag_name: "v1.0.0",
      published_at: "2026-09-01T00:00:00Z",
      assets: [
        { name: "SyncTogether-1.0.0-macOS.dmg", download_count: 10 },
        { name: "SyncTogether-1.0.0-Windows.exe", download_count: 7 },
        { name: "appcast.xml", download_count: 100 },
      ],
    },
  ]);
  assert.deepEqual([s.mac, s.win, s.total], [10, 7, 117]);
});

test("formatBytes", () => {
  assert.equal(formatBytes(0), "0 B");
  assert.equal(formatBytes(1024), "1 KB");
  assert.equal(formatBytes(10737418240), "10 GB");
});

test("isLoopbackHost identifies loopback and not production hosts", () => {
  for (const h of ["localhost", "127.0.0.1", "0.0.0.0", "::1", "app.localhost", "service.local"]) {
    assert.equal(isLoopbackHost(h), true, h);
  }
  for (const h of ["abcdefghij.supabase.co", "synctogether.app"]) assert.equal(isLoopbackHost(h), false, h);
});

test("validateProductionCredentials denies loopback, demo keys, missing and invalid input", () => {
  const cases: [string, string, string][] = [
    ["http://127.0.0.1:54321", "valid_secret_key_12345", "LOOPBACK_DETECTED"],
    [
      "https://projectref.supabase.co",
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU",
      "DEMO_KEY_DETECTED",
    ],
    ["", "", "MISSING_CREDENTIALS"],
    ["not-a-valid-url", "some_key", "INVALID_URL"],
  ];
  for (const [url, key, code] of cases) {
    const r = validateProductionCredentials(url, key);
    assert.equal(r.valid, false);
    if (!r.valid) assert.equal(r.code, code);
  }
  const ok = validateProductionCredentials("https://myprodproject.supabase.co", "sb_secret_genuine_production_key_12345");
  assert.equal(ok.valid, true);
  if (ok.valid) assert.equal(ok.host, "myprodproject.supabase.co");
});
