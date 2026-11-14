import test from "node:test";
import assert from "node:assert/strict";
import {
  ANDROID_SOURCES,
  DEFAULT_SEAT_TARGET,
  counterVisible,
  normalizeEmail,
  parseSource,
  seatLabel,
  seatTarget,
  seatsLeft,
} from "../lib/android-testers.ts";

test("an address is trimmed and lower-cased, so one address is one seat", () => {
  assert.equal(normalizeEmail("  Sam@Gmail.COM "), "sam@gmail.com");
  assert.equal(normalizeEmail("sam+tv@gmail.com"), "sam+tv@gmail.com");
});

test("a half-typed address is refused", () => {
  assert.equal(normalizeEmail("sam@gmial"), null);
  assert.equal(normalizeEmail("sam"), null);
  assert.equal(normalizeEmail("sam @gmail.com"), null);
  assert.equal(normalizeEmail("@gmail.com"), null);
  assert.equal(normalizeEmail(""), null);
  assert.equal(normalizeEmail(undefined), null);
  assert.equal(normalizeEmail({ email: "a@b.co" }), null);
  assert.equal(normalizeEmail(`${"a".repeat(250)}@b.co`), null);
});

test("only listed sources are kept, anything else files under android", () => {
  for (const s of ANDROID_SOURCES) assert.equal(parseSource(s), s);
  assert.equal(parseSource("twitter"), "android");
  assert.equal(parseSource("join "), "android");
  assert.equal(parseSource(undefined), "android");
  assert.equal(parseSource(7), "android");
});

test("the seat target defaults to 25 and is clamped", () => {
  assert.equal(seatTarget(undefined), DEFAULT_SEAT_TARGET);
  assert.equal(seatTarget(""), DEFAULT_SEAT_TARGET);
  assert.equal(seatTarget("abc"), DEFAULT_SEAT_TARGET);
  assert.equal(seatTarget("40"), 40);
  assert.equal(seatTarget("1"), 5);
  assert.equal(seatTarget("99999"), 500);
});

test("the strip only shows once there is something to see", () => {
  assert.equal(counterVisible(0), false);
  assert.equal(counterVisible(4), false);
  assert.equal(counterVisible(5), true);
  assert.equal(counterVisible(25), true);
});

test("seats left never goes negative and the stub pads to two digits", () => {
  assert.equal(seatsLeft(14, 25), 11);
  assert.equal(seatsLeft(30, 25), 0);
  assert.equal(seatLabel(6), "06");
  assert.equal(seatLabel(15), "15");
  assert.equal(seatLabel(112), "112");
});
