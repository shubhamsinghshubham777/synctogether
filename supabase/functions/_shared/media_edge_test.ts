import { assertEquals, assertMatch } from "jsr:@std/assert@1";
import { buildEdgeUrl, clampChunkBytes, clampMaxParallel, resolveEdgeConfig, signEdgeToken } from "./media_edge.ts";

Deno.test("signature matches the Worker's pinned vector", async () => {
  // Same vector as deploy/media-edge/test/sign.test.ts.
  assertEquals(
    await signEdgeToken("test-secret", "users/u1/room/abc/movie.mkv", 1900000000),
    "eVoMUIcrACMIpnE30LQKjHjbahixXxOf-5aC2540Lbc",
  );
});

Deno.test("flag logic: only enabled + https base_url + secret turns the edge on", () => {
  const on = { enabled: true, base_url: "https://media.example.com/" };
  assertEquals(resolveEdgeConfig(on, "s"), {
    baseUrl: "https://media.example.com",
    secret: "s",
    chunkBytes: 8 * 1024 * 1024,
    maxParallel: 4,
  });
  assertEquals(resolveEdgeConfig(on, undefined), null); // no secret
  assertEquals(resolveEdgeConfig(on, ""), null);
  assertEquals(resolveEdgeConfig({ ...on, enabled: false }, "s"), null);
  assertEquals(resolveEdgeConfig({ ...on, enabled: "true" }, "s"), null);
  assertEquals(resolveEdgeConfig({ enabled: true, base_url: null }, "s"), null);
  assertEquals(resolveEdgeConfig({ enabled: true, base_url: "http://media.example.com" }, "s"), null);
  assertEquals(resolveEdgeConfig({ enabled: true, base_url: "not a url" }, "s"), null);
  assertEquals(resolveEdgeConfig(null, "s"), null);
  assertEquals(resolveEdgeConfig(undefined, "s"), null);
  assertEquals(resolveEdgeConfig("x", "s"), null);
  assertEquals(
    resolveEdgeConfig({ enabled: true, base_url: "http://127.0.0.1:8787" }, "s")?.baseUrl,
    "http://127.0.0.1:8787",
  );
});

Deno.test("buildEdgeUrl encodes the key per segment and signs the decoded key", async () => {
  const cfg = { baseUrl: "https://media.example.com", secret: "test-secret", chunkBytes: 8388608, maxParallel: 4 };
  const url = await buildEdgeUrl(cfg, "users/u 1/a+b.mkv", 3600, 1_800_000_000_000);
  const u = new URL(url);
  assertEquals(u.origin, "https://media.example.com");
  assertEquals(u.pathname, "/v1/users/u%201/a%2Bb.mkv");
  assertEquals(u.searchParams.get("exp"), "1800003600");
  assertMatch(u.searchParams.get("sig")!, /^[A-Za-z0-9_-]{43}$/);
  assertEquals(u.searchParams.get("sig"), await signEdgeToken("test-secret", "users/u 1/a+b.mkv", 1800003600));
});

Deno.test("chunk_bytes: default 8 MiB, clamp 4-32 MiB, multiple of the Worker's 4 MiB chunk", () => {
  const MiB = 1024 * 1024;
  assertEquals(clampChunkBytes(undefined), 8 * MiB);
  assertEquals(clampChunkBytes("16"), 8 * MiB);
  assertEquals(clampChunkBytes(NaN), 8 * MiB);
  assertEquals(clampChunkBytes(Infinity), 8 * MiB);
  assertEquals(clampChunkBytes(1), 4 * MiB);
  assertEquals(clampChunkBytes(-5), 4 * MiB);
  assertEquals(clampChunkBytes(4 * MiB), 4 * MiB);
  assertEquals(clampChunkBytes(10 * MiB), 8 * MiB); // rounded down to 4 MiB steps
  assertEquals(clampChunkBytes(32 * MiB), 32 * MiB);
  assertEquals(clampChunkBytes(1024 * MiB), 32 * MiB);
});

Deno.test("max_parallel: default 4, clamp 1-8", () => {
  assertEquals(clampMaxParallel(undefined), 4);
  assertEquals(clampMaxParallel("3"), 4);
  assertEquals(clampMaxParallel(0), 1);
  assertEquals(clampMaxParallel(-2), 1);
  assertEquals(clampMaxParallel(3.9), 3);
  assertEquals(clampMaxParallel(99), 8);
});

Deno.test("hints flow from the setting and are clamped", () => {
  const cfg = resolveEdgeConfig(
    { enabled: true, base_url: "https://m.example.com", chunk_bytes: 999999999, max_parallel: 0 },
    "s",
  );
  assertEquals([cfg?.chunkBytes, cfg?.maxParallel], [32 * 1024 * 1024, 1]);
  const dflt = resolveEdgeConfig({ enabled: true, base_url: "https://m.example.com" }, "s");
  assertEquals([dflt?.chunkBytes, dflt?.maxParallel], [8 * 1024 * 1024, 4]);
});
