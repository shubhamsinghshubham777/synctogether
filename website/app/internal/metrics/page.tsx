import type { Metadata } from "next";
import { headers } from "next/headers";
import { notFound } from "next/navigation";
import type { ReactNode } from "react";
import { isAuthorizedLocalAccess } from "@/lib/admin-guard";
import { getDashboardMetrics, type DashboardMetrics } from "@/lib/metrics";
import { formatBytes } from "@/lib/metrics_logic";
import { ProductionCredentialsError } from "@/lib/supabase/admin";
import { GlassPanel } from "@/components/GlassPanel";
import { InternalMetricsControls } from "./InternalMetricsControls";
import {
  Activity,
  Crown,
  Database,
  Download,
  ExternalLink,
  Eye,
  HardDrive,
  ShieldAlert,
  Tv,
  Video,
} from "lucide-react";

export const metadata: Metadata = {
  title: "Internal Metrics | SyncTogether",
  description: "Local-only internal metrics dashboard for SyncTogether",
  robots: { index: false, follow: false },
};

export const dynamic = "force-dynamic";

const UNAVAILABLE = "unavailable";

function num(v: number | null | undefined): string {
  return v == null ? UNAVAILABLE : v.toLocaleString();
}

function pct(v: number | null | undefined): string {
  return v == null ? UNAVAILABLE : `${v}%`;
}

function bytes(v: number | null | undefined): string {
  return v == null ? UNAVAILABLE : formatBytes(v);
}

function money(v: number, currency: string): string {
  return v.toLocaleString(undefined, { style: "currency", currency, maximumFractionDigits: 2 });
}

/** One figure with its definition beneath it - the definition is the point. */
function Stat({ label, value, def, tone = "text-screen" }: { label: string; value: string; def: string; tone?: string }) {
  const muted = value === UNAVAILABLE || value === "not measured";
  return (
    <div className="p-4 rounded-md bg-aisle/60 border border-rail space-y-1">
      <div className="text-xs font-mono uppercase tracking-wider text-gray-400">{label}</div>
      <div className={`text-2xl font-bold font-mono ${muted ? "text-gray-500 text-base" : tone}`}>{value}</div>
      <p className="text-[11px] leading-snug text-gray-500">{def}</p>
    </div>
  );
}

function Section({ icon, title, note, children }: { icon: ReactNode; title: string; note?: ReactNode; children: ReactNode }) {
  return (
    <GlassPanel className="p-6 space-y-4">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2">
        <div className="flex items-center gap-2">
          {icon}
          <h2 className="text-lg font-bold text-screen font-[family-name:var(--font-space-grotesk)]">{title}</h2>
        </div>
        {note && <div className="text-xs font-mono text-gray-400">{note}</div>}
      </div>
      {children}
    </GlassPanel>
  );
}

function Grid({ children }: { children: ReactNode }) {
  return <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">{children}</div>;
}

function RankedList({ rows, empty, unit }: { rows: { key: string; count: number }[] | null; empty: string; unit: string }) {
  if (rows == null) return <div className="text-xs font-mono text-gray-500 py-2">{UNAVAILABLE}</div>;
  if (rows.length === 0) return <div className="text-xs font-mono text-gray-500 py-2">{empty}</div>;
  return (
    <div className="space-y-1.5">
      {rows.map((r) => (
        <div key={r.key} className="flex items-center justify-between gap-3 p-2 rounded-md bg-aisle/60 text-xs font-mono">
          <span className="text-gray-200 truncate">{r.key}</span>
          <span className="text-beam-300 shrink-0">
            {r.count.toLocaleString()} {unit}
          </span>
        </div>
      ))}
    </div>
  );
}

function ProductionCredentialsGate({ error }: { error: { code: string; message: string; resolution: string } }) {
  return (
    <div className="min-h-[85vh] flex items-center justify-center p-4 sm:p-6">
      <GlassPanel className="max-w-2xl w-full p-8 space-y-5 border-signal/40">
        <div className="flex items-start gap-4">
          <ShieldAlert className="w-8 h-8 text-signal shrink-0" />
          <div className="space-y-1">
            <h1 className="text-2xl font-bold text-screen">Production credentials required</h1>
            <p className="text-xs text-gray-400">This dashboard reads production only. Local or seed data is refused.</p>
          </div>
        </div>
        <div className="p-4 rounded-md bg-aisle border border-rail font-mono text-xs space-y-1">
          <div className="text-signal font-bold">{error.code}</div>
          <div className="text-gray-300">{error.message}</div>
        </div>
        <div className="p-4 rounded-md bg-aisle border border-rail font-mono text-xs space-y-2 text-gray-300">
          <p className="text-beam-300">{error.resolution}</p>
          <div className="text-gray-500"># website/.env.local</div>
          <div>PROD_SUPABASE_URL=https://&lt;project-ref&gt;.supabase.co</div>
          <div>PROD_SUPABASE_SERVICE_ROLE_KEY=...</div>
        </div>
      </GlassPanel>
    </div>
  );
}

export default async function InternalMetricsPage() {
  if (!isAuthorizedLocalAccess({ headers: await headers() })) notFound();

  let metrics: DashboardMetrics;
  try {
    metrics = await getDashboardMetrics();
  } catch (err) {
    if (err instanceof ProductionCredentialsError) {
      return <ProductionCredentialsGate error={{ code: err.code, message: err.message, resolution: err.resolution }} />;
    }
    throw err;
  }

  const { db, github, derived, source, consoleLinks } = metrics;
  const subs = db?.subscriptions;
  const mrr = derived.mrr;

  return (
    <div className="py-10 px-4 sm:px-6 lg:px-8 max-w-7xl mx-auto space-y-6">
      <div className="flex flex-col md:flex-row md:items-end justify-between gap-4">
        <div>
          <h1 className="text-3xl font-extrabold text-screen tracking-tight font-[family-name:var(--font-space-grotesk)]">
            Internal metrics
          </h1>
          <p className="text-sm text-gray-400 mt-1">
            Production data, local-only view. A figure that could not be read says so rather than guessing.
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-2 text-xs font-mono">
          <span className={`px-3 py-1.5 rounded-md border ${source.supabaseConnected ? "border-cue/40 text-cue" : "border-signal/40 text-signal"}`}>
            {source.host} ·{" "}
            {source.supabaseConnected ? `RPC ${source.rpcLatencyMs}ms` : `RPC failed${source.rpcError ? `: ${source.rpcError}` : ""}`}
          </span>
          <span className="px-3 py-1.5 rounded-md border border-rail text-gray-300">
            Latest release: {metrics.latestAppVersion ? `v${metrics.latestAppVersion}` : UNAVAILABLE}
          </span>
        </div>
      </div>

      <InternalMetricsControls timestamp={metrics.timestamp} data={metrics} />

      <Section icon={<Activity className="w-5 h-5 text-cue" />} title="Product activity">
        <Grid>
          <Stat label="DAU" value={num(db?.activity.dau)} tone="text-cue"
            def="Distinct users credited co-watching time in the last 24h (watch_ledger). Excludes guests and users who opted out of usage data." />
          <Stat label="WAU" value={num(db?.activity.wau)} def="Same, last 7 days." />
          <Stat label="MAU" value={num(db?.activity.mau)} def="Same, last 30 days. Signups are not added in." />
          <Stat label="Stickiness" value={pct(derived.productStickinessPercent)} def="DAU / MAU." />
        </Grid>
        <p className="text-xs font-mono text-gray-400">
          DAU by tier: premium {num(db?.activity.dau_by_tier.premium)} · free {num(db?.activity.dau_by_tier.free)} · guest{" "}
          {num(db?.activity.dau_by_tier.guest)} (guests earn no ledger time, so this is structurally ~0). Solo viewing is not measured here;
          see{" "}
          <a href={consoleLinks.posthog} target="_blank" rel="noopener noreferrer" className="text-beam-300 underline">PostHog</a>.
        </p>
      </Section>

      <Section icon={<Crown className="w-5 h-5 text-brass" />} title="Accounts & revenue">
        <Grid>
          <Stat label="Registered accounts" value={num(db?.accounts.registered)} def="Non-guest profiles, all sources (site, stores, direct)." />
          <Stat label="Premium" value={num(db?.accounts.premium)} tone="text-brass" def="Accounts whose effective_tier is premium, either rail, including manual grants." />
          <Stat label="Free" value={num(db?.accounts.free)} def="Registered minus premium." />
          <Stat label="Guests" value={num(db?.accounts.guests)} def="Anonymous profiles (purged after 3 days)." />
          <Stat label="Signups 24h / 7d / 30d" value={db ? `${num(db.signups.last_24h)} / ${num(db.signups.last_7d)} / ${num(db.signups.last_30d)}` : UNAVAILABLE}
            def="Profiles created in each window, guests included." />
          <Stat label="Paying, of active users" value={pct(derived.payingOfActivePercent)} def="Premium accounts / MAU." />
          <Stat label="Paddle MRR (USD equiv.)" value={mrr?.usdEquivalent != null ? money(mrr.usdEquivalent, "USD") : UNAVAILABLE} tone="text-brass"
            def={`Active Paddle rows, not past_due, charge normalised per month (annual / 12). INR at a fixed ${derived.inrPerUsd}/USD.`} />
          <Stat label="App Store subscribers" value={num(subs?.apple_production)}
            def={`Unrevoked, unexpired Production rows. Revenue lives in App Store Connect and is not computed. Sandbox: ${num(subs?.apple_sandbox)}.`} />
        </Grid>
        <div className="text-xs font-mono text-gray-400 space-y-1">
          <div>
            Paddle active {num(subs?.paddle_active)} · past_due {num(subs?.paddle_past_due)} (grace, excluded from MRR) · canceling at period end{" "}
            {num(subs?.paddle_canceling)} · no recorded price {num(subs?.paddle_unpriced)} (excluded until their next webhook) · manual/debug grants{" "}
            {num(subs?.manual_or_debug)} (no revenue)
          </div>
          {mrr && mrr.byCurrency.length > 0 && (
            <div>
              By currency: {mrr.byCurrency.map((c) => `${money(c.monthly, c.currency)}/mo from ${c.subscribers}`).join(" · ")}
              {mrr.unconvertedSubscribers > 0 && ` (${mrr.unconvertedSubscribers} in other currencies, not in the USD total)`}
            </div>
          )}
        </div>
      </Section>

      <Section icon={<Eye className="w-5 h-5 text-beam-400" />} title="Website"
        note={<a href={consoleLinks.posthog} target="_blank" rel="noopener noreferrer" className="inline-flex items-center gap-1 text-beam-300">Product funnel in PostHog <ExternalLink className="w-3 h-3" /></a>}>
        <Grid>
          <Stat label="Visitors" value={num(db?.website.visitors_total)}
            def={`First-party cookies, lifetime. Seen 24h ${num(db?.website.visitors_24h)} · 7d ${num(db?.website.visitors_7d)} · 30d ${num(db?.website.visitors_30d)}.`} />
          <Stat label="Visitors who downloaded" value={num(db?.website.visitors_who_downloaded)} def="Distinct cookies with at least one /api/download." />
          <Stat label="Visitor to download" value={pct(derived.visitorToDownloadPercent)} tone="text-beam-300" def="Previous two figures; one population, so at most 100%." />
          <Stat label="Single-page visitors (lifetime)" value={pct(derived.singlePageVisitorPercent)}
            def={`Cookies that viewed exactly one page, ever. Not a session bounce rate. Pageviews: ${num(db?.website.pageviews_total)}.`} />
        </Grid>
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
          <div className="space-y-2">
            <div className="text-xs font-mono text-gray-400">Top pages, last 30 days</div>
            <RankedList rows={db ? db.website.top_paths_30d.map((p) => ({ key: p.path, count: p.count })) : null} empty="No pageviews in 30 days." unit="views" />
          </div>
          <div className="space-y-2">
            <div className="text-xs font-mono text-gray-400">Top first referrers, visitors first seen in the last 30 days</div>
            <RankedList rows={db ? db.website.top_referrers_30d.map((r) => ({ key: r.source, count: r.count })) : null} empty="No external referrers in 30 days." unit="visitors" />
          </div>
        </div>
      </Section>

      <Section icon={<Download className="w-5 h-5 text-beam-400" />} title="Downloads">
        <Grid>
          <Stat label="Site downloads (acquisition)" value={num(db?.website.downloads_total)} tone="text-beam-300"
            def={`Clicks logged by /api/download. 24h ${num(db?.website.downloads_24h)} · 7d ${num(db?.website.downloads_7d)} · 30d ${num(db?.website.downloads_30d)}.`} />
          <Stat label="By platform" value={db ? Object.entries(db.website.downloads_by_platform).map(([k, v]) => `${k} ${v}`).join(" · ") || "0" : UNAVAILABLE}
            def="Site downloads by the platform requested." />
          <Stat label="GitHub binary fetches" value={num(github?.total)}
            def="Asset download_count across all releases. Includes self-updates and every site redirect, so never add it to site downloads." />
          <Stat label="GitHub fetches by OS" value={github ? `mac ${github.mac.toLocaleString()} · win ${github.win.toLocaleString()}` : UNAVAILABLE}
            def="By asset name (.dmg / .exe)." />
        </Grid>
        {github && github.releases.length > 0 && (
          <div className="space-y-1.5 font-mono text-xs max-h-40 overflow-y-auto">
            {github.releases.slice(0, 8).map((r) => (
              <div key={r.tagName} className="flex justify-between gap-3 p-2 rounded-md bg-aisle/60">
                <span className="text-screen">{r.tagName}{r.prerelease ? " (pre)" : ""}</span>
                <span className="text-gray-400">mac {r.mac} · win {r.win} · total {r.total}</span>
              </div>
            ))}
          </div>
        )}
      </Section>

      <Section icon={<Tv className="w-5 h-5 text-cue" />} title="Rooms">
        <Grid>
          <Stat label="Live rooms" value={num(db?.rooms.live_now)} tone="text-cue" def="room_state = live, including persistent premium rooms." />
          <Stat label="Member rows in live rooms" value={num(db?.rooms.member_rows_in_live_rooms)}
            def="Memberships, not people online. Presence is not measured here." />
          <Stat label="Rooms created" value={num(db?.rooms.total)} def={`All time. 7d ${num(db?.rooms.last_7d)} · 30d ${num(db?.rooms.last_30d)}.`} />
          <Stat label="Chat messages" value={num(db?.rooms.messages_total)} def="Rows in messages now. Chat dies with its room, so this is not lifetime." />
        </Grid>
        <p className="text-xs font-mono text-gray-400">
          Media kind of rooms that still exist:{" "}
          {db ? Object.entries(db.rooms.media_kind).map(([k, v]) => `${k} ${v}`).join(" · ") || "none" : UNAVAILABLE}
        </p>
      </Section>

      <Section icon={<HardDrive className="w-5 h-5 text-beam-400" />} title="Infrastructure"
        note={
          <div className="flex flex-wrap gap-3">
            <a href={consoleLinks.supabaseUsage} target="_blank" rel="noopener noreferrer" className="inline-flex items-center gap-1 text-beam-300"><Database className="w-3 h-3" />Supabase</a>
            <a href={consoleLinks.cloudflareR2} target="_blank" rel="noopener noreferrer" className="inline-flex items-center gap-1 text-beam-300"><HardDrive className="w-3 h-3" />R2</a>
            <a href={consoleLinks.livekitConsole} target="_blank" rel="noopener noreferrer" className="inline-flex items-center gap-1 text-beam-300"><Video className="w-3 h-3" />LiveKit</a>
          </div>
        }>
        <Grid>
          <Stat label="Database size" value={bytes(db?.storage.db_bytes)}
            def={derived.dbCapBytes && db ? `pg_database_size, ${Math.round((db.storage.db_bytes / derived.dbCapBytes) * 100)}% of ${formatBytes(derived.dbCapBytes)} (SUPABASE_DB_CAP_BYTES).` : "pg_database_size. Set SUPABASE_DB_CAP_BYTES to see it against your plan."} />
          <Stat label="R2: room media" value={bytes(db?.storage.active_room_media_bytes)} def="Rooms whose shared upload is ready. What the DB references, not a bucket listing." />
          <Stat label="R2: staged uploads" value={bytes(db?.storage.staged_ready_bytes)} def="Ready lobby pre-uploads not yet claimed by a room." />
          <Stat label="R2: queued deletions" value={num(db?.storage.pending_r2_deletions)} def="Objects in pending_r2_deletions. The queue records no sizes." />
          <Stat label="LiveKit usage" value="not measured" def="No SFU probe is wired up; check the LiveKit console." />
          <Stat label="R2 bucket size" value="not measured" def="Real bucket bytes need Cloudflare analytics; check the R2 console." />
        </Grid>
      </Section>
    </div>
  );
}
