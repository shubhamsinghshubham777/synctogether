import test from "node:test";
import assert from "node:assert/strict";
import { WEB_EVENT_NAMES, eventPath, isWebEventName } from "../lib/web-events.ts";

test("only listed event names are accepted", () => {
  for (const name of WEB_EVENT_NAMES) assert.equal(isWebEventName(name), true);
  assert.equal(isWebEventName("join_handed_off "), false);
  assert.equal(isWebEventName("page_view"), false);
  assert.equal(isWebEventName(undefined), false);
  assert.equal(isWebEventName({ name: "join_fallback" }), false);
});

test("the invite code never reaches the events table", () => {
  assert.equal(eventPath("/join/ABC123"), "/join/*");
  assert.equal(eventPath("/join/ABC123?x=1#y"), "/join/*");
  assert.equal(eventPath("/download"), "/download");
  assert.equal(eventPath("/download?code=ABC123"), "/download");
});

test("a malformed path falls back to the root", () => {
  assert.equal(eventPath(undefined), "/");
  assert.equal(eventPath("join/ABC123"), "/");
  assert.equal(eventPath(42), "/");
  assert.equal(eventPath("/" + "a".repeat(400)).length, 255);
});
