import { headers } from "next/headers";
import { notFound } from "next/navigation";
import Link from "next/link";
import { isAuthorizedLocalAccess } from "@/lib/admin-guard";
import { GlassPanel } from "@/components/GlassPanel";
import { Activity, ArrowRight, ShieldAlert } from "lucide-react";

export const dynamic = "force-dynamic";

export default async function AdminHubPage() {
  const reqHeaders = await headers();
  if (!isAuthorizedLocalAccess({ headers: reqHeaders })) {
    notFound();
  }

  return (
    <div className="min-h-screen bg-booth text-screen font-[family-name:var(--font-inter)] p-6 sm:p-12 flex items-center justify-center">
      <div className="w-full max-w-xl space-y-6">
        <div className="text-center space-y-2">
          <h1 className="text-2xl font-bold font-[family-name:var(--font-space-grotesk)] text-screen tracking-tight">
            SyncTogether Operator Booth
          </h1>
          <p className="text-xs text-gray-400 font-mono">
            Local Administrative &amp; Moderation Control Center
          </p>
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <Link href="/internal/moderation" className="group">
            <GlassPanel className="p-6 h-full space-y-4 hover:border-purple-500/60 transition-all">
              <div className="p-3 rounded-xl bg-purple-600/20 border border-purple-500/30 text-purple-400 w-fit">
                <ShieldAlert className="w-6 h-6" />
              </div>
              <div className="space-y-1">
                <div className="text-base font-bold text-gray-100 group-hover:text-purple-300 transition-colors flex items-center justify-between">
                  Moderation
                  <ArrowRight className="w-4 h-4 opacity-0 group-hover:opacity-100 -translate-x-1 group-hover:translate-x-0 transition-all" />
                </div>
                <p className="text-xs text-gray-400 leading-snug">
                  Review reported rooms, examine media evidence, issue strikes, and ban pirated rooms.
                </p>
              </div>
            </GlassPanel>
          </Link>

          <Link href="/internal/metrics" className="group">
            <GlassPanel className="p-6 h-full space-y-4 hover:border-blue-500/60 transition-all">
              <div className="p-3 rounded-xl bg-blue-600/20 border border-blue-500/30 text-blue-400 w-fit">
                <Activity className="w-6 h-6" />
              </div>
              <div className="space-y-1">
                <div className="text-base font-bold text-gray-100 group-hover:text-blue-300 transition-colors flex items-center justify-between">
                  Metrics
                  <ArrowRight className="w-4 h-4 opacity-0 group-hover:opacity-100 -translate-x-1 group-hover:translate-x-0 transition-all" />
                </div>
                <p className="text-xs text-gray-400 leading-snug">
                  Live production telemetry, MRR, subscriptions, DAU/MAU, and room volume.
                </p>
              </div>
            </GlassPanel>
          </Link>
        </div>
      </div>
    </div>
  );
}
