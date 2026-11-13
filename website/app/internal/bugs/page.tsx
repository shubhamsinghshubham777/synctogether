import type { Metadata } from "next";
import { headers } from "next/headers";
import { notFound } from "next/navigation";
import Link from "next/link";
import { Activity, ArrowLeft, Bug, Shield } from "lucide-react";
import { isAuthorizedLocalAccess } from "@/lib/admin-guard";
import { createAdminClient } from "@/lib/supabase/admin";
import { toBugRow } from "@/lib/bug_board_logic";
import { BugBoardClient } from "./BugBoardClient";
import { loadReleaseOptions } from "./releases";

export const metadata: Metadata = {
  title: "Bug Board",
  description: "Internal bug report board",
  robots: { index: false, follow: false },
};

export const dynamic = "force-dynamic";

const COLUMNS =
  "id, code, category, note, note_appendix, status, fixed_in, reason, duplicate_of, public_title, created_at, sentry_event_id, notify_when_fixed, context";

export default async function BugBoardPage() {
  const reqHeaders = await headers();
  if (!isAuthorizedLocalAccess({ headers: reqHeaders })) {
    notFound();
  }

  const { data, error } = await createAdminClient()
    .from("bug_reports")
    .select(COLUMNS)
    .order("created_at", { ascending: false })
    .limit(500);

  const releases = await loadReleaseOptions();
  const rows = (data ?? []).map((r) => toBugRow(r as Record<string, unknown>));

  return (
    <div className="min-h-screen bg-booth text-screen p-4 sm:p-8 space-y-6 max-w-[1440px] mx-auto">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 border-b border-rail pb-4">
        <div className="flex items-center gap-3">
          <div className="p-2.5 rounded-md bg-seat border border-rail text-screen">
            <Bug className="w-6 h-6" aria-hidden="true" />
          </div>
          <div>
            <h1 className="text-xl font-bold tracking-tight text-screen">Bug Board</h1>
            <p className="text-xs text-gray-400 font-mono">
              Moving a card tells the user &bull; closing needs a reason or an original
            </p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          <Link
            href="/internal/moderation"
            className="px-3 py-1.5 rounded-md bg-aisle hover:bg-aisle/80 text-xs font-mono text-gray-300 hover:text-white border border-rail flex items-center gap-1.5 transition-colors"
          >
            <Shield className="w-3.5 h-3.5 text-beam-300" aria-hidden="true" />
            Moderation
          </Link>
          <Link
            href="/internal/metrics"
            className="px-3 py-1.5 rounded-md bg-aisle hover:bg-aisle/80 text-xs font-mono text-gray-300 hover:text-white border border-rail flex items-center gap-1.5 transition-colors"
          >
            <Activity className="w-3.5 h-3.5 text-beam-300" aria-hidden="true" />
            Metrics
          </Link>
          <Link
            href="/"
            className="px-3 py-1.5 rounded-md bg-aisle hover:bg-aisle/80 text-xs font-mono text-gray-400 hover:text-white border border-rail flex items-center gap-1.5 transition-colors"
          >
            <ArrowLeft className="w-3.5 h-3.5" aria-hidden="true" />
            Back to Site
          </Link>
        </div>
      </div>

      {error ? (
        <div className="rounded-md border border-signal bg-seat p-5 text-sm text-gray-300">
          Couldn&apos;t load the reports. Is the bug board migration applied to this database?
          <div className="mt-2 font-mono text-xs text-gray-500">{error.message}</div>
        </div>
      ) : (
        <BugBoardClient rows={rows} releases={releases} />
      )}
    </div>
  );
}
