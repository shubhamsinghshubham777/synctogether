import type { Metadata } from "next";
import { headers } from "next/headers";
import { notFound } from "next/navigation";
import { isAuthorizedLocalAccess } from "@/lib/admin-guard";
import {
  getDashboardMetrics,
  type DashboardMetrics,
  type ServiceQuotaMetric,
} from "@/lib/metrics";
import { ProductionCredentialsError } from "@/lib/supabase/admin";
import { GlassPanel } from "@/components/GlassPanel";
import { InternalMetricsControls } from "./InternalMetricsControls";
import {
  Users,
  Download,
  Eye,
  Activity,
  DollarSign,
  Tv,
  Crown,
  Share2,
  Calendar,
  Layers,
  ArrowRight,
  TrendingUp,
  Clock,
  Sparkles,
  Server,
  Compass,
  Database,
  HardDrive,
  Video,
  ExternalLink,
  ShieldAlert,
  RefreshCw,
} from "lucide-react";

export const metadata: Metadata = {
  title: "Internal Telemetry & Business Metrics | SyncTogether",
  description: "Internal local-only metrics dashboard for SyncTogether",
  robots: {
    index: false,
    follow: false,
  },
};

export const dynamic = "force-dynamic";

function ProductionCredentialsGate({
  error,
}: {
  error: { code: string; message: string; resolution: string };
}) {
  return (
    <div className="relative min-h-[85vh] flex items-center justify-center p-4 sm:p-6 lg:p-8">
      <div className="glow-blob-purple top-1/4 left-1/2 -translate-x-1/2 opacity-30" />
      <GlassPanel glow="purple" className="max-w-2xl w-full p-8 md:p-10 border-red-500/30 space-y-6">
        <div className="flex items-start gap-4">
          <div className="p-3 rounded-2xl bg-red-500/10 text-red-400 border border-red-500/20 shrink-0">
            <ShieldAlert className="w-8 h-8" />
          </div>
          <div className="space-y-1">
            <div className="inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full bg-red-500/10 border border-red-500/20 text-xs font-mono text-red-400 font-semibold">
              <span>DATA INTEGRITY GUARD • ACCESS DENIED</span>
            </div>
            <h1 className="text-2xl sm:text-3xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
              Production Credentials Required
            </h1>
            <p className="text-xs text-gray-400">
              SyncTogether Mission Control strictly operates on live production data.
            </p>
          </div>
        </div>

        <div className="space-y-3 text-sm text-gray-300 leading-relaxed">
          <p>
            This admin telemetry dashboard is strictly forbidden from displaying localhost or seed data (<code className="text-purple-300 bg-purple-950/60 px-1.5 py-0.5 rounded font-mono text-xs">127.0.0.1:54321</code>). Operating on test/seed data skews business metrics and renders service quotas meaningless.
          </p>
          <div className="p-4 rounded-xl bg-red-950/30 border border-red-500/20 space-y-1 font-mono text-xs">
            <div className="text-red-400 font-bold uppercase tracking-wider">
              Error: {error.code}
            </div>
            <div className="text-gray-300 leading-normal">{error.message}</div>
          </div>
        </div>

        <div className="space-y-3 pt-2 border-t border-white/10">
          <h2 className="text-xs font-semibold text-gray-400 font-mono uppercase tracking-wider">
            Required Configuration
          </h2>
          <div className="p-4 rounded-xl bg-purple-950/40 border border-purple-500/30 space-y-2 text-xs font-mono text-gray-300">
            <p className="text-purple-300 font-medium">{error.resolution}</p>
            <div className="bg-black/60 p-3.5 rounded-lg text-gray-200 select-all border border-white/10 overflow-x-auto space-y-1">
              <div className="text-gray-500"># In website/.env.local:</div>
              <div>PROD_SUPABASE_URL=https://&lt;your-project-ref&gt;.supabase.co</div>
              <div>PROD_SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOi...</div>
            </div>
            <p className="text-gray-400 text-[11px] pt-1">
              Providing <code className="text-purple-300">PROD_SUPABASE_URL</code> targets production for telemetry without altering your local app&apos;s dev database.
            </p>
          </div>
        </div>

        <div className="pt-2 flex items-center justify-between border-t border-white/5">
          <span className="text-xs text-gray-500 font-mono">SyncTogether Telemetry Guard</span>
          <a
            href="/admin"
            className="inline-flex items-center gap-2 px-4 py-2 rounded-xl bg-purple-600 hover:bg-purple-500 text-white font-mono text-xs font-semibold transition"
          >
            <RefreshCw className="w-3.5 h-3.5" />
            Retry Connection
          </a>
        </div>
      </GlassPanel>
    </div>
  );
}

function renderQuotaCard(quota: ServiceQuotaMetric, icon: React.ReactNode) {
  const isCritical = quota.status === "critical";
  const isWarning = quota.status === "warning";

  const statusBadge = isCritical
    ? { text: "CRITICAL", bg: "bg-red-500/10", border: "border-red-500/30", textCol: "text-red-400" }
    : isWarning
    ? { text: "WARNING", bg: "bg-amber-500/10", border: "border-amber-500/30", textCol: "text-amber-400" }
    : { text: "HEALTHY", bg: "bg-emerald-500/10", border: "border-emerald-500/30", textCol: "text-emerald-400" };

  const barColor = isCritical
    ? "bg-red-500"
    : isWarning
    ? "bg-amber-400"
    : "bg-gradient-to-r from-purple-500 to-emerald-400";

  return (
    <GlassPanel glow="purple" className="p-6 flex flex-col justify-between space-y-4 border-purple-500/20">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2.5">
          <div className="p-2 rounded-xl bg-purple-500/10 border border-purple-400/20">
            {icon}
          </div>
          <span className="text-xs font-mono uppercase tracking-wider text-gray-300 font-semibold">
            {quota.name}
          </span>
        </div>
        <span
          className={`px-2 py-0.5 rounded-full text-[10px] font-mono font-bold uppercase tracking-wider border ${statusBadge.bg} ${statusBadge.border} ${statusBadge.textCol}`}
        >
          {statusBadge.text}
        </span>
      </div>

      <div className="space-y-2">
        <div className="flex items-baseline justify-between">
          <div className="flex items-baseline gap-1.5">
            <span className="text-2xl font-extrabold text-white font-[family-name:var(--font-space-grotesk)]">
              {quota.formattedUsed}
            </span>
            <span className="text-xs text-gray-400 font-mono">
              / {quota.formattedLimit}
            </span>
          </div>
          <span className={`text-sm font-bold font-mono ${statusBadge.textCol}`}>
            {quota.percentage}%
          </span>
        </div>

        {/* Visual Progress Bar */}
        <div className="w-full h-2 rounded-full bg-white/10 overflow-hidden">
          <div
            className={`h-full rounded-full transition-all duration-500 ${barColor}`}
            style={{ width: `${Math.min(100, quota.percentage)}%` }}
          />
        </div>
      </div>

      <div className="pt-3 border-t border-white/5 flex items-center justify-between text-xs font-mono text-gray-400">
        <span>{quota.details}</span>
      </div>
    </GlassPanel>
  );
}

export default async function InternalMetricsPage() {
  const reqHeaders = await headers();
  if (!isAuthorizedLocalAccess({ headers: reqHeaders })) {
    notFound();
  }

  let metrics: DashboardMetrics | null = null;
  let credentialsError: { code: string; message: string; resolution: string } | null = null;

  try {
    metrics = await getDashboardMetrics();
  } catch (err) {
    if (err instanceof ProductionCredentialsError) {
      credentialsError = {
        code: err.code,
        message: err.message,
        resolution: err.resolution,
      };
    } else {
      throw err;
    }
  }

  if (credentialsError || !metrics) {
    return <ProductionCredentialsGate error={credentialsError!} />;
  }

  const {
    timestamp,
    health,
    infrastructure,
    downloads,
    traffic,
    users,
    activity,
    business,
  } = metrics;

  return (
    <div className="relative py-10 px-4 sm:px-6 lg:px-8 max-w-7xl mx-auto space-y-10">
      {/* Background Ambient Violet Glow */}
      <div className="glow-blob-purple top-12 left-1/2 -translate-x-1/2 opacity-25" />

      {/* Top Banner & Interactive Bar */}
      <div className="space-y-4">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div>
            <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-purple-500/10 border border-purple-400/20 text-xs font-mono text-purple-300">
              <Sparkles className="w-3.5 h-3.5 text-amber-300" />
              <span>Founder &amp; Executive Telemetry</span>
            </div>
            <h1 className="text-3xl sm:text-4xl font-extrabold text-white tracking-tight font-[family-name:var(--font-space-grotesk)] mt-2">
              SyncTogether <span className="text-gradient-brand">Mission Control</span>
            </h1>
            <p className="text-sm text-gray-400 mt-1">
              Live production telemetry, service capacity quotas, and end-to-end user retention.
            </p>
          </div>

          <div className="flex items-center gap-3 flex-wrap">
            <div className="flex items-center gap-2 px-3 py-1.5 rounded-xl bg-[#120E22]/80 border border-emerald-500/30 text-xs font-mono text-emerald-300">
              <span className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse" />
              <span>Target: Production ({infrastructure.dataSource.targetHost})</span>
              <span className="text-gray-500">•</span>
              <span>{health.responseTimeMs}ms</span>
            </div>
            <div className="flex items-center gap-2 px-3 py-1.5 rounded-xl bg-[#120E22]/80 border border-white/10 text-xs font-mono text-gray-300">
              <Compass className="w-3.5 h-3.5 text-purple-400" />
              <span>Release: v{health.latestAppVersion}</span>
            </div>
          </div>
        </div>

        {/* Live Controls */}
        <InternalMetricsControls timestamp={timestamp} data={metrics} />
      </div>

      {/* 1. EXECUTIVE KPI RIBBON (5 Core Questions at a Glance) */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-5">
        {/* KPI 1: Unique Visitors */}
        <GlassPanel glow="purple" className="p-6 flex flex-col justify-between space-y-4 border-purple-500/20">
          <div className="flex items-center justify-between">
            <span className="text-xs font-mono uppercase tracking-wider text-gray-400">
              1. Unique Visitors
            </span>
            <div className="p-2.5 rounded-xl bg-purple-500/10 text-purple-300 border border-purple-400/20">
              <Eye className="w-5 h-5" />
            </div>
          </div>
          <div>
            <div className="text-3xl font-extrabold text-white font-[family-name:var(--font-space-grotesk)]">
              {traffic.uniqueVisitorsTotal.toLocaleString()}
            </div>
            <p className="text-xs text-purple-300/80 mt-1 font-mono">
              Unique individuals (deduplicated)
            </p>
          </div>
          <div className="pt-3 border-t border-white/5 flex items-center justify-between text-xs font-mono text-gray-400">
            <span>Today: <strong className="text-white">{traffic.uniqueVisitors24h}</strong></span>
            <span>7 Days: <strong className="text-white">{traffic.uniqueVisitors7d}</strong></span>
            <span>30 Days: <strong className="text-white">{traffic.uniqueVisitors30d}</strong></span>
          </div>
        </GlassPanel>

        {/* KPI 2: Direct Website Downloads */}
        <GlassPanel glow="purple" className="p-6 flex flex-col justify-between space-y-4 border-purple-500/20">
          <div className="flex items-center justify-between">
            <span className="text-xs font-mono uppercase tracking-wider text-gray-400">
              2. Total Downloads
            </span>
            <div className="p-2.5 rounded-xl bg-purple-500/10 text-purple-300 border border-purple-400/20">
              <Download className="w-5 h-5" />
            </div>
          </div>
          <div>
            <div className="flex items-baseline gap-2">
              <span className="text-3xl font-extrabold text-white font-[family-name:var(--font-space-grotesk)]">
                {downloads.combinedTotal.toLocaleString()}
              </span>
              <span className="text-xs text-gray-400 font-mono">all sources</span>
            </div>
            <div className="text-xs text-purple-300/80 mt-1 font-mono flex items-center gap-1.5">
              <span>Direct site: <strong>{downloads.directWebsite.total}</strong></span>
              <span>•</span>
              <span>GitHub: <strong>{downloads.githubAllTime.totalDownloads}</strong></span>
            </div>
          </div>
          <div className="pt-3 border-t border-white/5 flex items-center justify-between text-xs font-mono text-gray-400">
            <span className="text-blue-300">macOS: <strong className="text-white">{downloads.macTotal}</strong></span>
            <span className="text-indigo-300">Windows: <strong className="text-white">{downloads.winTotal}</strong></span>
            <span>24h: <strong className="text-white">+{downloads.directWebsite.last24h}</strong></span>
          </div>
        </GlassPanel>

        {/* KPI 3: Active Premium & Free Users */}
        <GlassPanel glow="purple" className="p-6 flex flex-col justify-between space-y-4 border-purple-500/20">
          <div className="flex items-center justify-between">
            <span className="text-xs font-mono uppercase tracking-wider text-gray-400">
              3. User Tiers &amp; MRR
            </span>
            <div className="p-2.5 rounded-xl bg-amber-500/10 text-amber-300 border border-amber-400/20">
              <Crown className="w-5 h-5" />
            </div>
          </div>
          <div>
            <div className="flex items-baseline gap-2">
              <span className="text-3xl font-extrabold text-white font-[family-name:var(--font-space-grotesk)]">
                {users.activePremiumUsers}
              </span>
              <span className="text-xs font-mono text-amber-300">
                Premium (${business.estimatedMrr}/mo)
              </span>
            </div>
            <p className="text-xs text-gray-400 mt-1 font-mono">
              Free registered: <strong className="text-white">{users.registeredFreeUsers}</strong>
            </p>
          </div>
          <div className="pt-3 border-t border-white/5 flex items-center justify-between text-xs font-mono text-gray-400">
            <span>Guests: <strong className="text-white">{users.guestUsers}</strong></span>
            <span>Total Accounts: <strong className="text-white">{users.totalRegisteredAccounts}</strong></span>
          </div>
        </GlassPanel>

        {/* KPI 4: MAU and DAU */}
        <GlassPanel glow="purple" className="p-6 flex flex-col justify-between space-y-4 border-purple-500/20">
          <div className="flex items-center justify-between">
            <span className="text-xs font-mono uppercase tracking-wider text-gray-400">
              4. Product DAU / MAU
            </span>
            <div className="p-2.5 rounded-xl bg-emerald-500/10 text-emerald-300 border border-emerald-400/20">
              <Activity className="w-5 h-5" />
            </div>
          </div>
          <div>
            <div className="flex items-baseline gap-2">
              <span className="text-3xl font-extrabold text-white font-[family-name:var(--font-space-grotesk)]">
                {activity.productDau}
              </span>
              <span className="text-sm font-bold text-gray-400 font-mono">
                / {activity.productMau} MAU
              </span>
            </div>
            <div className="text-xs text-emerald-400 mt-1 font-mono flex items-center gap-1.5">
              <TrendingUp className="w-3.5 h-3.5" />
              <span>Stickiness: <strong>{activity.productStickinessPercent}%</strong></span>
            </div>
          </div>
          <div className="pt-3 border-t border-white/5 flex items-center justify-between text-xs font-mono text-gray-400">
            <span>Web DAU: <strong className="text-white">{activity.websiteDau}</strong></span>
            <span>Web MAU: <strong className="text-white">{activity.websiteMau}</strong></span>
          </div>
        </GlassPanel>
      </div>

      {/* 2. INFRASTRUCTURE, SERVICE QUOTAS & SYSTEM HEALTH */}
      <div className="space-y-4">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div>
            <div className="flex items-center gap-2">
              <HardDrive className="w-5 h-5 text-purple-400" />
              <h2 className="text-xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
                Infrastructure &amp; Service Quotas
              </h2>
            </div>
            <p className="text-xs text-gray-400 mt-1">
              Live capacity limits and utilization derived directly from production database state and media assets.
            </p>
          </div>

          {/* Quick Launch Console Hub */}
          <div className="flex items-center gap-2 flex-wrap">
            <span className="text-xs text-gray-400 font-mono mr-1">Consoles:</span>
            <a
              href={infrastructure.consoleLinks.supabaseUsage}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-purple-950/40 hover:bg-purple-900/40 border border-purple-500/20 text-xs font-mono text-gray-300 hover:text-white transition"
            >
              <Database className="w-3.5 h-3.5 text-emerald-400" />
              <span>Supabase Usage</span>
              <ExternalLink className="w-3 h-3 text-gray-500" />
            </a>
            <a
              href={infrastructure.consoleLinks.livekitConsole}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-purple-950/40 hover:bg-purple-900/40 border border-purple-500/20 text-xs font-mono text-gray-300 hover:text-white transition"
            >
              <Video className="w-3.5 h-3.5 text-purple-400" />
              <span>LiveKit Console</span>
              <ExternalLink className="w-3 h-3 text-gray-500" />
            </a>
            <a
              href={infrastructure.consoleLinks.cloudflareR2}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-purple-950/40 hover:bg-purple-900/40 border border-purple-500/20 text-xs font-mono text-gray-300 hover:text-white transition"
            >
              <HardDrive className="w-3.5 h-3.5 text-amber-400" />
              <span>Cloudflare R2</span>
              <ExternalLink className="w-3 h-3 text-gray-500" />
            </a>
          </div>
        </div>

        {/* Quota Progress Cards */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-5">
          {renderQuotaCard(
            infrastructure.services.livekit,
            <Video className="w-5 h-5 text-purple-300" />
          )}
          {renderQuotaCard(
            infrastructure.services.cloudflareR2,
            <HardDrive className="w-5 h-5 text-amber-300" />
          )}
          {renderQuotaCard(
            infrastructure.services.supabaseDatabase,
            <Database className="w-5 h-5 text-emerald-300" />
          )}
        </div>
      </div>

      {/* 3. FULL CONVERSION FUNNEL & BUSINESS CONVERSION */}
      <GlassPanel className="p-8 border-purple-500/20 space-y-6">
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
          <div>
            <div className="flex items-center gap-2">
              <Layers className="w-5 h-5 text-purple-400" />
              <h2 className="text-xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
                End-to-End Business Conversion Funnel
              </h2>
            </div>
            <p className="text-xs text-gray-400 mt-1">
              Calculates audience drop-off from visitor arrival through app download, account creation, and paid upgrade.
            </p>
          </div>
          <div className="flex items-center gap-4 text-xs font-mono bg-purple-950/40 px-4 py-2 rounded-xl border border-purple-500/20">
            <div>
              <span className="text-gray-400">Visitor → Download: </span>
              <strong className="text-purple-300">
                {business.funnel[1].conversionRate}%
              </strong>
            </div>
            <span className="text-gray-600">|</span>
            <div>
              <span className="text-gray-400">Account → Premium: </span>
              <strong className="text-amber-300">
                {business.payingConversionPercent}%
              </strong>
            </div>
          </div>
        </div>

        {/* Funnel Visual Cards */}
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
          {business.funnel.map((stage, idx) => (
            <div
              key={stage.name}
              className="relative p-5 rounded-2xl bg-[#140F24]/80 border border-purple-500/15 flex flex-col justify-between space-y-3"
            >
              <div className="flex items-center justify-between text-xs font-mono text-gray-400">
                <span>Stage 0{idx + 1}</span>
                <span className="text-purple-300 font-bold">
                  {stage.overallRate}% total
                </span>
              </div>
              <div>
                <div className="text-2xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
                  {stage.count.toLocaleString()}
                </div>
                <div className="text-sm font-semibold text-gray-200 mt-0.5">
                  {stage.name}
                </div>
              </div>
              <div className="text-xs text-gray-400 font-mono pt-2 border-t border-white/5">
                {idx === 0 ? (
                  <span>Top of funnel</span>
                ) : (
                  <span>
                    <strong>{stage.conversionRate}%</strong> of prev step
                  </span>
                )}
              </div>
            </div>
          ))}
        </div>
      </GlassPanel>

      {/* 4. DOWNLOADS & PLATFORMS BREAKDOWN */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
        {/* Direct Website Downloads Detail */}
        <GlassPanel className="p-6 border-purple-500/20 space-y-6">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <Download className="w-5 h-5 text-purple-400" />
              <h3 className="text-lg font-bold text-white font-[family-name:var(--font-space-grotesk)]">
                Direct Website Downloads
              </h3>
            </div>
            <span className="text-xs font-mono text-purple-300 bg-purple-500/10 px-2.5 py-1 rounded-full border border-purple-400/20">
              Tracked via /api/download
            </span>
          </div>

          <div className="grid grid-cols-3 gap-3 text-center">
            <div className="p-3 rounded-xl bg-purple-950/30 border border-purple-500/15">
              <div className="text-xs font-mono text-gray-400">24 Hours</div>
              <div className="text-xl font-bold text-white mt-1">
                {downloads.directWebsite.last24h}
              </div>
            </div>
            <div className="p-3 rounded-xl bg-purple-950/30 border border-purple-500/15">
              <div className="text-xs font-mono text-gray-400">7 Days</div>
              <div className="text-xl font-bold text-white mt-1">
                {downloads.directWebsite.last7d}
              </div>
            </div>
            <div className="p-3 rounded-xl bg-purple-950/30 border border-purple-500/15">
              <div className="text-xs font-mono text-gray-400">30 Days</div>
              <div className="text-xl font-bold text-white mt-1">
                {downloads.directWebsite.last30d}
              </div>
            </div>
          </div>

          {/* Platform Distribution Bar */}
          <div className="space-y-2">
            <div className="flex justify-between text-xs font-mono text-gray-400">
              <span>Platform Split:</span>
              <span>macOS ({downloads.directWebsite.macos}) • Windows ({downloads.directWebsite.windows})</span>
            </div>
            <div className="w-full h-2 rounded-full bg-white/10 overflow-hidden flex">
              <div
                className="bg-purple-500 h-full transition-all duration-500"
                style={{
                  width: `${
                    downloads.directWebsite.total > 0
                      ? (downloads.directWebsite.macos / downloads.directWebsite.total) * 100
                      : 50
                  }%`,
                }}
              />
              <div
                className="bg-indigo-400 h-full transition-all duration-500"
                style={{
                  width: `${
                    downloads.directWebsite.total > 0
                      ? (downloads.directWebsite.windows / downloads.directWebsite.total) * 100
                      : 50
                  }%`,
                }}
              />
            </div>
          </div>
        </GlassPanel>

        {/* GitHub Releases All-Time Detail */}
        <GlassPanel className="p-6 border-purple-500/20 space-y-6">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <Share2 className="w-5 h-5 text-purple-400" />
              <h3 className="text-lg font-bold text-white font-[family-name:var(--font-space-grotesk)]">
                GitHub Releases Downloads
              </h3>
            </div>
            <span className="text-xs font-mono text-indigo-300 bg-indigo-500/10 px-2.5 py-1 rounded-full border border-indigo-400/20">
              {downloads.githubAllTime.releasesCount} Releases Published
            </span>
          </div>

          <div className="grid grid-cols-2 gap-4 text-center">
            <div className="p-3.5 rounded-xl bg-purple-950/30 border border-purple-500/15">
              <div className="text-xs font-mono text-gray-400">macOS DMG</div>
              <div className="text-xl font-bold text-purple-300 mt-1">
                {downloads.githubAllTime.macDownloads}
              </div>
            </div>
            <div className="p-3.5 rounded-xl bg-purple-950/30 border border-purple-500/15">
              <div className="text-xs font-mono text-gray-400">Windows EXE</div>
              <div className="text-xl font-bold text-indigo-300 mt-1">
                {downloads.githubAllTime.winDownloads}
              </div>
            </div>
          </div>

          {/* Per-Release Breakdown Preview */}
          <div className="space-y-2">
            <div className="text-xs font-mono text-gray-400">Latest Release Versions:</div>
            <div className="max-h-36 overflow-y-auto space-y-1.5 pr-1 font-mono text-xs">
              {downloads.githubAllTime.releases.slice(0, 5).map((rel) => (
                <div
                  key={rel.tagName}
                  className="flex items-center justify-between p-2 rounded-lg bg-white/5 hover:bg-white/10 transition-colors"
                >
                  <span className="text-white font-medium">{rel.tagName}</span>
                  <div className="flex items-center gap-3 text-gray-400">
                    <span>DMG: {rel.macDownloads}</span>
                    <span>EXE: {rel.winDownloads}</span>
                    <span className="text-purple-300 font-bold">Total: {rel.totalDownloads}</span>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </GlassPanel>
      </div>

      {/* 5. REAL-TIME ROOMS & PRODUCT ENGAGEMENT */}
      <GlassPanel className="p-8 border-purple-500/20 space-y-6">
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
          <div className="flex items-center gap-2">
            <Tv className="w-5 h-5 text-purple-400" />
            <h3 className="text-lg font-bold text-white font-[family-name:var(--font-space-grotesk)]">
              Real-Time Playback &amp; Room Activity
            </h3>
          </div>
          <div className="flex items-center gap-2 text-xs font-mono">
            <span className="w-2.5 h-2.5 rounded-full bg-emerald-400 animate-pulse" />
            <span className="text-emerald-400 font-semibold">
              Live: {business.rooms.liveRoomsNow} rooms ({business.rooms.liveParticipantsNow} participants)
            </span>
          </div>
        </div>

        <div className="grid grid-cols-2 sm:grid-cols-4 gap-4 text-center">
          <div className="p-4 rounded-xl bg-purple-950/20 border border-purple-500/15">
            <div className="text-xs font-mono text-gray-400">All-Time Rooms</div>
            <div className="text-2xl font-extrabold text-white mt-1">
              {business.rooms.totalRoomsAllTime}
            </div>
            <div className="text-[11px] text-gray-500 font-mono mt-0.5">created rooms</div>
          </div>

          <div className="p-4 rounded-xl bg-purple-950/20 border border-purple-500/15">
            <div className="text-xs font-mono text-gray-400">Rooms (7 Days)</div>
            <div className="text-2xl font-extrabold text-white mt-1">
              {business.rooms.roomsLast7d}
            </div>
            <div className="text-[11px] text-gray-500 font-mono mt-0.5">weekly activity</div>
          </div>

          <div className="p-4 rounded-xl bg-purple-950/20 border border-purple-500/15">
            <div className="text-xs font-mono text-gray-400">Media Distribution</div>
            <div className="text-sm font-bold text-purple-300 mt-2 font-mono">
              YT: {business.rooms.mediaDistribution.youtube} • Local: {business.rooms.mediaDistribution.local}
            </div>
            <div className="text-[11px] text-gray-500 font-mono mt-0.5">None: {business.rooms.mediaDistribution.none}</div>
          </div>

          <div className="p-4 rounded-xl bg-purple-950/20 border border-purple-500/15">
            <div className="text-xs font-mono text-gray-400">Chat Messages</div>
            <div className="text-2xl font-extrabold text-white mt-1">
              {business.rooms.totalMessagesSent}
            </div>
            <div className="text-[11px] text-gray-500 font-mono mt-0.5">lifetime messages</div>
          </div>
        </div>
      </GlassPanel>

      {/* 6. TRAFFIC QUALITY, REFERRERS & PAGES */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
        {/* Top Referrers */}
        <GlassPanel className="p-6 border-purple-500/20 space-y-4">
          <div className="flex items-center justify-between">
            <h4 className="text-base font-bold text-white font-[family-name:var(--font-space-grotesk)]">
              Top Referring Domains
            </h4>
            <span className="text-xs font-mono text-gray-400">Acquisition</span>
          </div>

          {traffic.topReferrers.length === 0 ? (
            <div className="text-xs font-mono text-gray-500 py-6 text-center">
              No external referrers logged yet (direct visits or local dev).
            </div>
          ) : (
            <div className="space-y-2">
              {traffic.topReferrers.map((ref) => (
                <div
                  key={ref.source}
                  className="flex items-center justify-between p-2.5 rounded-xl bg-white/5 text-xs font-mono"
                >
                  <span className="text-gray-200">{ref.source}</span>
                  <span className="text-purple-300 font-bold">{ref.count} visit{ref.count === 1 ? "" : "s"}</span>
                </div>
              ))}
            </div>
          )}
        </GlassPanel>

        {/* Traffic Engagement Metrics */}
        <GlassPanel className="p-6 border-purple-500/20 space-y-4">
          <div className="flex items-center justify-between">
            <h4 className="text-base font-bold text-white font-[family-name:var(--font-space-grotesk)]">
              Traffic Quality &amp; Engagement
            </h4>
            <span className="text-xs font-mono text-gray-400">Session Depth</span>
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div className="p-3.5 rounded-xl bg-purple-950/20 border border-purple-500/15">
              <div className="text-xs font-mono text-gray-400">Pages / Visitor</div>
              <div className="text-2xl font-bold text-white mt-1">
                {traffic.pagesPerVisitor}
              </div>
              <div className="text-[11px] text-gray-500 font-mono mt-0.5">
                Total pageviews: {traffic.totalPageviews}
              </div>
            </div>

            <div className="p-3.5 rounded-xl bg-purple-950/20 border border-purple-500/15">
              <div className="text-xs font-mono text-gray-400">Bounce Rate</div>
              <div className="text-2xl font-bold text-white mt-1">
                {traffic.bounceRatePercent}%
              </div>
              <div className="text-[11px] text-gray-500 font-mono mt-0.5">
                Single-page sessions
              </div>
            </div>
          </div>

          {/* Top Visited Pages */}
          <div className="space-y-2 pt-2">
            <div className="text-xs font-mono text-gray-400">Top Visited Pages:</div>
            {traffic.topPages.length === 0 ? (
              <div className="text-xs font-mono text-gray-500 py-2 text-center">
                Waiting for first pageviews...
              </div>
            ) : (
              traffic.topPages.map((p) => (
                <div
                  key={p.path}
                  className="flex items-center justify-between p-2 rounded-lg bg-white/5 text-xs font-mono"
                >
                  <span className="text-gray-200">{p.path}</span>
                  <span className="text-purple-300 font-semibold">{p.count} view{p.count === 1 ? "" : "s"}</span>
                </div>
              ))
            )}
          </div>
        </GlassPanel>
      </div>
    </div>
  );
}
