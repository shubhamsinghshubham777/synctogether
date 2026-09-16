import test from "node:test";
import assert from "node:assert/strict";
import {
  displayNameFor,
  formatPoints,
  formatWatchTime,
  gradientForSeed,
  normalizeRoomCode,
  SUPERLATIVE_TITLES,
} from "../lib/rewards.ts";

test("room codes are accepted only in the alphabet create_room actually uses", () => {
  assert.equal(normalizeRoomCode("X7K9P2"), "X7K9P2");
  assert.equal(normalizeRoomCode("  x7k9p2 "), "X7K9P2");
  // 0/O and 1/I are excluded server-side so a code can be read aloud.
  assert.equal(normalizeRoomCode("X7K9P0"), null);
  assert.equal(normalizeRoomCode("X7K9PO"), null);
  assert.equal(normalizeRoomCode("X7K9P1"), null);
  assert.equal(normalizeRoomCode("X7K9PI"), null);
});

test("anything that is not a six-character code is refused rather than 404'd later", () => {
  assert.equal(normalizeRoomCode("X7K9P"), null);
  assert.equal(normalizeRoomCode("X7K9P22"), null);
  assert.equal(normalizeRoomCode(""), null);
  assert.equal(normalizeRoomCode("../../etc"), null);
  assert.equal(normalizeRoomCode("<script>"), null);
});

test("watch time never renders a zero, which reads as broken", () => {
  assert.equal(formatWatchTime(20), "under a minute");
  assert.equal(formatWatchTime(0), "under a minute");
  assert.equal(formatWatchTime(60 * 38), "38m");
  assert.equal(formatWatchTime(3600 * 2), "2h");
  assert.equal(formatWatchTime(3600 * 4 + 60 * 12), "4h 12m");
});

test("points shorten without pretending to precision", () => {
  assert.equal(formatPoints(940), "940");
  assert.equal(formatPoints(1500), "1.5k");
  assert.equal(formatPoints(42000), "42k");
  assert.equal(formatPoints(2400000), "2.4M");
});

test("the same seed always picks the same gradient, so a page does not shuffle on reload", () => {
  const first = gradientForSeed("a1b2c3d4");
  const second = gradientForSeed("a1b2c3d4");
  assert.deepEqual(first, second);
  assert.equal(first.length, 2);
});

test("different seeds spread across the palette", () => {
  const seen = new Set<string>();
  for (let i = 0; i < 64; i++) seen.add(gradientForSeed(`seed-${i}`).join(""));
  assert.ok(seen.size > 1, "all seeds collapsed onto one gradient");
});

test("someone who never opted in is never named on a public page", () => {
  assert.equal(
    displayNameFor({ seed: "abc", name: "Ana", public: true }),
    "Ana",
  );
  // The RPC omits the name entirely for a non-consenting account; this is the
  // second guard, for a payload shape that ever changes underneath us.
  assert.equal(displayNameFor({ seed: "abc", name: "Ana", public: false }), "A friend");
  assert.equal(displayNameFor({ seed: "abc", public: false }), "A friend");
  assert.equal(displayNameFor(null), "Someone");
  assert.equal(displayNameFor(undefined), "Someone");
});

test("every superlative the client can send has a title on the page", () => {
  // Mirrors the allow-list in public.create_recap. A key that reaches the page
  // without a title here renders as a raw wire string.
  const serverAllowList = [
    "reactions",
    "chat",
    "steady",
    "pauser",
    "night_owl",
    "ride_or_die",
    "host",
    "first_in",
    "camera",
  ];
  for (const key of serverAllowList) {
    assert.ok(SUPERLATIVE_TITLES[key], `missing title for superlative "${key}"`);
  }
});

test("season ids render as months, and a malformed one falls back rather than throwing", async () => {
  const { seasonMonthLabel, seasonRankLabel } = await import("../lib/rewards.ts");
  assert.equal(seasonMonthLabel("2026-05"), "May 2026");
  assert.equal(seasonMonthLabel("2026-12"), "December 2026");
  assert.equal(seasonMonthLabel("2026-13"), "2026-13");
  assert.equal(seasonMonthLabel("nonsense"), "nonsense");
  assert.equal(seasonMonthLabel(""), "");

  assert.equal(seasonRankLabel(1), "Season winner");
  assert.equal(seasonRankLabel(2), "Season runner-up");
  assert.equal(seasonRankLabel(3), "Season third");
});
