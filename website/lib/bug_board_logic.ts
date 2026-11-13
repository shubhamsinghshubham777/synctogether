/**
 * Pure rules behind the internal bug board (website/app/internal/bugs).
 *
 * Kept free of React, Next and Supabase so node --test can drive every rule:
 * which lane a report sits in, what a close-as form accepts, which original a
 * duplicate really follows, and exactly what the user will read afterwards.
 * The database enforces the same rules (supabase/migrations/..._bug_board.sql);
 * this file is the board's friendly front of them.
 */

export type BugStatus = "received" | "looking" | "fixed" | "wontfix" | "duplicate";
export type BugLane = "received" | "looking" | "fixed";
export type BugCategory = "video" | "sound" | "sync" | "chat" | "camera" | "other";

export interface BugRow {
  id: string;
  code: string;
  category: string | null;
  note: string | null;
  /** Details the user added after sending. */
  appendix: string | null;
  status: BugStatus;
  fixedIn: string | null;
  reason: string | null;
  /** Row id of the root original this report follows, if any. */
  duplicateOf: string | null;
  publicTitle: string | null;
  createdAt: string;
  appVersion: string | null;
  os: string | null;
  route: string | null;
  sentryEventId: string | null;
  notifyWhenFixed: boolean;
}

export const MIN_REASON_CHARS = 20;

export const REASON_STARTERS: readonly string[] = [
  "Works as designed: ",
  "We can't reproduce this on current builds, so we're closing it for now. If it happens again, send us a new report and we'll look straight away.",
  "This is outside what the app supports today. ",
];

export const STARTER_LABELS: readonly string[] = [
  "Works as designed",
  "Can't reproduce on current builds",
  "Outside what the app supports",
];

const CATEGORY_LABELS: Record<string, string> = {
  video: "Video issue",
  sound: "Sound issue",
  sync: "Sync issue",
  chat: "Chat issue",
  camera: "Camera issue",
};

export function categoryLabel(category: string | null): string {
  return (category && CATEGORY_LABELS[category]) || "Bug report";
}

/** The neutral title the user sees for an original: never its reporter's note. */
export function publicTitleOf(row: Pick<BugRow, "publicTitle" | "category">): string {
  const t = row.publicTitle?.trim();
  return t ? t : categoryLabel(row.category);
}

/** The board's own headline for a card: the note's first line, clipped. */
export function cardTitle(row: Pick<BugRow, "note" | "publicTitle" | "category">, max = 90): string {
  const note = row.note?.trim().split(/\r?\n/)[0] ?? "";
  const base = note || publicTitleOf(row);
  return base.length > max ? `${base.slice(0, max - 1).trimEnd()}…` : base;
}

export function nonSpaceLength(s: string | null | undefined): number {
  return (s ?? "").replace(/\s/g, "").length;
}

/** Null when the reason is good enough to send to a user. */
export function reasonError(reason: string | null | undefined): string | null {
  const n = nonSpaceLength(reason);
  if (n === 0) return "Tell the user why. They will read this exactly as written.";
  if (n < MIN_REASON_CHARS) return `A little more, please: at least ${MIN_REASON_CHARS} characters (${n} so far).`;
  return null;
}

const SEMVER = /^[0-9]+\.[0-9]+\.[0-9]+$/;

/** "1.4.2+88" and " 1.4.2 " are both 1.4.2: build metadata never reaches the database. */
export function normalizeVersion(v: string | null | undefined): string {
  return (v ?? "").replace(/\+.*$/, "").trim();
}

/** Plain X.Y.Z with parts small enough to compare safely, or null. */
export function parseSemver(v: string | null | undefined): [number, number, number] | null {
  const n = normalizeVersion(v);
  if (!/^[0-9]{1,9}\.[0-9]{1,9}\.[0-9]{1,9}$/.test(n)) return null;
  const [a, b, c] = n.split(".").map((p) => parseInt(p, 10));
  return [a, b, c];
}

/** Mirror of the database's semver_gte: null when either side is unparsable. */
export function semverGte(a: string | null | undefined, b: string | null | undefined): boolean | null {
  const pa = parseSemver(a);
  const pb = parseSemver(b);
  if (!pa || !pb) return null;
  for (let i = 0; i < 3; i++) {
    if (pa[i] !== pb[i]) return pa[i] > pb[i];
  }
  return true;
}

/**
 * fixed_in is the FIRST version that contains the fix ("Fixed from X.Y.Z
 * onward"), so it must be a plain X.Y.Z. Null when it is good enough to send.
 */
export function versionError(version: string | null | undefined): string | null {
  const v = normalizeVersion(version);
  if (!v) return "Pick the first version that has the fix.";
  if (!SEMVER.test(v)) return "Use a plain version like 1.4.2.";
  return null;
}

/** The format error, or a fix that would predate the build the report came from. */
export function fixedFromError(
  version: string | null | undefined,
  reportedVersion: string | null | undefined,
): string | null {
  const bad = versionError(version);
  if (bad) return bad;
  if (semverGte(version, reportedVersion) === false) {
    return `That's older than ${normalizeVersion(reportedVersion)}, the version this report came from.`;
  }
  return null;
}

/** `version:` from pubspec.yaml, without the +build number. */
export function parsePubspecVersion(text: string): string | null {
  const m = /^version:\s*([0-9]+\.[0-9]+\.[0-9]+)/m.exec(text);
  return m ? m[1] : null;
}

/** `git tag --sort=-v:refname` output as plain versions, newest first. */
export function parseTagVersions(stdout: string, limit = 8): string[] {
  const out: string[] = [];
  for (const line of stdout.split(/\r?\n/)) {
    const m = /^v?([0-9]+\.[0-9]+\.[0-9]+)$/.exec(line.trim());
    if (m && !out.includes(m[1])) out.push(m[1]);
    if (out.length >= limit) break;
  }
  return out;
}

/** The dropdown: the version in pubspec.yaml first (marked current), then recent releases. */
export function releaseOptions(current: string | null, tags: readonly string[]): { value: string; label: string }[] {
  const out: { value: string; label: string }[] = [];
  if (current) out.push({ value: current, label: `${current} (current)` });
  for (const t of tags) if (t !== current) out.push({ value: t, label: t });
  return out;
}

/** Index rows by id once so the root lookups below stay O(1). */
export function indexById(rows: readonly BugRow[]): Map<string, BugRow> {
  return new Map(rows.map((r) => [r.id, r]));
}

/**
 * The root a report really follows. The database already stores the root, but a
 * form can be picked before the data refreshes, so the board resolves too:
 * following a follower follows its original. A cycle (or a dangling link) stops
 * at the last known row instead of looping.
 */
export function resolveRoot(row: BugRow, byId: ReadonlyMap<string, BugRow>): BugRow {
  const seen = new Set<string>([row.id]);
  let current = row;
  while (current.duplicateOf) {
    const next = byId.get(current.duplicateOf);
    if (!next || seen.has(next.id)) break;
    seen.add(next.id);
    current = next;
  }
  return current;
}

export type OriginalCheck =
  | { ok: true; root: BugRow; viaFollower: boolean }
  | { ok: false; error: string };

/** Whether `candidate` can be the original of `report`, and which row it resolves to. */
export function checkOriginal(
  report: BugRow,
  candidate: BugRow | null | undefined,
  byId: ReadonlyMap<string, BugRow>,
): OriginalCheck {
  if (!candidate) return { ok: false, error: "Pick the original report first." };
  if (candidate.id === report.id) return { ok: false, error: "A report can't be a duplicate of itself." };
  const root = resolveRoot(candidate, byId);
  if (root.id === report.id) return { ok: false, error: "That report already follows this one." };
  return { ok: true, root, viaFollower: root.id !== candidate.id };
}

/** Search the board for an original: by code or by words in the note or title. */
export function searchOriginals(
  report: BugRow,
  rows: readonly BugRow[],
  query: string,
  limit = 6,
): BugRow[] {
  const q = query.trim().toLowerCase();
  const byId = indexById(rows);
  const seen = new Set<string>();
  const out: BugRow[] = [];
  for (const r of rows) {
    if (r.id === report.id) continue;
    const root = resolveRoot(r, byId);
    if (root.id === report.id || seen.has(root.id)) continue;
    const hay = `${root.code} ${root.note ?? ""} ${root.publicTitle ?? ""} ${categoryLabel(root.category)}`.toLowerCase();
    if (q && !q.split(/\s+/).every((w) => hay.includes(w))) continue;
    seen.add(root.id);
    out.push(root);
  }
  // Open originals first: they are the ones a follower can still hope to see fixed.
  out.sort((a, b) => laneRank(a) - laneRank(b) || b.createdAt.localeCompare(a.createdAt));
  return out.slice(0, limit);
}

function laneRank(r: BugRow): number {
  switch (r.status) {
    case "looking":
      return 0;
    case "received":
      return 1;
    case "fixed":
      return 2;
    default:
      return 3;
  }
}

/** Which working lane a card sits in; closed originals live outside the lanes. */
export function laneOf(row: BugRow, byId: ReadonlyMap<string, BugRow>): BugLane | "closed" {
  const root = resolveRoot(row, byId);
  switch (root.status) {
    case "received":
    case "looking":
    case "fixed":
      return root.status;
    default:
      return "closed";
  }
}

/** How many other reports follow this card's root (the "N SAME" count). */
export function sameCounts(rows: readonly BugRow[]): Map<string, number> {
  const counts = new Map<string, number>();
  for (const r of rows) {
    if (r.duplicateOf) counts.set(r.duplicateOf, (counts.get(r.duplicateOf) ?? 0) + 1);
  }
  return counts;
}

export interface BoardFilters {
  search: string;
  category: string; // "all" or a BugCategory
  version: string; // "all" or an app version
  groupDuplicates: boolean;
}

export const DEFAULT_FILTERS: BoardFilters = {
  search: "",
  category: "all",
  version: "all",
  groupDuplicates: true,
};

export function filterRows(rows: readonly BugRow[], f: BoardFilters): BugRow[] {
  const q = f.search.trim().toLowerCase();
  return rows.filter((r) => {
    if (f.groupDuplicates && r.duplicateOf) return false;
    if (f.category !== "all" && (r.category ?? "other") !== f.category) return false;
    if (f.version !== "all" && r.appVersion !== f.version) return false;
    if (!q) return true;
    const hay = `${r.code} ${r.note ?? ""} ${r.publicTitle ?? ""} ${r.appVersion ?? ""} ${r.os ?? ""} ${r.fixedIn ?? ""}`.toLowerCase();
    return q.split(/\s+/).every((w) => hay.includes(w));
  });
}

export function knownVersions(rows: readonly BugRow[]): string[] {
  const set = new Set<string>();
  for (const r of rows) if (r.appVersion) set.add(r.appVersion);
  return [...set].sort(compareVersionsDesc);
}

export function compareVersionsDesc(a: string, b: string): number {
  const pa = a.split(".").map((p) => parseInt(p, 10) || 0);
  const pb = b.split(".").map((p) => parseInt(p, 10) || 0);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const d = (pb[i] ?? 0) - (pa[i] ?? 0);
    if (d !== 0) return d;
  }
  return 0;
}

/** The three user-visible lines for a close-as form, so the preview and the app can never drift. */
export function wontFixPreview(row: Pick<BugRow, "note" | "publicTitle" | "category">, reason: string) {
  return { pill: "CLOSED", title: cardTitle(row, 60), body: reason.trim() };
}

export function duplicatePreview(original: BugRow) {
  const status = original.status;
  const standing =
    status === "fixed"
      ? `fixed from ${original.fixedIn ?? "a coming version"} onward`
      : status === "wontfix"
        ? "closed"
        : status === "looking"
          ? "looking into it"
          : "received";
  const tail =
    status === "fixed"
      ? "It's fixed, so this one is too."
      : status === "wontfix"
        ? "They'll see the same reason."
        : "They'll be told the moment it's fixed.";
  return {
    pill: `SAME AS ${original.code}`,
    body: `Following ${original.code}: ${standing}. ${tail}`,
  };
}

export type MoveTarget = "received" | "looking" | "fixed" | "wontfix" | "duplicate";

/** What dropping a card on a target needs before it may move. */
export function moveNeeds(target: MoveTarget): "none" | "version" | "reason" | "original" {
  switch (target) {
    case "fixed":
      return "version";
    case "wontfix":
      return "reason";
    case "duplicate":
      return "original";
    default:
      return "none";
  }
}

/** Map the table's snake_case row (plus its jsonb context) into a board row. */
export function toBugRow(raw: Record<string, unknown>): BugRow {
  const ctx = (raw.context ?? {}) as Record<string, unknown>;
  const app = (ctx.app ?? {}) as Record<string, unknown>;
  const device = (ctx.device ?? {}) as Record<string, unknown>;
  const str = (v: unknown): string | null => (typeof v === "string" && v ? v : null);
  return {
    id: String(raw.id),
    code: String(raw.code),
    category: str(raw.category),
    note: str(raw.note),
    appendix: str(raw.note_appendix),
    status: raw.status as BugStatus,
    fixedIn: str(raw.fixed_in),
    reason: str(raw.reason),
    duplicateOf: str(raw.duplicate_of),
    publicTitle: str(raw.public_title),
    createdAt: String(raw.created_at),
    appVersion: str(app.version),
    os: str(device.os),
    route: str(ctx.route),
    sentryEventId: str(raw.sentry_event_id),
    notifyWhenFixed: raw.notify_when_fixed === true,
  };
}
