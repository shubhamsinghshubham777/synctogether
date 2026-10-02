import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import { parseEndpoints } from "./av_endpoints.ts";

Deno.test("legacy single endpoint becomes 'default'", () => {
  assertEquals(
    parseEndpoints({ LIVEKIT_URL: "wss://a", LIVEKIT_API_KEY: "k", LIVEKIT_API_SECRET: "s" }),
    [{ id: "default", url: "wss://a", key: "k", secret: "s" }],
  );
});

Deno.test("nothing configured is an empty list", () => {
  assertEquals(parseEndpoints({}), []);
});

Deno.test("LIVEKIT_ENDPOINTS wins and keeps its order", () => {
  const list = parseEndpoints({
    LIVEKIT_URL: "wss://legacy",
    LIVEKIT_API_KEY: "k",
    LIVEKIT_API_SECRET: "s",
    LIVEKIT_ENDPOINTS: JSON.stringify([
      { id: "self", url: "wss://self", key: "k1", secret: "s1" },
      { id: "cloud", url: "wss://cloud", key: "k2", secret: "s2" },
    ]),
  });
  assertEquals(list.map((e) => e.id), ["self", "cloud"]);
});

Deno.test("a malformed list fails loudly rather than silently dropping AV", () => {
  assertThrows(() => parseEndpoints({ LIVEKIT_ENDPOINTS: "{" }));
  assertThrows(() => parseEndpoints({ LIVEKIT_ENDPOINTS: '[{"id":"a","url":"wss://a"}]' }));
  assertThrows(() =>
    parseEndpoints({
      LIVEKIT_ENDPOINTS: JSON.stringify([
        { id: "a", url: "u", key: "k", secret: "s" },
        { id: "a", url: "u", key: "k", secret: "s" },
      ]),
    })
  );
});
