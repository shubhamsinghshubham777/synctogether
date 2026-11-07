import test from "node:test";
import assert from "node:assert/strict";
import { requiredEnv, SITE_CONFIG, SITE_HOST } from "../lib/constants.ts";

test("a production build refuses to start without an operator value", () => {
  assert.throws(
    () => requiredEnv(undefined, "NEXT_PUBLIC_SITE_URL", "http://localhost:3000", "production"),
    /NEXT_PUBLIC_SITE_URL must be set/,
  );
  assert.throws(() => requiredEnv("   ", "NEXT_PUBLIC_SUPPORT_EMAIL", "x", "production"), /must be set/);
});

test("development and tests get a harmless local value, never an official one", () => {
  assert.equal(requiredEnv(undefined, "N", "http://localhost:3000", "development"), "http://localhost:3000");
  assert.equal(requiredEnv(undefined, "N", "support@localhost", undefined), "support@localhost");
  assert.equal(requiredEnv(" https://watch.example.com ", "N", "x", "production"), "https://watch.example.com");
});

test("the site config carries no official hostname when nothing is configured", () => {
  // The suite runs with no NEXT_PUBLIC_* set.
  assert.equal(SITE_CONFIG.url, "http://localhost:3000");
  assert.equal(SITE_HOST, "localhost:3000");
  assert.doesNotMatch(JSON.stringify(SITE_CONFIG), /synctogether\.app/);
});
