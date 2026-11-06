import { describe, expect, it } from "vitest";
import { signToken, verifyToken } from "../src/sign";

// Pinned vector: supabase/functions/_shared/media_edge_test.ts asserts the same value.
const VECTOR = { secret: "test-secret", key: "users/u1/room/abc/movie.mkv", exp: 1900000000, sig: "eVoMUIcrACMIpnE30LQKjHjbahixXxOf-5aC2540Lbc" };

describe("token", () => {
  it("matches the cross-implementation vector", async () => {
    expect(await signToken(VECTOR.secret, VECTOR.key, VECTOR.exp)).toBe(VECTOR.sig);
  });
  it("accepts a valid token", async () => {
    expect(await verifyToken(VECTOR.secret, VECTOR.key, "1900000000", VECTOR.sig, 1899999000, 90000)).toBe("ok");
  });
  it("rejects expired, far-future, tampered and malformed tokens", async () => {
    const v = (key: string, exp: string | null, sig: string | null, now = 1899999000) =>
      verifyToken(VECTOR.secret, key, exp, sig, now, 90000);
    expect(await v(VECTOR.key, "1900000000", VECTOR.sig, 1900000001)).toBe("expired");
    expect(await v(VECTOR.key, "1900000000", VECTOR.sig, 1800000000)).toBe("too_far");
    expect(await v(VECTOR.key + "x", "1900000000", VECTOR.sig)).toBe("bad_signature");
    expect(await v(VECTOR.key, "1900000001", VECTOR.sig)).toBe("bad_signature");
    expect(await verifyToken("other", VECTOR.key, "1900000000", VECTOR.sig, 1899999000, 90000)).toBe("bad_signature");
    expect(await v(VECTOR.key, null, VECTOR.sig)).toBe("malformed");
    expect(await v(VECTOR.key, "abc", VECTOR.sig)).toBe("malformed");
    expect(await v(VECTOR.key, "1900000000", "short")).toBe("malformed");
    expect(await v(VECTOR.key, "1900000000", "!!!" + VECTOR.sig.slice(3))).toBe("malformed");
  });
});
