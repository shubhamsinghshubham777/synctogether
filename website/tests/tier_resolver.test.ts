import test from "node:test";
import assert from "node:assert/strict";
import { cheapestTierFor } from "../lib/tier-resolver.ts";

test("boundary: 4 people fits guest, 5 needs free", () => {
  assert.equal(cheapestTierFor(4, 60), "guest");
  assert.equal(cheapestTierFor(5, 60), "free");
});

test("boundary: 60 minutes fits guest, 61 needs free", () => {
  assert.equal(cheapestTierFor(4, 60), "guest");
  assert.equal(cheapestTierFor(4, 61), "free");
});

test("boundary: 16 people fits premium, 17 fits nothing", () => {
  assert.equal(cheapestTierFor(16, 60), "premium");
  assert.equal(cheapestTierFor(17, 60), null);
});

test("boundary: 240 minutes fits free, 241 needs premium", () => {
  assert.equal(cheapestTierFor(8, 240), "free");
  assert.equal(cheapestTierFor(8, 241), "premium");
});

test("boundary: 1440 minutes (24h) fits premium, beyond fits nothing", () => {
  assert.equal(cheapestTierFor(16, 1440), "premium");
  assert.equal(cheapestTierFor(16, 1441), null);
});

test("always returns the cheapest sufficient tier, never a pricier one", () => {
  assert.equal(cheapestTierFor(2, 30), "guest");
  assert.equal(cheapestTierFor(9, 30), "premium"); // free caps at 8 members
});
