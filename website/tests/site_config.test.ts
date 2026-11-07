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

test("the operator's identity comes from configuration, never from the project's author", async () => {
  const { OPERATOR, DMCA_AGENT } = await import("../lib/constants.ts");
  const json = JSON.stringify({ OPERATOR, DMCA_AGENT, SITE_CONFIG: { ...SITE_CONFIG, githubRepo: undefined } }) // githubRepo is the upstream source link the license asks to keep;
  assert.doesNotMatch(json, /Shubham|Bahadurgarh|DMCA-1080733|synctogether\.app|linkedin\.com/i);
  assert.equal(OPERATOR.dmcaRegistration, ""); // no registration is claimed unless one is configured
  assert.equal(SITE_CONFIG.appStoreUrl, `${SITE_CONFIG.url}/download`); // never someone else's store listing
});
