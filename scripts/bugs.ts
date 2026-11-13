#!/usr/bin/env node
/**
 * Bug board CLI
 *
 * The command-line side of the internal bug board (website/app/internal/bugs):
 * the same admin RPC, for agents and for the release skill. What a ticket's
 * status says is shown to users in "Your reports", so every state change that
 * is not routine asks for --confirm and prints a plan first.
 *
 * Usage:
 *   node scripts/bugs.ts list [received|looking|fixed|wontfix|duplicate|open|all]
 *   node scripts/bugs.ts show <code>
 *   node scripts/bugs.ts find <text>
 *   node scripts/bugs.ts looking <code...>
 *   node scripts/bugs.ts fix <code...> --version=X.Y.Z [--confirm]
 *   node scripts/bugs.ts wontfix <code> --reason="..." [--confirm]
 *   node scripts/bugs.ts duplicate <code> --of=<code> [--confirm]
 *   node scripts/bugs.ts reopen <code> [--confirm]
 *   node scripts/bugs.ts close-from-commits --version=X.Y.Z [--since=<ref>] [--until=<ref>] [--force] [--confirm]
 *
 * Add --local to talk to the local Supabase stack (ignores .env files). Without
 * it the target comes from the environment like scripts/moderate.ts, and the
 * target is printed before anything is written.
 *
 * Reports are user data. Notes, contexts and screenshots shown here are for
 * fixing the bug: never paste them into commits, issues or logs.
 */

import { execFileSync } from "node:child_process";
import { readFileSync, existsSync } from "node:fs";
import { resolve } from "node:path";
import { createClient } from "../website/node_modules/@supabase/supabase-js/dist/index.mjs";
import {
  compareVersions,
  isBugCode,
  normalizeCode,
  normalizeVersion,
  parseArgs,
  parseFixesTrailers,
  pickSince,
  planClose,
  reasonError,
  renderPlan,
  sameCounts,
  searchTerm,
} from "./lib/bugs_logic.ts";
import type { BugRow, BugStatus } from "./lib/bugs_logic.ts";

const LOCAL_URL = "http://127.0.0.1:54321";
// The well-known Supabase local-dev service key (also embedded in moderate.ts).
const LOCAL_KEY =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU";

function loadEnv(local: boolean): { url: string; key: string } {
  if (local) {
    return { url: process.env.LOCAL_SUPABASE_URL || LOCAL_URL, key: process.env.LOCAL_SUPABASE_SERVICE_ROLE_KEY || LOCAL_KEY };
  }
  let url = process.env.SUPABASE_URL || process.env.PROD_SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL;
  let key = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.PROD_SUPABASE_SERVICE_ROLE_KEY;

  const envPaths = [
    resolve(process.cwd(), "website/.env.local"),
    resolve(process.cwd(), "website/.env"),
    resolve(process.cwd(), ".env.local"),
    resolve(process.cwd(), ".env"),
  ];
  for (const p of envPaths) {
    if (!existsSync(p)) continue;
    for (const line of readFileSync(p, "utf-8").split("\n")) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith("#")) continue;
      const [k, ...v] = trimmed.split("=");
      const val = v.join("=").replace(/^["']|["']$/g, "").trim();
      if ((k === "SUPABASE_URL" || k === "PROD_SUPABASE_URL" || k === "NEXT_PUBLIC_SUPABASE_URL") && !url) url = val;
      if ((k === "SUPABASE_SERVICE_ROLE_KEY" || k === "PROD_SUPABASE_SERVICE_ROLE_KEY") && !key) key = val;
    }
  }
  return { url: url || LOCAL_URL, key: key || LOCAL_KEY };
}

const { cmd, pos, flags } = parseArgs(process.argv.slice(2));
const { url, key } = loadEnv(flags.local === "true");
const isLocalTarget = /^https?:\/\/(127\.0\.0\.1|localhost)(:|\/|$)/.test(url);
const supabase = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });

function fail(message: string): never {
  console.error(`Error: ${message}`);
  process.exit(1);
}

function target(): string {
  return isLocalTarget ? `LOCAL (${url})` : `PRODUCTION (${new URL(url).host})`;
}

/** Said before any write, so nobody is surprised which board a command touched. */
function announceWrite(): void {
  console.log(`Target: ${target()}`);
}

function clip(text: string | null | undefined, n: number): string {
  const t = (text ?? "").replace(/\s+/g, " ").trim();
  return t.length > n ? `${t.slice(0, n - 1)}…` : t;
}

function codesFrom(list: string[]): string[] {
  if (list.length === 0) fail("Give at least one ticket code, like BUG-7K2M.");
  const out = list.map(normalizeCode);
  for (const c of out) if (!isBugCode(c)) fail(`"${c}" is not a ticket code (expected BUG-XXXX).`);
  return out;
}

const FRIENDLY: Record<string, string> = {
  reason_required: "A reason of at least 20 characters is required.",
  fixed_in_required: "A version is required.",
  fixed_in_invalid: "The version must be plain X.Y.Z.",
  fixed_before_report: "That version is older than the build the report came from.",
  original_required: "The original ticket is required.",
  unknown_original: "The original ticket does not exist.",
  cannot_duplicate_self: "A ticket cannot follow itself.",
  not_found: "No such ticket.",
  invalid_status: "Not a valid status.",
};

async function setStatus(
  code: string,
  status: BugStatus,
  extra: { fixedIn?: string; reason?: string; original?: string } = {},
): Promise<void> {
  const { error } = await supabase.rpc("admin_set_bug_status", {
    p_code: code,
    p_status: status,
    p_fixed_in: extra.fixedIn ?? null,
    p_reason: extra.reason ?? null,
    p_duplicate_of_code: extra.original ?? null,
    p_public_title: null,
  });
  if (error) {
    const hit = Object.keys(FRIENDLY).find((k) => error.message.includes(k));
    fail(`${code}: ${hit ? FRIENDLY[hit] : error.message}`);
  }
}

interface Row {
  id: string;
  code: string;
  category: string | null;
  note: string | null;
  context: any;
  sentry_event_id: string | null;
  status: BugStatus;
  fixed_in: string | null;
  reason: string | null;
  duplicate_of: string | null;
  public_title: string | null;
  created_at: string;
  closed_at: string | null;
  user_id: string;
}

async function fetchAll(): Promise<Row[]> {
  const { data, error } = await supabase
    .from("bug_reports")
    .select("id, code, category, note, context, sentry_event_id, status, fixed_in, reason, duplicate_of, public_title, created_at, closed_at, user_id")
    .order("created_at", { ascending: false })
    .limit(2000);
  if (error) fail(`Could not read the board: ${error.message}`);
  return (data ?? []) as Row[];
}

function versionOf(context: any): string {
  return context?.app?.version ?? context?.app_version ?? "?";
}

function colorStatus(s: string): string {
  const c: Record<string, string> = { received: "37", looking: "33", fixed: "32", wontfix: "90", duplicate: "90" };
  return `\x1b[${c[s] ?? "0"}m${s.toUpperCase()}\x1b[0m`;
}

async function list(filter = "open"): Promise<void> {
  const rows = await fetchAll();
  const same = sameCounts(rows);
  const byId = new Map(rows.map((r) => [r.id, r]));
  const shown = rows.filter((r) =>
    filter === "all" ? true : filter === "open" ? r.status === "received" || r.status === "looking" : r.status === filter,
  );
  console.log(`\nBoard: ${target()} · ${shown.length} ticket(s) [${filter}]\n`);
  if (shown.length === 0) {
    console.log("Nothing here.\n");
    return;
  }
  for (const r of shown) {
    const original = r.duplicate_of ? byId.get(r.duplicate_of)?.code : null;
    const tail = r.status === "fixed" ? ` from ${r.fixed_in}` : original ? ` of ${original}` : "";
    const n = same.get(r.id) ?? 0;
    console.log(
      `${r.code}  ${colorStatus(r.status)}${tail}  ${r.category ?? "-"}  v${versionOf(r.context)}  ${n > 0 ? `${n} same  ` : ""}${r.created_at.slice(0, 10)}`,
    );
    console.log(`   ${clip(r.note, 110) || "(no note)"}`);
  }
  console.log("");
}

async function show(code: string): Promise<void> {
  const rows = await fetchAll();
  const r = rows.find((x) => x.code === code);
  if (!r) fail(`No ticket ${code} on ${target()}.`);
  const followers = rows.filter((x) => x.duplicate_of === r.id);
  const original = r.duplicate_of ? rows.find((x) => x.id === r.duplicate_of) : null;
  console.log(`\n══ ${r.code} · ${colorStatus(r.status)} · ${target()} ══`);
  console.log(`Category:   ${r.category ?? "-"}`);
  console.log(`App:        ${versionOf(r.context)}`);
  console.log(`Sent:       ${r.created_at}${r.closed_at ? ` · closed ${r.closed_at}` : ""}`);
  console.log(`Account:    ${r.user_id}`);
  console.log(`Sentry:     ${r.sentry_event_id ?? "-"}`);
  if (r.fixed_in) console.log(`Fixed from: ${r.fixed_in}`);
  if (r.reason) console.log(`Reason:     ${r.reason}`);
  if (original) console.log(`Follows:    ${original.code} (${original.status})`);
  console.log(`\nNote:\n${r.note ?? "(none)"}\n`);
  console.log(`Context:\n${JSON.stringify(r.context, null, 2)}\n`);
  if (followers.length > 0) {
    console.log(`Followers (${followers.length}): ${followers.map((f) => f.code).join(", ")}\n`);
  }
}

async function find(text: string): Promise<void> {
  const term = searchTerm(text);
  if (term.length < 3) fail("Search for at least 3 characters.");
  const { data, error } = await supabase
    .from("bug_reports")
    .select("code, category, note, public_title, status, fixed_in, context")
    .or(`note.ilike.%${term}%,public_title.ilike.%${term}%`)
    .order("created_at", { ascending: false })
    .limit(25);
  if (error) fail(`Search failed: ${error.message}`);
  console.log(`\nBoard: ${target()} · ${data?.length ?? 0} match(es) for "${term}"\n`);
  for (const r of data ?? []) {
    console.log(`${r.code}  ${colorStatus(r.status)}${r.fixed_in ? ` from ${r.fixed_in}` : ""}  ${r.category ?? "-"}  v${versionOf(r.context)}`);
    console.log(`   ${clip(r.public_title || r.note, 110)}`);
  }
  console.log("");
}

async function looking(codes: string[]): Promise<void> {
  announceWrite();
  const rows = await fetchAll();
  // Check every code before changing any, so a typo never leaves half a batch applied.
  for (const code of codes) {
    const r = rows.find((x) => x.code === code);
    if (!r) fail(`No ticket ${code} on ${target()}. Nothing was changed.`);
    if (r.status !== "received" && r.status !== "looking") {
      fail(`${code} is ${r.status}. "looking" only starts work on a received ticket; use "reopen" to bring a closed one back. Nothing was changed.`);
    }
  }
  for (const code of codes) {
    if (rows.find((x) => x.code === code)?.status === "looking") {
      console.log(`${code}: already LOOKING INTO IT`);
    } else {
      await setStatus(code, "looking");
      console.log(`${code}: received -> LOOKING INTO IT (users see this now)`);
    }
  }
}

function needConfirm(plan: string): boolean {
  announceWrite();
  console.log(plan);
  if (flags.confirm === "true") return true;
  console.log("\nDry run. Re-run with --confirm to apply.");
  return false;
}

async function fix(codes: string[]): Promise<void> {
  const version = normalizeVersion(flags.version ?? "");
  if (!version) fail("--version=X.Y.Z is required: the first version that contains the fix.");
  const rows = await fetchAll();
  const map = new Map<string, BugRow>(rows.map((r) => [r.code, { code: r.code, status: r.status, fixed_in: r.fixed_in }]));
  const lines = planClose({ codes, rows: map, version, force: flags.force === "true" });
  if (!needConfirm(renderPlan(`Mark fixed from ${version}:`, lines))) return;
  for (const l of lines.filter((x) => x.action === "fix")) {
    await setStatus(l.code, "fixed", { fixedIn: version });
    console.log(`${l.code}: FIXED from ${version}`);
  }
}

async function wontfix(code: string): Promise<void> {
  const reason = (flags.reason ?? "").trim();
  const bad = reasonError(reason);
  if (bad) fail(bad);
  const plan = [
    `Close ${code} as won't fix. The user reads this verbatim:`,
    "",
    `  "${reason}"`,
    "",
    "Calm tone, no blame; it must say why and what they can do next.",
  ].join("\n");
  if (!needConfirm(plan)) return;
  await setStatus(code, "wontfix", { reason });
  console.log(`${code}: closed (won't fix); duplicates copy the reason`);
}

async function duplicate(code: string): Promise<void> {
  const of = normalizeCode(flags.of ?? "");
  if (!isBugCode(of)) fail("--of=BUG-XXXX is required: the original ticket.");
  if (of === code) fail("A ticket cannot follow itself.");
  const plan = `Mark ${code} as a duplicate of ${of}. The user will see "Same as ${of}" with its live status (never its note).`;
  if (!needConfirm(plan)) return;
  await setStatus(code, "duplicate", { original: of });
  console.log(`${code}: now follows ${of}`);
}

async function reopen(code: string): Promise<void> {
  const plan = `Reopen ${code}: back to LOOKING INTO IT. This clears its fixed version, reason and original link, and its followers fall back to plain duplicates.`;
  if (!needConfirm(plan)) return;
  await setStatus(code, "looking");
  console.log(`${code}: reopened -> LOOKING INTO IT`);
}

function git(args: string[]): string {
  return execFileSync("git", args, { encoding: "utf-8", maxBuffer: 64 * 1024 * 1024 });
}

async function closeFromCommits(): Promise<void> {
  const version = normalizeVersion(flags.version ?? "");
  if (!version) fail("--version=X.Y.Z is required: the version that was just released.");
  const rows = await fetchAll();

  let maxFixed: string | null = null;
  for (const r of rows) {
    if (r.status === "fixed" && r.fixed_in && (!maxFixed || (compareVersions(r.fixed_in, maxFixed) ?? 0) > 0)) maxFixed = r.fixed_in;
  }
  const tags = git(["tag", "--list", "v*"]).split("\n").filter(Boolean);
  const since = flags.since ?? pickSince({ tags, targetVersion: version, maxFixedVersion: maxFixed });
  // The release's own tag when it exists, so a commit made after the release is not swept in.
  const until = flags.until ?? (tags.includes(`v${version}`) ? `v${version}` : "HEAD");
  if (!since) console.log("No earlier release tag found: scanning the whole history.");

  const range = since ? `${since}..${until}` : until;
  const log = git(["log", range, "--format=%B%x00"]);
  const codes = parseFixesTrailers(log);
  console.log(`Commits ${range}: ${codes.length} ticket(s) named by Fixes-Bug trailers.`);
  if (codes.length === 0) return;

  const map = new Map<string, BugRow>();
  const byId = new Map(rows.map((r) => [r.id, r]));
  for (const r of rows) {
    map.set(r.code, {
      code: r.code,
      status: r.status,
      fixed_in: r.fixed_in,
      duplicate_of_code: r.duplicate_of ? byId.get(r.duplicate_of)?.code : null,
    });
  }
  const lines = planClose({ codes, rows: map, version, force: flags.force === "true" });
  if (!needConfirm(renderPlan(`Mark fixed from ${version} (${range}):`, lines))) return;
  for (const l of lines.filter((x) => x.action === "fix")) {
    await setStatus(l.code, "fixed", { fixedIn: version });
    console.log(`${l.code}: FIXED from ${version}`);
  }
  const done = lines.filter((x) => x.action === "fix").map((x) => x.code);
  console.log(`\nClosed ${done.length}: ${done.join(", ") || "none"}`);
}

function help(): void {
  console.log(
    [
      "Bug board CLI. Add --local for the local stack.",
      "  list [received|looking|fixed|wontfix|duplicate|open|all]",
      "  show <code>            find <text>",
      "  looking <code...>      (runs immediately)",
      "  fix <code...> --version=X.Y.Z [--confirm]",
      "  wontfix <code> --reason=\"...\" [--confirm]",
      "  duplicate <code> --of=<code> [--confirm]",
      "  reopen <code> [--confirm]",
      "  close-from-commits --version=X.Y.Z [--since=ref] [--until=ref] [--force] [--confirm]",
    ].join("\n"),
  );
}

switch (cmd) {
  case "list":
    await list(pos[0]);
    break;
  case "show":
    await show(codesFrom(pos.slice(0, 1))[0]);
    break;
  case "find":
    await find(pos.join(" "));
    break;
  case "looking":
    await looking(codesFrom(pos));
    break;
  case "fix":
    await fix(codesFrom(pos));
    break;
  case "wontfix":
    await wontfix(codesFrom(pos.slice(0, 1))[0]);
    break;
  case "duplicate":
    await duplicate(codesFrom(pos.slice(0, 1))[0]);
    break;
  case "reopen":
    await reopen(codesFrom(pos.slice(0, 1))[0]);
    break;
  case "close-from-commits":
    await closeFromCommits();
    break;
  default:
    help();
}
