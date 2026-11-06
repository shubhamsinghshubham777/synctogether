export type RangeResult =
  | { kind: "none" } // no Range, or one we ignore (malformed / multi-range): serve 200
  | { kind: "range"; start: number; end: number } // inclusive, clamped to size
  | { kind: "unsatisfiable" };

/** RFC 9110 single byte-range. `size` is the full object length. */
export function parseRange(header: string | null, size: number): RangeResult {
  if (!header) return { kind: "none" };
  const m = /^bytes=(\d*)-(\d*)$/.exec(header.trim());
  if (!m) return { kind: "none" }; // other units, multi-range, junk: ignore the header
  const [, a, b] = m;
  if (a === "" && b === "") return { kind: "none" };
  if (a === "") {
    const n = Number(b);
    if (!Number.isSafeInteger(n) || n === 0 || size === 0) return { kind: "unsatisfiable" };
    return { kind: "range", start: Math.max(0, size - n), end: size - 1 };
  }
  const start = Number(a);
  if (!Number.isSafeInteger(start)) return { kind: "none" };
  if (start >= size) return { kind: "unsatisfiable" };
  let end = b === "" ? size - 1 : Number(b);
  if (!Number.isSafeInteger(end)) return { kind: "none" };
  if (end < start) return { kind: "none" }; // invalid spec: ignore, per RFC
  end = Math.min(end, size - 1);
  return { kind: "range", start, end };
}

/** Does an If-None-Match / If-Range validator list contain this strong etag? */
export function etagMatches(header: string | null, etag: string): boolean {
  if (!header) return false;
  if (header.trim() === "*") return true;
  const strip = (v: string) => v.trim().replace(/^W\//, "");
  return header.split(",").some((v) => strip(v) === etag);
}
