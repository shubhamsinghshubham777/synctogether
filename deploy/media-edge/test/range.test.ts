import { describe, expect, it } from "vitest";
import { etagMatches, parseRange } from "../src/range";

describe("parseRange", () => {
  const size = 1000;
  it("no header or ignorable headers serve the whole object", () => {
    expect(parseRange(null, size)).toEqual({ kind: "none" });
    expect(parseRange("items=0-1", size)).toEqual({ kind: "none" });
    expect(parseRange("bytes=0-1,5-6", size)).toEqual({ kind: "none" });
    expect(parseRange("bytes=-", size)).toEqual({ kind: "none" });
    expect(parseRange("bytes=9-3", size)).toEqual({ kind: "none" });
  });
  it("closed, open and suffix ranges", () => {
    expect(parseRange("bytes=0-99", size)).toEqual({ kind: "range", start: 0, end: 99 });
    expect(parseRange("bytes=900-", size)).toEqual({ kind: "range", start: 900, end: 999 });
    expect(parseRange("bytes=-100", size)).toEqual({ kind: "range", start: 900, end: 999 });
    expect(parseRange("bytes=-5000", size)).toEqual({ kind: "range", start: 0, end: 999 });
  });
  it("clamps the end to the object", () => {
    expect(parseRange("bytes=990-5000", size)).toEqual({ kind: "range", start: 990, end: 999 });
  });
  it("unsatisfiable", () => {
    expect(parseRange("bytes=1000-", size)).toEqual({ kind: "unsatisfiable" });
    expect(parseRange("bytes=-0", size)).toEqual({ kind: "unsatisfiable" });
    expect(parseRange("bytes=0-0", 0)).toEqual({ kind: "unsatisfiable" });
  });
});

describe("etagMatches", () => {
  it("handles lists, weak prefixes and *", () => {
    expect(etagMatches('"a", "b"', '"b"')).toBe(true);
    expect(etagMatches('W/"a"', '"a"')).toBe(true);
    expect(etagMatches("*", '"a"')).toBe(true);
    expect(etagMatches('"c"', '"a"')).toBe(false);
    expect(etagMatches(null, '"a"')).toBe(false);
  });
});
