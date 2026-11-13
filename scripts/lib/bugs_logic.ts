/**
 * Pure logic behind scripts/bugs.ts: nothing here touches the network, git or
 * the filesystem, so it is unit-tested in scripts/tests/bugs_logic.test.ts.
 *
 * Only erasable TypeScript syntax (no enums, no parameter properties): Node runs
 * this file directly with type stripping.
 */

export const BUG_CODE = /^BUG-[A-Z0-9]{4}$/;

/** The statuses users can see. `looking` is the one an agent sets by itself. */
export type BugStatus = "received" | "looking" | "fixed" | "wontfix" | "duplicate";

export interface BugRow {
  code: string;
  status: BugStatus;
  fixed_in?: string | null;
  duplicate_of_code?: string | null;
}

export function normalizeCode(raw: string): string {
  return raw.trim().toUpperCase();
}

export function isBugCode(raw: string): boolean {
  return BUG_CODE.test(raw);
}

export type Version = [number, number, number];

/** `1.4.2`, `v1.4.2` or `1.4.2+88` become [1, 4, 2]; anything else is null. */
export function parseVersion(raw: string | null | undefined): Version | null {
  if (!raw) return null;
  const m = /^v?(\d+)\.(\d+)\.(\d+)(?:\+.*)?$/.exec(raw.trim());
  return m ? [Number(m[1]), Number(m[2]), Number(m[3])] : null;
}

export function normalizeVersion(raw: string): string | null {
  const v = parseVersion(raw);
  return v ? v.join(".") : null;
}

/** Negative when a < b, 0 when equal, positive when a > b. Null if either is not a version. */
export function compareVersions(a: string, b: string): number | null {
  const x = parseVersion(a);
  const y = parseVersion(b);
  if (!x || !y) return null;
  for (let i = 0; i < 3; i++) {
    if (x[i] !== y[i]) return x[i] - y[i];
  }
  return 0;
}

/** Same rule the database enforces: at least 20 characters once whitespace is ignored. */
export function reasonLength(reason: string): number {
  return reason.replace(/\s/g, "").length;
}

export function reasonError(reason: string | undefined): string | null {
  if (!reason || reasonLength(reason) < 20) {
    return "A won't-fix needs the reason the user will read: at least 20 characters.";
  }
  return null;
}

/**
 * Codes named by `Fixes-Bug:` trailers in `git log --format=%B%x00` output.
 * Only a line that starts with the trailer key counts, so prose that merely
 * mentions a ticket never closes it. One trailer per ticket is the convention,
 * but a comma or space separated list on one line is accepted too.
 */
export function parseFixesTrailers(log: string): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const line of log.split(/\r?\n/)) {
    const m = /^\s*fixes-bug\s*:\s*(.+)$/i.exec(line);
    if (!m) continue;
    for (const token of m[1].split(/[\s,]+/)) {
      const code = normalizeCode(token);
      if (isBugCode(code) && !seen.has(code)) {
        seen.add(code);
        out.push(code);
      }
    }
  }
  return out;
}

export interface TagVersion {
  tag: string;
  version: string;
}

/** Release tags (`v1.4.2`, or the retired `v1.4.2_123456`) with their versions, newest first. */
export function releaseTags(tags: string[]): TagVersion[] {
  const out: TagVersion[] = [];
  for (const tag of tags) {
    const m = /^v(\d+\.\d+\.\d+)(?:_\d+)?$/.exec(tag.trim());
    if (m) out.push({ tag: tag.trim(), version: m[1] });
  }
  return out.sort((a, b) => compareVersions(b.version, a.version) ?? 0);
}

/**
 * Where the scan of commits starts. The `tag` job tags a build as soon as ONE
 * store accepted it, so "the last v* tag" can sit on a release that another
 * store rejected, and the tickets of that release would be skipped for good.
 * The board is the record of what has been closed instead: start at the tag of
 * the highest version any ticket is already fixed from, and fall back to the
 * newest tag below the version being closed. Re-closing is harmless because a
 * ticket that is already fixed is skipped.
 */
export function pickSince(args: {
  tags: string[];
  targetVersion: string;
  maxFixedVersion?: string | null;
}): string | null {
  const all = releaseTags(args.tags);
  const below = all.filter((t) => (compareVersions(t.version, args.targetVersion) ?? 1) < 0);
  if (args.maxFixedVersion) {
    const hit = below.find((t) => compareVersions(t.version, args.maxFixedVersion as string) === 0);
    if (hit) return hit.tag;
  }
  return below[0]?.tag ?? null;
}

export interface PlanLine {
  code: string;
  action: "fix" | "skip";
  why: string;
}

/**
 * What close-from-commits will do with each ticket the commits name. Only a
 * ticket still waiting (received or looking) is marked fixed. A won't-fix was a
 * human decision and is never overridden, a follower follows its original, and
 * a ticket already fixed from the same or an earlier version stays as it is. A
 * lower version than the one on the board needs --force.
 */
export function planClose(args: {
  codes: string[];
  rows: Map<string, BugRow>;
  version: string;
  force?: boolean;
}): PlanLine[] {
  const lines: PlanLine[] = [];
  for (const code of args.codes) {
    const row = args.rows.get(code);
    if (!row) {
      lines.push({ code, action: "skip", why: "not on the board (typo, or another environment)" });
      continue;
    }
    switch (row.status) {
      case "received":
      case "looking":
        lines.push({ code, action: "fix", why: `${row.status} -> fixed from ${args.version}` });
        break;
      case "wontfix":
        lines.push({ code, action: "skip", why: "closed as won't fix by a person; left alone" });
        break;
      case "duplicate":
        lines.push({
          code,
          action: "skip",
          why: `follows ${row.duplicate_of_code ?? "its original"}; it is fixed when that one is`,
        });
        break;
      case "fixed": {
        const cmp = compareVersions(row.fixed_in ?? "", args.version);
        if (cmp === null || cmp <= 0) {
          lines.push({ code, action: "skip", why: `already fixed from ${row.fixed_in}` });
        } else if (args.force) {
          lines.push({ code, action: "fix", why: `lowers fixed from ${row.fixed_in} to ${args.version} (--force)` });
        } else {
          lines.push({
            code,
            action: "skip",
            why: `already fixed from ${row.fixed_in}, which is later; --force lowers it`,
          });
        }
        break;
      }
    }
  }
  return lines;
}

export function renderPlan(title: string, lines: PlanLine[]): string {
  const out = [title];
  for (const l of lines) {
    out.push(`  ${l.action === "fix" ? "FIX " : "skip"}  ${l.code}  ${l.why}`);
  }
  const n = lines.filter((l) => l.action === "fix").length;
  out.push(n === 0 ? "Nothing to change." : `${n} ticket(s) will change.`);
  return out.join("\n");
}

export interface ParsedArgs {
  cmd: string;
  pos: string[];
  flags: Record<string, string>;
}

export function parseArgs(args: string[]): ParsedArgs {
  const positional: string[] = [];
  const flags: Record<string, string> = {};
  for (const arg of args) {
    if (arg.startsWith("--")) {
      const [k, ...v] = arg.slice(2).split("=");
      flags[k] = v.length > 0 ? v.join("=") : "true";
    } else {
      positional.push(arg);
    }
  }
  // The command is the first non-flag word, so `--local looking X` works as well as `looking X --local`.
  const [cmd = "help", ...pos] = positional;
  return { cmd, pos, flags };
}

/** A search term made safe for a PostgREST `or=(...)` filter. */
export function searchTerm(raw: string): string {
  return raw.replace(/[,()%*\\]/g, " ").replace(/\s+/g, " ").trim();
}

/** Same-count as the app and the board show it: the root's followers, or the siblings of a follower. */
export function sameCounts(rows: { id: string; duplicate_of: string | null }[]): Map<string, number> {
  const followers = new Map<string, number>();
  for (const r of rows) {
    if (r.duplicate_of) followers.set(r.duplicate_of, (followers.get(r.duplicate_of) ?? 0) + 1);
  }
  const out = new Map<string, number>();
  for (const r of rows) {
    out.set(r.id, followers.get(r.duplicate_of ?? r.id) ?? 0);
  }
  return out;
}
