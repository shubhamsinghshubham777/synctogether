import test from "node:test";
import assert from "node:assert/strict";
import {
  DEFAULT_FILTERS,
  MIN_REASON_CHARS,
  cardTitle,
  checkOriginal,
  compareVersionsDesc,
  duplicatePreview,
  filterRows,
  fixedFromError,
  indexById,
  knownVersions,
  laneOf,
  moveNeeds,
  normalizeVersion,
  nonSpaceLength,
  parsePubspecVersion,
  parseTagVersions,
  publicTitleOf,
  reasonError,
  releaseOptions,
  resolveRoot,
  sameCounts,
  searchOriginals,
  semverGte,
  toBugRow,
  versionError,
  wontFixPreview,
  type BugRow,
} from "../lib/bug_board_logic.ts";

let n = 0;
function row(over: Partial<BugRow> = {}): BugRow {
  n += 1;
  return {
    id: `id-${n}`,
    code: `BUG-${String(n).padStart(4, "A")}`,
    category: "chat",
    note: `note ${n}`,
    appendix: null,
    status: "received",
    fixedIn: null,
    reason: null,
    duplicateOf: null,
    publicTitle: null,
    createdAt: `2026-11-13T10:${String(n % 60).padStart(2, "0")}:00Z`,
    appVersion: "1.4.1",
    os: "ios",
    route: null,
    sentryEventId: null,
    notifyWhenFixed: false,
    ...over,
  };
}

test("a won't fix reason needs 20 non-space characters", () => {
  assert.equal(MIN_REASON_CHARS, 20);
  assert.ok(reasonError(""), "empty");
  assert.ok(reasonError(null), "null");
  assert.ok(reasonError("   too   short   "), "padding does not count");
  assert.ok(reasonError(`${" ".repeat(40)}abc`), "spaces never count");
  assert.equal(reasonError("This is how the fold works on purpose."), null);
  assert.equal(nonSpaceLength("a b\tc\nd"), 4);
});

test("fixed_in is the first version with the fix: plain X.Y.Z only", () => {
  assert.ok(versionError(""));
  assert.ok(versionError("   "));
  assert.ok(versionError("1.4"), "two parts");
  assert.ok(versionError("v1.4.2"), "a leading v");
  assert.ok(versionError("1.4.2-beta"), "a pre-release tag");
  assert.equal(versionError("1.4.2"), null);
  assert.equal(versionError(" 1.4.2+88 "), null, "build metadata is stripped, not refused");
  assert.equal(normalizeVersion(" 1.4.2+88 "), "1.4.2");
});

test("semverGte mirrors the database: numeric, build-blind, null when unparsable", () => {
  assert.equal(semverGte("1.4.10", "1.4.9"), true);
  assert.equal(semverGte("1.4.9", "1.4.10"), false);
  assert.equal(semverGte("1.4.2", "1.4.2"), true);
  assert.equal(semverGte("2.0.0", "1.99.99"), true);
  assert.equal(semverGte("1.4.2+88", "1.4.2"), true);
  assert.equal(semverGte("abc", "1.0.0"), null);
  assert.equal(semverGte("1.0", "1.0.0"), null);
  assert.equal(semverGte(null, "1.0.0"), null);
  assert.equal(semverGte("1.0.0", "99999999999.0.0"), null);
});

test("a fix may not predate the build the report came from, but unknown versions skip the guard", () => {
  assert.ok(fixedFromError("1.4.2", "1.4.3"));
  assert.match(fixedFromError("1.4.2", "1.4.3") ?? "", /1\.4\.3/);
  assert.equal(fixedFromError("1.4.3", "1.4.3"), null);
  assert.equal(fixedFromError("1.4.4", "1.4.3"), null);
  assert.equal(fixedFromError("1.0.0", null), null, "no reported version");
  assert.equal(fixedFromError("1.0.0", "dev"), null, "unparsable reported version");
  assert.ok(fixedFromError("v1", "1.4.3"), "format wins");
});

test("the version dropdown: pubspec first, then recent release tags", () => {
  assert.equal(parsePubspecVersion("name: x\nversion: 1.16.1+30\n"), "1.16.1");
  assert.equal(parsePubspecVersion("name: x\n"), null);
  assert.deepEqual(parseTagVersions("v1.16.1\nv1.15.0\nnot-a-tag\n1.14.0\nv1.15.0\n"), ["1.16.1", "1.15.0", "1.14.0"]);
  assert.equal(parseTagVersions("v1.0.0\nv1.0.1\nv1.0.2", 2).length, 2);
  assert.deepEqual(releaseOptions("1.16.1", ["1.16.1", "1.15.0"]), [
    { value: "1.16.1", label: "1.16.1 (current)" },
    { value: "1.15.0", label: "1.15.0" },
  ]);
  assert.deepEqual(releaseOptions(null, ["1.15.0"]), [{ value: "1.15.0", label: "1.15.0" }]);
  assert.deepEqual(releaseOptions(null, []), []);
});

test("moves that need a form say which one", () => {
  assert.equal(moveNeeds("received"), "none");
  assert.equal(moveNeeds("looking"), "none");
  assert.equal(moveNeeds("fixed"), "version");
  assert.equal(moveNeeds("wontfix"), "reason");
  assert.equal(moveNeeds("duplicate"), "original");
});

test("a duplicate resolves to its root, even through followers", () => {
  const root = row({ status: "looking" });
  const a = row({ status: "duplicate", duplicateOf: root.id });
  const b = row({ status: "duplicate", duplicateOf: a.id }); // stale link to a follower
  const byId = indexById([root, a, b]);
  assert.equal(resolveRoot(b, byId).id, root.id);
  assert.equal(resolveRoot(root, byId).id, root.id);
});

test("a cycle or dangling link stops instead of looping", () => {
  const a = row();
  const b = row({ duplicateOf: a.id });
  const cyc = { ...a, duplicateOf: b.id };
  assert.doesNotThrow(() => resolveRoot(cyc, indexById([cyc, b])));
  const lost = row({ duplicateOf: "gone" });
  assert.equal(resolveRoot(lost, indexById([lost])).id, lost.id);
});

test("an original is validated: not itself, not a report that already follows it", () => {
  const root = row();
  const follower = row({ status: "duplicate", duplicateOf: root.id });
  const other = row();
  const byId = indexById([root, follower, other]);
  assert.equal(checkOriginal(root, null, byId).ok, false);
  assert.equal(checkOriginal(root, root, byId).ok, false, "self");
  assert.equal(checkOriginal(root, follower, byId).ok, false, "its own follower");
  const viaFollower = checkOriginal(other, follower, byId);
  assert.ok(viaFollower.ok);
  if (viaFollower.ok) {
    assert.equal(viaFollower.root.id, root.id);
    assert.equal(viaFollower.viaFollower, true);
  }
});

test("search offers roots only, open ones first, never the report itself", () => {
  const report = row({ note: "stuck" });
  const looking = row({ status: "looking", note: "chat cellular" });
  const received = row({ note: "chat on wifi" });
  const fixed = row({ status: "fixed", fixedIn: "1.4.2", note: "chat once broke" });
  const follower = row({ status: "duplicate", duplicateOf: looking.id, note: "cellular again" });
  const rows = [report, fixed, received, follower, looking];
  const hits = searchOriginals(report, rows, "chat");
  assert.deepEqual(
    hits.map((r) => r.code),
    [looking.code, received.code, fixed.code],
  );
  assert.ok(!hits.some((r) => r.id === report.id));
  const viaFollowerText = searchOriginals(report, rows, "again");
  assert.deepEqual(viaFollowerText.map((r) => r.code), [], "a follower's own words are not searched; its root is");
  assert.deepEqual(searchOriginals(report, rows, "").map((r) => r.id).includes(follower.id), false);
});

test("lanes follow the root's status; closed roots leave the lanes", () => {
  const root = row({ status: "looking" });
  const follower = row({ status: "duplicate", duplicateOf: root.id });
  const fixed = row({ status: "fixed", fixedIn: "1.4.2" });
  const closed = row({ status: "wontfix", reason: "Works as designed here." });
  const closedFollower = row({ status: "wontfix", reason: "x", duplicateOf: closed.id });
  const byId = indexById([root, follower, fixed, closed, closedFollower]);
  assert.equal(laneOf(root, byId), "looking");
  assert.equal(laneOf(follower, byId), "looking");
  assert.equal(laneOf(fixed, byId), "fixed");
  assert.equal(laneOf(closed, byId), "closed");
  assert.equal(laneOf(closedFollower, byId), "closed");
});

test("same counts tally followers per root", () => {
  const root = row();
  const a = row({ status: "duplicate", duplicateOf: root.id });
  const b = row({ status: "duplicate", duplicateOf: root.id });
  const counts = sameCounts([root, a, b, row()]);
  assert.equal(counts.get(root.id), 2);
  assert.equal(counts.get(a.id), undefined);
});

test("filters: grouping hides followers, category, version and words narrow the board", () => {
  const root = row({ note: "black screen", category: "video", appVersion: "1.4.1" });
  const follower = row({ status: "duplicate", duplicateOf: root.id, note: "black screen again" });
  const old = row({ note: "freeze", category: "camera", appVersion: "1.4.0" });
  const rows = [root, follower, old];
  assert.deepEqual(filterRows(rows, DEFAULT_FILTERS).map((r) => r.id), [root.id, old.id]);
  assert.equal(filterRows(rows, { ...DEFAULT_FILTERS, groupDuplicates: false }).length, 3);
  assert.deepEqual(filterRows(rows, { ...DEFAULT_FILTERS, category: "camera" }).map((r) => r.id), [old.id]);
  assert.deepEqual(filterRows(rows, { ...DEFAULT_FILTERS, version: "1.4.0" }).map((r) => r.id), [old.id]);
  assert.deepEqual(filterRows(rows, { ...DEFAULT_FILTERS, search: "BLACK screen" }).map((r) => r.id), [root.id]);
});

test("versions are listed newest first", () => {
  assert.ok(compareVersionsDesc("1.10.0", "1.9.0") < 0, "1.10 is newer than 1.9");
  const rows = [row({ appVersion: "1.4.0" }), row({ appVersion: "1.10.1" }), row({ appVersion: "1.4.1" }), row({ appVersion: null })];
  assert.deepEqual(knownVersions(rows), ["1.10.1", "1.4.1", "1.4.0"]);
});

test("users see a neutral title for an original, never its reporter's note", () => {
  const withNote = row({ note: "my private description", category: "video" });
  assert.equal(publicTitleOf(withNote), "Video issue");
  assert.equal(publicTitleOf({ ...withNote, publicTitle: "  Video goes black  " }), "Video goes black");
  assert.equal(publicTitleOf(row({ category: null })), "Bug report");
  assert.ok(!duplicatePreview(row({ note: "my private description" })).body.includes("my private description"));
});

test("previews say exactly what the user will read", () => {
  const r = row({ note: "Seek bar jumps on fold\nmore detail" });
  assert.equal(cardTitle(r), "Seek bar jumps on fold");
  const w = wontFixPreview(r, "  Works as designed.  ");
  assert.deepEqual(w, { pill: "CLOSED", title: "Seek bar jumps on fold", body: "Works as designed." });
  const open = duplicatePreview(row({ code: "BUG-3F9A", status: "looking" }));
  assert.equal(open.pill, "SAME AS BUG-3F9A");
  assert.match(open.body, /looking into it/);
  assert.match(duplicatePreview(row({ code: "BUG-3F9A", status: "fixed", fixedIn: "1.4.2" })).body, /fixed from 1\.4\.2 onward/);
  assert.match(duplicatePreview(row({ code: "BUG-3F9A", status: "wontfix" })).body, /same reason/);
});

test("rows map from the table's shape, tolerating a sparse context", () => {
  const mapped = toBugRow({
    id: "1",
    code: "BUG-7K2M",
    category: "video",
    note: "went black",
    note_appendix: "also on wifi",
    status: "fixed",
    fixed_in: "1.4.2",
    reason: null,
    duplicate_of: null,
    public_title: null,
    created_at: "2026-11-13T10:00:00Z",
    sentry_event_id: "evt1",
    notify_when_fixed: true,
    context: { app: { version: "1.4.1" }, device: { os: "ios" }, route: "/lobby" },
  });
  assert.equal(mapped.appVersion, "1.4.1");
  assert.equal(mapped.os, "ios");
  assert.equal(mapped.route, "/lobby");
  assert.equal(mapped.appendix, "also on wifi");
  assert.equal(mapped.notifyWhenFixed, true);
  const sparse = toBugRow({ id: "2", code: "BUG-2222", status: "received", created_at: "x", context: null });
  assert.equal(sparse.appVersion, null);
  assert.equal(sparse.note, null);
});
