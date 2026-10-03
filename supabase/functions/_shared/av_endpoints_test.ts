import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import { cameraGrant, parseEndpoints } from "./av_endpoints.ts";

Deno.test("legacy single endpoint becomes 'default'", () => {
  assertEquals(
    parseEndpoints({ LIVEKIT_URL: "wss://a", LIVEKIT_API_KEY: "k", LIVEKIT_API_SECRET: "s" }),
    [{ id: "default", url: "wss://a", key: "k", secret: "s", trial: true }],
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

Deno.test("trials default on for our own servers and off for LiveKit Cloud", () => {
  const list = parseEndpoints({
    LIVEKIT_ENDPOINTS: JSON.stringify([
      { id: "self", url: "wss://av.example.com", key: "k", secret: "s" },
      { id: "cloud", url: "wss://proj-abc.livekit.cloud", key: "k", secret: "s" },
      { id: "forced", url: "wss://proj-def.livekit.cloud", key: "k", secret: "s", trial: true },
      { id: "off", url: "wss://av2.example.com", key: "k", secret: "s", trial: false },
    ]),
  });
  assertEquals(list.map((e) => e.trial), [true, false, true, false]);
  assertThrows(() =>
    parseEndpoints({
      LIVEKIT_ENDPOINTS: JSON.stringify([{ id: "a", url: "u", key: "k", secret: "s", trial: "yes" }]),
    })
  );
});

Deno.test("cameraGrant: who may publish video, and for how long", () => {
  const now = new Date("2026-10-04T12:00:00Z");
  const self = { trial: true };
  const cloud = { trial: false };
  const inFive = "2026-10-04T12:05:00Z";
  const ago = "2026-10-04T11:59:00Z";

  assertEquals(cameraGrant("video", null, cloud, now, 600), { camera: true, trial: false, ttlSeconds: 600 });
  assertEquals(cameraGrant("voice", null, self, now, 600), { camera: false, trial: false, ttlSeconds: 600 });
  assertEquals(cameraGrant("voice", inFive, self, now, 600), { camera: true, trial: true, ttlSeconds: 300 });
  assertEquals(cameraGrant("voice", inFive, cloud, now, 600).camera, false);
  assertEquals(cameraGrant("voice", ago, self, now, 600).camera, false);
  assertEquals(cameraGrant("none", inFive, self, now, 600).camera, false);
  assertEquals(cameraGrant("voice", "2026-10-04T13:00:00Z", self, now, 600).ttlSeconds, 600);
});
