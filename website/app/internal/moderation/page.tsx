import type { Metadata } from "next";
import { headers } from "next/headers";
import { notFound } from "next/navigation";
import Link from "next/link";
import { isAuthorizedLocalAccess } from "@/lib/admin-guard";
import { createAdminClient } from "@/lib/supabase/admin";
import { evaluateReportHeuristics } from "@/lib/moderation-heuristics";
import { GlassPanel } from "@/components/GlassPanel";
import { ModerationTriageClient, type ModerationReportItem } from "./ModerationTriageClient";
import { ShieldAlert, Activity, ArrowLeft, Shield } from "lucide-react";

export const metadata: Metadata = {
  title: "Moderation Queue | SyncTogether",
  description: "Internal Anti-Piracy & Content Moderation Dashboard",
  robots: { index: false, follow: false },
};

export const dynamic = "force-dynamic";

export default async function ModerationPage() {
  const reqHeaders = await headers();
  if (!isAuthorizedLocalAccess({ headers: reqHeaders })) {
    notFound();
  }

  const supabase = createAdminClient();

  // Fetch reports with joined profiles
  const { data: rawReports, error: reportErr } = await supabase
    .from("content_reports")
    .select(`
      id,
      reason,
      status,
      source,
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
      reporter:profiles!content_reports_reporter_id_fkey(id, display_name, email),
      reported:profiles!content_reports_reported_user_id_fkey(id, display_name, email, profile_moderation(strikes_count, moderation_status, warning_reason, ban_reason))
    `)
    .order("created_at", { ascending: false })
    .limit(100);

  // Fetch room details for distinct room ids
  const roomIds = Array.from(new Set((rawReports || []).map((r) => r.room_id).filter(Boolean)));
  const { data: roomRows } = roomIds.length > 0
    ? await supabase.from("rooms").select("id, code, is_banned, ended_at").in("id", roomIds)
    : { data: [] };

  const roomsById = new Map((roomRows || []).map((rm) => [rm.id, rm]));

  // Count metrics
  const { count: openCount } = await supabase
    .from("content_reports")
    .select("*", { count: "exact", head: true })
    .eq("status", "open");

  const { count: copyrightCount } = await supabase
    .from("content_reports")
    .select("*", { count: "exact", head: true })
    .eq("reason", "copyright");

  const { count: bannedUsersCount } = await supabase
    .from("profile_moderation")
    .select("*", { count: "exact", head: true })
    .eq("moderation_status", "banned");

  const { count: bannedRoomsCount } = await supabase
    .from("rooms")
    .select("*", { count: "exact", head: true })
    .eq("is_banned", true);

  // Transform reports with heuristics
  const reports: ModerationReportItem[] = (rawReports || []).map((r) => {
    const room = r.room_id ? roomsById.get(r.room_id) : null;
    const reported = r.reported as any;
    const reportedMod = (Array.isArray(reported?.profile_moderation)
      ? reported.profile_moderation[0]
      : reported?.profile_moderation) as any;
    const reporter = r.reporter as any;

    const heuristics = evaluateReportHeuristics({
      reason: r.reason,
      mediaTitle: r.media_title,
      mediaSourceUrl: r.media_source_url,
      mediaKind: r.media_kind,
      messageExcerpt: r.message_excerpt,
      details: r.details,
      userStrikes: reportedMod?.strikes_count || 0,
      userModerationStatus: reportedMod?.moderation_status || "clean",
    });

    return {
      id: r.id,
      reason: r.reason,
      status: r.status,
      source: r.source,
      createdAt: r.created_at,
      room: {
        id: r.room_id,
        code: r.room_code || room?.code,
        isBanned: room?.is_banned ?? false,
        endedAt: room?.ended_at,
      },
      // The client component reads camelCase; the query returns snake_case.
      reporter: reporter
        ? { id: reporter.id, displayName: reporter.display_name, email: reporter.email }
        : null,
      reported: reported
        ? {
            id: reported.id,
            displayName: reported.display_name,
            email: reported.email,
            strikesCount: reportedMod?.strikes_count ?? 0,
            moderationStatus: reportedMod?.moderation_status ?? "clean",
            warningReason: reportedMod?.warning_reason ?? null,
            banReason: reportedMod?.ban_reason ?? null,
          }
        : null,
      media: {
        kind: r.media_kind,
        title: r.media_title,
        url: r.media_source_url,
      },
      messageExcerpt: r.message_excerpt,
      details: r.details,
      heuristics,
    };
  });

  return (
    <div className="min-h-screen bg-booth text-screen font-[family-name:var(--font-inter)] p-4 sm:p-8 space-y-8 max-w-7xl mx-auto">
      {/* Top Bar */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 border-b border-rail pb-4">
        <div className="flex items-center gap-3">
          <div className="p-2.5 rounded-xl bg-purple-600/20 border border-purple-500/30 text-purple-400">
            <ShieldAlert className="w-6 h-6" />
          </div>
          <div>
            <h1 className="text-xl font-bold font-[family-name:var(--font-space-grotesk)] text-screen tracking-tight">
              Anti-Piracy &amp; Moderation Triage
            </h1>
            <p className="text-xs text-gray-400 font-mono">
              Zero-Key Heuristics &bull; Agent-Assisted Review Queue
            </p>
          </div>
        </div>

        <div className="flex items-center gap-2">
          <Link
            href="/internal/metrics"
            className="px-3 py-1.5 rounded-lg bg-aisle hover:bg-aisle/80 text-xs font-mono text-gray-300 hover:text-white border border-rail flex items-center gap-1.5 transition-colors"
          >
            <Activity className="w-3.5 h-3.5 text-beam-300" />
            Internal Metrics
          </Link>
          <Link
            href="/"
            className="px-3 py-1.5 rounded-lg bg-aisle hover:bg-aisle/80 text-xs font-mono text-gray-400 hover:text-white border border-rail flex items-center gap-1.5 transition-colors"
          >
            <ArrowLeft className="w-3.5 h-3.5" />
            Back to Site
          </Link>
        </div>
      </div>

      {/* KPI Cards */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
        <div className="p-4 rounded-xl bg-aisle/60 border border-rail space-y-1">
          <div className="text-[11px] font-mono uppercase tracking-wider text-gray-400">Open Reports</div>
          <div className="text-2xl font-bold font-mono text-amber-300">{openCount ?? 0}</div>
          <p className="text-[10px] text-gray-500">Awaiting reviewer triage</p>
        </div>

        <div className="p-4 rounded-xl bg-aisle/60 border border-rail space-y-1">
          <div className="text-[11px] font-mono uppercase tracking-wider text-gray-400">Copyright Flags</div>
          <div className="text-2xl font-bold font-mono text-purple-300">{copyrightCount ?? 0}</div>
          <p className="text-[10px] text-gray-500">Reported under piracy policy</p>
        </div>

        <div className="p-4 rounded-xl bg-aisle/60 border border-rail space-y-1">
          <div className="text-[11px] font-mono uppercase tracking-wider text-gray-400">Terminated Rooms</div>
          <div className="text-2xl font-bold font-mono text-screen">{bannedRoomsCount ?? 0}</div>
          <p className="text-[10px] text-gray-500">Rooms banned by admin</p>
        </div>

        <div className="p-4 rounded-xl bg-aisle/60 border border-rail space-y-1">
          <div className="text-[11px] font-mono uppercase tracking-wider text-gray-400">Suspended Users</div>
          <div className="text-2xl font-bold font-mono text-red-400">{bannedUsersCount ?? 0}</div>
          <p className="text-[10px] text-gray-500">Accounts banned (Strike 2)</p>
        </div>
      </div>

      {/* Main Reviewer Triage Panel */}
      <GlassPanel className="p-6 space-y-6">
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2 border-b border-rail/60 pb-3">
          <div className="flex items-center gap-2">
            <Shield className="w-5 h-5 text-purple-400" />
            <h2 className="text-base font-bold text-screen font-[family-name:var(--font-space-grotesk)]">
              Complaint Review &amp; Enforcement Queue
            </h2>
          </div>
          <div className="text-xs font-mono text-gray-400">
            Strike 1 = Warning Gate &bull; Strike 2 = Account Ban
          </div>
        </div>

        <ModerationTriageClient reports={reports} />
      </GlassPanel>
    </div>
  );
}
