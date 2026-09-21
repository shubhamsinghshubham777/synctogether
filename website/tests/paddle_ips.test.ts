import test from "node:test";
import assert from "node:assert/strict";
import {
  parseIpv4Cidrs,
  callerAddress,
  classifyCaller,
} from "../lib/paddle_ips.ts";

// The shape Paddle actually serves at https://api.paddle.com/ips.
const LIVE_PAYLOAD = {
  data: {
    ipv4_cidrs: [
      "34.237.3.244/32",
      "34.195.105.136/32",
      "34.232.58.13/32",
      "35.155.119.135/32",
      "34.212.5.7/32",
      "52.11.166.252/32",
    ],
  },
  meta: { request_id: "53d23cd6-4990-424d-81f7-12f3ef0657b5" },
};

test("parseIpv4Cidrs", async (t) => {
  await t.test("strips the /32 prefix Paddle publishes", () => {
    assert.deepEqual(parseIpv4Cidrs(LIVE_PAYLOAD), [
      "34.237.3.244",
      "34.195.105.136",
      "34.232.58.13",
      "35.155.119.135",
      "34.212.5.7",
      "52.11.166.252",
    ]);
  });

  await t.test("a bare address with no prefix survives unchanged", () => {
    assert.deepEqual(
      parseIpv4Cidrs({ data: { ipv4_cidrs: ["34.237.3.244"] } }),
      ["34.237.3.244"]
    );
  });

  await t.test("a malformed payload yields nothing rather than throwing", () => {
    // Each of these must be empty, because an empty list is what `loadAddresses`
    // treats as a bad response - the alternative is a partly-parsed allowlist
    // that rejects real Paddle deliveries.
    assert.deepEqual(parseIpv4Cidrs(null), []);
    assert.deepEqual(parseIpv4Cidrs({}), []);
    assert.deepEqual(parseIpv4Cidrs({ data: {} }), []);
    assert.deepEqual(parseIpv4Cidrs({ data: { ipv4_cidrs: "not-a-list" } }), []);
    assert.deepEqual(parseIpv4Cidrs({ data: { ipv4_cidrs: [42, null] } }), []);
  });
});

test("callerAddress", async (t) => {
  await t.test("takes the first hop of x-forwarded-for, not the last", () => {
    // Each proxy appends, so the original client is leftmost. Reading the last
    // entry would read our own edge and allowlist nothing.
    const headers = new Headers({
      "x-forwarded-for": "34.237.3.244, 10.0.0.1, 10.0.0.2",
    });
    assert.equal(callerAddress(headers), "34.237.3.244");
  });

  await t.test("prefers x-real-ip when present", () => {
    const headers = new Headers({
      "x-real-ip": "34.237.3.244",
      "x-forwarded-for": "1.2.3.4",
    });
    assert.equal(callerAddress(headers), "34.237.3.244");
  });

  await t.test("no proxy headers at all is null, not an empty string", () => {
    assert.equal(callerAddress(new Headers()), null);
    assert.equal(callerAddress(new Headers({ "x-forwarded-for": "" })), null);
  });
});

test("classifyCaller", async (t) => {
  const allowlist = new Set(parseIpv4Cidrs(LIVE_PAYLOAD));

  await t.test("a published Paddle address is allowed", () => {
    assert.equal(classifyCaller("34.237.3.244", allowlist), "allowed");
  });

  await t.test("anything else is rejected", () => {
    assert.equal(classifyCaller("203.0.113.9", allowlist), "rejected");
    // Adjacent to a real one, so a substring or prefix comparison would pass it.
    assert.equal(classifyCaller("34.237.3.245", allowlist), "rejected");
    assert.equal(classifyCaller("34.237.3.24", allowlist), "rejected");
  });

  await t.test("fails open rather than closed when it cannot classify", () => {
    // Both of these must be `unverifiable`, never `rejected`: the route only
    // drops the request on `rejected`, and treating "we could not fetch the
    // list" as hostile would discard every real subscription event.
    assert.equal(classifyCaller("34.237.3.244", null), "unverifiable");
    assert.equal(classifyCaller(null, allowlist), "unverifiable");
  });
});
