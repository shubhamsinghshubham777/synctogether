#!/usr/bin/env node
/**
 * Agent Moderation & Anti-Piracy CLI
 *
 * Designed for Antigravity IDE and Claude Code agents to review complaints,
 * inspect room media evidence, and take administrative actions directly.
 *
 * Usage:
 *   node scripts/moderate.ts list [open|reviewing|actioned|dismissed|all]
 *   node scripts/moderate.ts inspect <report-id>
 *   node scripts/moderate.ts warn <user-id> --reason="..." [--report-id="..."]
 *   node scripts/moderate.ts ban-user <user-id> --reason="..." [--report-id="..."]
 *   node scripts/moderate.ts ban-room <room-id> --reason="..." [--report-id="..."]
 *   node scripts/moderate.ts dismiss <report-id> [--notes="..."]
 *   node scripts/moderate.ts triage <report-id> --score=90 --action=ban_room_and_warn_user --reason="..."
 */

import { readFileSync, existsSync } from "node:fs";
import { resolve } from "node:path";
import { createClient } from "../website/node_modules/@supabase/supabase-js/dist/index.mjs";

function loadEnv(): { url: string; key: string } {
  let url = process.env.SUPABASE_URL || process.env.PROD_SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL;
  let key = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.PROD_SUPABASE_SERVICE_ROLE_KEY;

  const envPaths = [
    resolve(process.cwd(), "website/.env.local"),
    resolve(process.cwd(), "website/.env"),
    resolve(process.cwd(), ".env.local"),
    resolve(process.cwd(), ".env"),
  ];

  for (const p of envPaths) {
    if (existsSync(p)) {
      const content = readFileSync(p, "utf-8");
      for (const line of content.split("\n")) {
        const trimmed = line.trim();
        if (!trimmed || trimmed.startsWith("#")) continue;
        const [k, ...v] = trimmed.split("=");
        const val = v.join("=").replace(/^["']|["']$/g, "").trim();
        if (k === "SUPABASE_URL" && !url) url = val;
        if (k === "PROD_SUPABASE_URL" && !url) url = val;
        if (k === "NEXT_PUBLIC_SUPABASE_URL" && !url) url = val;
        if (k === "SUPABASE_SERVICE_ROLE_KEY" && !key) key = val;
        if (k === "PROD_SUPABASE_SERVICE_ROLE_KEY" && !key) key = val;
      }
    }
  }

  // Fallback to local Supabase dev defaults
  url = url || "http://127.0.0.1:54321";
  key =
    key ||
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU";

  return { url, key };
}

const { url, key } = loadEnv();
const supabase = createClient(url, key, {
  auth: { persistSession: false, autoRefreshToken: false },
});

function parseArgs(args: string[]): { cmd: string; pos: string[]; flags: Record<string, string> } {
  const [cmd = "help", ...rest] = args;
  const pos: string[] = [];
  const flags: Record<string, string> = {};

  for (const arg of rest) {
    if (arg.startsWith("--")) {
      const [k, ...v] = arg.slice(2).split("=");
      flags[k] = v.length > 0 ? v.join("=") : "true";
    } else {
      pos.push(arg);
    }
  }

  return { cmd, pos, flags };
}

async function listReports(statusFilter = "open") {
  console.log(`\n🔍 Fetching reports from ${url}...`);
  let query = supabase
    .from("content_reports")
    .select(`
      id,
      reason,
      status,
      created_at,
      room_id,
      room_code,
      media_kind,
      media_title,
      media_source_url,
      message_excerpt,
      details,
      reporter_id,
      reported_user_id,
      ai_risk_score,
      ai_recommended_action,
      reported_profile:profiles!content_reports_reported_user_id_fkey(id, display_name, email, strikes_count, moderation_status)
    `)
    .order("created_at", { ascending: false });

  if (statusFilter !== "all") {
    query = query.eq("status", statusFilter);
  }

  const { data, error } = await query;
  if (error) {
    console.error("❌ Failed to list reports:", error.message);
    process.exit(1);
  }

  if (!data || data.length === 0) {
    console.log(`✨ No reports found with status '${statusFilter}'.`);
    return;
  }

  console.log(`\n📋 Found ${data.length} report(s) [Filter: ${statusFilter}]:\n`);
  for (const r of data) {
    const reported = r.reported_profile as any;
    const strikeInfo = reported ? `[Strikes: ${reported.strikes_count}/2, Status: ${reported.moderation_status}]` : "[No profile]";
    console.log(`────────────────────────────────────────────────────────────`);
    console.log(`ID:        \x1b[36m${r.id}\x1b[0m`);
    console.log(`Status:    \x1b[33m${r.status.toUpperCase()}\x1b[0m | Reason: \x1b[31m${r.reason}\x1b[0m`);
    console.log(`Target:    ${reported?.display_name || "Unknown"} (${r.reported_user_id}) ${strikeInfo}`);
    if (r.room_code || r.room_id) {
      console.log(`Room:      Code: ${r.room_code || "N/A"} (UUID: ${r.room_id || "N/A"})`);
    }
    if (r.media_title || r.media_kind) {
      console.log(`Media:     Kind: ${r.media_kind || "none"} | Title: \x1b[35m${r.media_title || "None"}\x1b[0m`);
      if (r.media_source_url) console.log(`URL:       ${r.media_source_url}`);
    }
    if (r.message_excerpt) console.log(`Chat Excerpt: "${r.message_excerpt}"`);
    if (r.details) console.log(`Reporter Note: "${r.details}"`);
    if (r.ai_risk_score !== null) {
      console.log(`AI Triage: Risk: ${r.ai_risk_score}% | Recommended: ${r.ai_recommended_action || "none"}`);
    }
  }
  console.log(`────────────────────────────────────────────────────────────\n`);
}

async function inspectReport(reportId: string) {
  if (!reportId) {
    console.error("Error: Please provide a report ID.");
    process.exit(1);
  }

  const { data: report, error } = await supabase
    .from("content_reports")
    .select(`
      *,
      reporter:profiles!content_reports_reporter_id_fkey(id, display_name, email),
      reported:profiles!content_reports_reported_user_id_fkey(id, display_name, email, strikes_count, moderation_status, warning_reason, ban_reason)
    `)
    .eq("id", reportId)
    .maybeSingle();

  if (error || !report) {
    console.error("❌ Failed to fetch report:", error?.message || "Report not found");
    process.exit(1);
  }

  let roomData = null;
  if (report.room_id) {
    const { data: rm } = await supabase.from("rooms").select("*").eq("id", report.room_id).maybeSingle();
    roomData = rm;
  }

  const { data: pastActions } = await supabase
    .from("moderation_actions")
    .select("*")
    .eq("target_user_id", report.reported_user_id)
    .order("created_at", { ascending: false });

  console.log(`\n════════════════════════════════════════════════════════════`);
  console.log(`REPORT DOSSIER: ${report.id}`);
  console.log(`════════════════════════════════════════════════════════════`);
  console.log(`Created:     ${report.created_at}`);
  console.log(`Status:      ${report.status}`);
  console.log(`Reason:      ${report.reason}`);
  console.log(`Source:      ${report.source}`);
  console.log(`\n--- REPORTED USER ---`);
  console.log(`ID:          ${report.reported?.id}`);
  console.log(`Name:        ${report.reported?.display_name}`);
  console.log(`Email:       ${report.reported?.email || "N/A"}`);
  console.log(`Strikes:     ${report.reported?.strikes_count}/2`);
  console.log(`Status:      ${report.reported?.moderation_status}`);
  if (report.reported?.warning_reason) console.log(`Last Warn:   ${report.reported?.warning_reason}`);
  if (report.reported?.ban_reason) console.log(`Ban Reason:  ${report.reported?.ban_reason}`);

  console.log(`\n--- MEDIA & ROOM EVIDENCE ---`);
  console.log(`Room Code:   ${report.room_code || roomData?.code || "N/A"}`);
  console.log(`Room Live:   ${roomData ? (roomData.ended_at ? "Ended" : "Live") : "N/A"}`);
  console.log(`Room Banned: ${roomData?.is_banned ? "YES" : "No"}`);
  console.log(`Media Kind:  ${report.media_kind || roomData?.media_kind || "N/A"}`);
  console.log(`Media Title: ${report.media_title || roomData?.media_name || "N/A"}`);
  console.log(`Media URL:   ${report.media_source_url || "N/A"}`);

  if (report.message_excerpt) {
    console.log(`\n--- CHAT MESSAGE EXCERPT ---`);
    console.log(`"${report.message_excerpt}"`);
  }

  if (report.details) {
    console.log(`\n--- REPORTER COMPLAINT DETAILS ---`);
    console.log(`"${report.details}"`);
  }

  if (pastActions && pastActions.length > 0) {
    console.log(`\n--- PAST MODERATION ACTIONS (${pastActions.length}) ---`);
    for (const a of pastActions) {
      console.log(`• [${a.created_at}] ${a.action_type.toUpperCase()} by ${a.actioned_by}: ${a.reason} (${a.notes || "no notes"})`);
    }
  }
  console.log(`════════════════════════════════════════════════════════════\n`);
}

async function warnUser(userId: string, reason: string, reportId?: string, notes?: string) {
  console.log(`⚠️ Issuing Strike 1 warning to user ${userId}...`);
  const { error } = await supabase.rpc("admin_warn_user", {
    p_user_id: userId,
    p_reason: reason,
    p_report_id: reportId || null,
    p_notes: notes || "Issued via Agent Moderation CLI",
    p_ai_assisted: true,
  });

  if (error) {
    console.error("❌ Failed to warn user:", error.message);
    process.exit(1);
  }
  console.log("✅ Warning recorded successfully. User has received Strike 1 (or escalated to ban if Strike 2).");
}

async function banUser(userId: string, reason: string, reportId?: string, notes?: string) {
  console.log(`🚫 Suspending account ${userId} indefinitely...`);
  const { error } = await supabase.rpc("admin_ban_user", {
    p_user_id: userId,
    p_reason: reason,
    p_report_id: reportId || null,
    p_notes: notes || "Issued via Agent Moderation CLI",
    p_ai_assisted: true,
  });

  if (error) {
    console.error("❌ Failed to ban user:", error.message);
    process.exit(1);
  }
  console.log("✅ User account banned platform-wide. All active rooms terminated.");
}

async function banRoom(roomId: string, reason: string, reportId?: string, notes?: string) {
  console.log(`🛑 Terminating and banning room ${roomId}...`);
  const { error } = await supabase.rpc("admin_ban_room", {
    p_room_id: roomId,
    p_reason: reason,
    p_report_id: reportId || null,
    p_notes: notes || "Issued via Agent Moderation CLI",
    p_ai_assisted: true,
  });

  if (error) {
    console.error("❌ Failed to ban room:", error.message);
    process.exit(1);
  }
  console.log("✅ Room banned and terminated. Media queued for R2 deletion. Members evicted.");
}

async function dismissReport(reportId: string, notes?: string) {
  console.log(`⚪ Dismissing report ${reportId}...`);
  const { error } = await supabase.rpc("admin_dismiss_report", {
    p_report_id: reportId,
    p_notes: notes || "Dismissed via Agent Moderation CLI",
  });

  if (error) {
    console.error("❌ Failed to dismiss report:", error.message);
    process.exit(1);
  }
  console.log("✅ Report dismissed.");
}

async function triageReport(reportId: string, score: number, action: string, reasoning: string) {
  console.log(`🤖 Recording AI triage for report ${reportId}...`);
  const { error } = await supabase.rpc("admin_record_ai_triage", {
    p_report_id: reportId,
    p_risk_score: score,
    p_recommended_action: action,
    p_reasoning: reasoning,
  });

  if (error) {
    console.error("❌ Failed to record triage:", error.message);
    process.exit(1);
  }
  console.log("✅ AI Triage recorded.");
}

async function main() {
  const { cmd, pos, flags } = parseArgs(process.argv.slice(2));

  switch (cmd) {
    case "list":
      await listReports(pos[0] || "open");
      break;
    case "inspect":
      await inspectReport(pos[0]);
      break;
    case "warn":
      await warnUser(pos[0], flags.reason || "Copyright/terms violation warning", flags["report-id"], flags.notes);
      break;
    case "ban-user":
      await banUser(pos[0], flags.reason || "Account suspended for copyright violation", flags["report-id"], flags.notes);
      break;
    case "ban-room":
      await banRoom(pos[0], flags.reason || "Room terminated for copyright violation", flags["report-id"], flags.notes);
      break;
    case "dismiss":
      await dismissReport(pos[0], flags.notes);
      break;
    case "triage":
      await triageReport(pos[0], Number(flags.score || 80), flags.action || "warn_user", flags.reason || "Detected potential piracy");
      break;
    default:
      console.log(`
SyncTogether Moderation CLI (for Antigravity & Claude Code)

Commands:
  node scripts/moderate.ts list [status]     List reports (open, reviewing, actioned, dismissed, all)
  node scripts/moderate.ts inspect <id>      View full evidence dossier for a report
  node scripts/moderate.ts warn <user-id> --reason="..." [--report-id="..."]
  node scripts/moderate.ts ban-user <user-id> --reason="..." [--report-id="..."]
  node scripts/moderate.ts ban-room <room-id> --reason="..." [--report-id="..."]
  node scripts/moderate.ts dismiss <id> [--notes="..."]
  node scripts/moderate.ts triage <id> --score=90 --action=ban_room_and_warn_user --reason="..."
      `);
  }
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
