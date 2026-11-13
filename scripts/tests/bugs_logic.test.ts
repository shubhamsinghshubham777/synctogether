// Run: node --test scripts/tests/bugs_logic.test.ts   (also run by test_bugs_cli.py in CI)
import test from "node:test";
import assert from "node:assert/strict";
import {
  compareVersions,
  normalizeVersion,
  parseArgs,
  parseFixesTrailers,
  parseVersion,
  pickSince,
  planClose,
  reasonError,
  releaseTags,
  renderPlan,
  sameCounts,
  searchTerm,
} from "../lib/bugs_logic.ts";
import type { BugRow } from "../lib/bugs_logic.ts";

test("versions: parse, normalize and compare numerically", () => {
  assert.deepEqual(parseVersion("1.4.2"), [1, 4, 2]);
  assert.deepEqual(parseVersion("v1.4.2+88"), [1, 4, 2]);
  assert.equal(parseVersion("1.4"), null);
  assert.equal(parseVersion("next week"), null);
  assert.equal(normalizeVersion("v2.0.10+3"), "2.0.10");
  assert.ok((compareVersions("1.4.10", "1.4.9") as number) > 0);
  assert.equal(compareVersions("1.4.2", "1.4.2"), 0);
  assert.ok((compareVersions("1.3.9", "1.4.0") as number) < 0);
  assert.equal(compareVersions("1.4", "1.4.0"), null);
});

test("trailers: only a line that starts with Fixes-Bug closes a ticket", () => {
  const log = [
    "fix(sync): stop the drift after two pauses",
    "",
    "Mentions BUG-AAAA in prose, which must not count.",
    "",
    "Fixes-Bug: BUG-7K2M",
    "fixes-bug: bug-3f9a",
    "Fixes-Bug: BUG-1C0D, BUG-2H7W BUG-7K2M",
    "\0",
    "chore: nothing",
    "Fixes-Bug: not-a-code",
    "  Fixes-Bug: BUG-9Z9Z",
  ].join("\n");
  assert.deepEqual(parseFixesTrailers(log), ["BUG-7K2M", "BUG-3F9A", "BUG-1C0D", "BUG-2H7W", "BUG-9Z9Z"]);
  assert.deepEqual(parseFixesTrailers(""), []);
});

test("reason: twenty characters once whitespace is ignored", () => {
  assert.notEqual(reasonError(undefined), null);
  assert.notEqual(reasonError("too short   here"), null);
  assert.equal(reasonError("This is how the fold works on purpose."), null);
});

test("release tags: newest first, retired run-id style included, junk ignored", () => {
  const tags = ["v1.9.0", "v1.10.0", "v1.4.2_123456", "v1.4.2", "latest", "v2", "metadata/version/1.0.0"];
  assert.deepEqual(
    releaseTags(tags).map((t) => t.version),
    ["1.10.0", "1.9.0", "1.4.2", "1.4.2"],
  );
  assert.equal(releaseTags(tags)[0].tag, "v1.10.0");
});

test("pickSince: the tag of the highest fixed version, so a skipped release is re-scanned", () => {
  const tags = ["v1.4.0", "v1.4.1", "v1.4.2"];
  // 1.4.2 was tagged because one store accepted it, but no ticket was closed from it.
  assert.equal(pickSince({ tags, targetVersion: "1.4.3", maxFixedVersion: "1.4.1" }), "v1.4.1");
  // nothing fixed yet on the board: the newest tag below the target.
  assert.equal(pickSince({ tags, targetVersion: "1.4.3", maxFixedVersion: null }), "v1.4.2");
  // the target's own tag is never the start.
  assert.equal(pickSince({ tags, targetVersion: "1.4.2", maxFixedVersion: null }), "v1.4.1");
  // a fixed version with no local tag falls back to the previous tag.
  assert.equal(pickSince({ tags, targetVersion: "1.4.3", maxFixedVersion: "1.3.0" }), "v1.4.2");
  assert.equal(pickSince({ tags: [], targetVersion: "1.0.0" }), null);
});

function rows(list: BugRow[]): Map<string, BugRow> {
  return new Map(list.map((r) => [r.code, r]));
}

test("planClose: only waiting tickets are fixed; people's decisions and followers are left alone", () => {
  const plan = planClose({
    codes: ["BUG-AAAA", "BUG-BBBB", "BUG-CCCC", "BUG-DDDD", "BUG-EEEE", "BUG-FFFF", "BUG-GGGG"],
    version: "1.4.3",
    rows: rows([
      { code: "BUG-AAAA", status: "looking" },
      { code: "BUG-BBBB", status: "received" },
      { code: "BUG-CCCC", status: "wontfix" },
      { code: "BUG-DDDD", status: "duplicate", duplicate_of_code: "BUG-AAAA" },
      { code: "BUG-EEEE", status: "fixed", fixed_in: "1.4.2" },
      { code: "BUG-FFFF", status: "fixed", fixed_in: "1.4.9" },
    ]),
  });
  const by = Object.fromEntries(plan.map((l) => [l.code, l.action]));
  assert.deepEqual(by, {
    "BUG-AAAA": "fix",
    "BUG-BBBB": "fix",
    "BUG-CCCC": "skip",
    "BUG-DDDD": "skip",
    "BUG-EEEE": "skip",
    "BUG-FFFF": "skip",
    "BUG-GGGG": "skip",
  });
});

test("planClose: a later fixed version is only lowered with --force", () => {
  const input = {
    codes: ["BUG-FFFF"],
    version: "1.4.3",
    rows: rows([{ code: "BUG-FFFF", status: "fixed", fixed_in: "1.4.9" }]),
  };
  assert.equal(planClose(input)[0].action, "skip");
  assert.equal(planClose({ ...input, force: true })[0].action, "fix");
});

test("renderPlan counts what will change", () => {
  const text = renderPlan("Plan:", [
    { code: "BUG-AAAA", action: "fix", why: "looking -> fixed from 1.4.3" },
    { code: "BUG-BBBB", action: "skip", why: "already fixed from 1.4.2" },
  ]);
  assert.match(text, /FIX\s+BUG-AAAA/);
  assert.match(text, /1 ticket\(s\) will change/);
  assert.match(renderPlan("Plan:", []), /Nothing to change/);
});

test("args and search terms", () => {
  assert.deepEqual(parseArgs(["fix", "BUG-AAAA", "--version=1.4.3", "--confirm"]), {
    cmd: "fix",
    pos: ["BUG-AAAA"],
    flags: { version: "1.4.3", confirm: "true" },
  });
  assert.equal(parseArgs([]).cmd, "help");
  assert.deepEqual(parseArgs(["--local", "looking", "BUG-AAAA"]), {
    cmd: "looking",
    pos: ["BUG-AAAA"],
    flags: { local: "true" },
  });
  assert.equal(parseArgs(["wontfix", "BUG-AAAA", "--reason=a=b, c"]).flags.reason, "a=b, c");
  assert.equal(searchTerm("chat (cellular), 100%*"), "chat cellular 100");
});

test("sameCounts: a root counts its followers, a follower counts its siblings", () => {
  const counts = sameCounts([
    { id: "root", duplicate_of: null },
    { id: "a", duplicate_of: "root" },
    { id: "b", duplicate_of: "root" },
    { id: "lonely", duplicate_of: null },
  ]);
  assert.equal(counts.get("root"), 2);
  assert.equal(counts.get("a"), 2);
  assert.equal(counts.get("lonely"), 0);
});
