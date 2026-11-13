import type { Metadata } from "next";
import { headers } from "next/headers";
import { notFound } from "next/navigation";
import Link from "next/link";
import type { ReactNode } from "react";
import { isAuthorizedLocalAccess } from "@/lib/admin-guard";
import { getDashboardMetrics, type DashboardMetrics, type TrafficSources } from "@/lib/metrics";
import { formatBytes, unreferencedR2Bytes } from "@/lib/metrics_logic";
import { ProductionCredentialsError } from "@/lib/supabase/admin";
import { GlassPanel } from "@/components/GlassPanel";
import { InternalMetricsControls } from "./InternalMetricsControls";
import {
  Activity,
  ArrowLeft,
  Bug,
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
  title: "Internal Metrics",
  description: "Local-only internal metrics dashboard for SyncTogether",
  robots: { index: false, follow: false },
};

export const dynamic = "force-dynamic";

const UNAVAILABLE = "unavailable";

/** The sources the organic reach playbook asks to be watched, by referrer host. */
const PLAYBOOK_CHANNELS = [
  { label: "Pinterest", hosts: ["pinterest.com", "pin.it"] },
  { label: "Reddit", hosts: ["reddit.com"] },
  { label: "TikTok", hosts: ["tiktok.com"] },
  { label: "Instagram", hosts: ["instagram.com", "l.instagram.com"] },
  { label: "YouTube", hosts: ["youtube.com", "youtu.be"] },
  { label: "ChatGPT", hosts: ["chatgpt.com"] },
  { label: "Perplexity", hosts: ["perplexity.ai"] },
  { label: "Direct", hosts: ["(direct)"] },
];

const TREND_BUCKETS = 8;

/** Oldest to newest. `weekly` ages are 0 = newest, so reverse into reading order. */
function trendFor(t: TrafficSources, hosts: string[]): number[] {
  const out = new Array<number>(TREND_BUCKETS).fill(0);
  for (const w of t.weekly) {
    if (w.age < 0 || w.age >= TREND_BUCKETS) continue;
    if (hosts.some((h) => w.source === h || w.source.endsWith(`.${h}`))) out[TREND_BUCKETS - 1 - w.age] += w.visitors;
  }
  return out;
}

/** Tiny dependency-free line; the final point is dotted because it is the live window. */
function Sparkline({ values }: { values: number[] }) {
  const w = 96, h = 28, pad = 3;
  const max = Math.max(...values, 1);
  const pts = values.map((v, i) => [pad + (i * (w - pad * 2)) / (values.length - 1), h - pad - (v / max) * (h - pad * 2)]);
  const last = pts[pts.length - 1];
  return (
    <svg viewBox={`0 0 ${w} ${h}`} className="w-full h-7" role="img" aria-label={`Weekly new visitors, oldest to newest: ${values.join(", ")}`}>
      <polyline points={pts.map((p) => p.join(",")).join(" ")} fill="none" className="stroke-beam-400" strokeWidth="1.5" strokeLinejoin="round" strokeLinecap="round" />
      <circle cx={last[0]} cy={last[1]} r="2" className="fill-beam-300" />
    </svg>
  );
}

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
function Stat({ label, value, def, tone = "text-screen", href }: { label: string; value: string; def: ReactNode; tone?: string; href?: string }) {
  const muted = value === UNAVAILABLE || value === "not measured";
  const body = (
    <>
      <div className="flex items-center justify-between gap-2 text-xs font-mono uppercase tracking-wider text-gray-400">
        {label}
        {href && <ExternalLink className="w-3 h-3 shrink-0 opacity-60 group-hover:opacity-100 group-hover:text-beam-300 transition-opacity" />}
      </div>
      <div className={`text-2xl font-bold font-mono ${muted ? "text-gray-500 text-base" : tone}`}>{value}</div>
      <p className="text-[11px] leading-snug text-gray-500">{def}</p>
    </>
  );
  const box = "block p-4 rounded-md bg-aisle/60 border border-rail space-y-1";
  return href ? (
    <a href={href} target="_blank" rel="noopener noreferrer" className={`group ${box} hover:border-beam-400/50 transition-colors`}>
      {body}
    </a>
  ) : (
    <div className={box}>{body}</div>
  );
}

/** Cloudflare's own total beside what the database references; the gap is what nothing will clean up. */
function R2BucketStat({ r2, referencedBytes }: { r2: DashboardMetrics["r2"]; referencedBytes: number | null }) {
  if (!r2.configured) {
    return (
      <Stat label="R2 bucket size" value="not measured"
        def="Set CLOUDFLARE_ACCOUNT_ID and CLOUDFLARE_API_TOKEN (Workers R2 Storage: Read) in website/.env.local to read it." />
    );
  }
  if (!r2.usage) {
    return <Stat label="R2 bucket size" value={UNAVAILABLE} def={`Cloudflare did not answer${r2.error ? `: ${r2.error}` : ""}.`} />;
  }
  const { usage } = r2;
  const orphaned = referencedBytes == null ? null : unreferencedR2Bytes(usage.publishedBytes, referencedBytes);
  return (
    <Stat label="R2 bucket size" value={formatBytes(usage.publishedBytes)}
      def={`${usage.objects.toLocaleString()} objects across the account's buckets, per Cloudflare (can lag). ${
        orphaned == null ? "" : `Not referenced by any room or staged upload: ${formatBytes(orphaned)}. `
      }${usage.pendingUploadBytes > 0 ? `Unfinished multipart uploads: ${formatBytes(usage.pendingUploadBytes)}.` : ""}`} />
  );
}

/** Headroom colour for a share of a plan limit: calm, then a warning, then act now. */
function capTone(share: number): string {
  return share >= 0.9 ? "text-signal" : share >= 0.7 ? "text-beam-300" : "text-cue";
}

const PLATFORM_LABELS: Record<string, string> = { macos: "macOS", windows: "Windows", other: "Other" };

/** Share of a keyed count per row, largest first; the bar is the share, so rows compare at a glance. */
function PlatformBreakdown({ counts }: { counts: Record<string, number> | null }) {
  const rows = counts ? Object.entries(counts).sort((a, b) => b[1] - a[1]) : [];
  const total = rows.reduce((n, [, v]) => n + v, 0);
  return (
    <div className="p-4 rounded-md bg-aisle/60 border border-rail space-y-3">
      <div className="text-xs font-mono uppercase tracking-wider text-gray-400">By platform</div>
      {counts == null ? (
        <div className="text-base font-bold font-mono text-gray-500">{UNAVAILABLE}</div>
      ) : total === 0 ? (
        <div className="text-base font-bold font-mono text-gray-500">0</div>
      ) : (
        <div className="space-y-2.5">
          {rows.map(([platform, n]) => {
            const share = (n / total) * 100;
            return (
              <div key={platform} className="space-y-1">
                <div className="flex items-baseline justify-between gap-3 font-mono">
                  <span className="text-sm text-gray-200">{PLATFORM_LABELS[platform] ?? platform}</span>
                  <span className="text-sm text-screen">
                    <span className="font-bold">{n.toLocaleString()}</span>
                    <span className="text-xs text-gray-400 ml-2 inline-block w-10 text-right">{Math.round(share)}%</span>
                  </span>
                </div>
                <div className="h-1.5 rounded-full bg-rail overflow-hidden">
                  <div className="h-full rounded-full bg-beam-400" style={{ width: `${share}%` }} />
                </div>
              </div>
            );
          })}
        </div>
      )}
      <p className="text-[11px] leading-snug text-gray-500">Site downloads by the platform requested.</p>
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

  const { db, derived, source, consoleLinks, trafficSources } = metrics;
  const subs = db?.subscriptions;
  const mrr = derived.mrr;

  return (
    <div className="py-10 px-4 sm:px-6 lg:px-8 max-w-7xl mx-auto space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 border-b border-rail pb-4">
        <div className="flex items-center gap-3">
          <div className="p-2.5 rounded-xl bg-purple-600/20 border border-purple-500/30 text-purple-400">
            <Activity className="w-6 h-6" />
          </div>
          <div>
            <h1 className="text-xl font-bold font-[family-name:var(--font-space-grotesk)] text-screen tracking-tight">Internal Metrics</h1>
            <p className="text-xs text-gray-400 font-mono">
              Production Data &bull; Local-Only View &bull; Unreadable Figures Say So
            </p>
            <span
              className={`mt-2 inline-block px-2.5 py-1 rounded-lg border text-xs font-mono ${source.supabaseConnected ? "border-cue/40 text-cue" : "border-signal/40 text-signal"}`}
            >
              {source.host} ·{" "}
              {source.supabaseConnected ? `RPC ${source.rpcLatencyMs}ms` : `RPC failed${source.rpcError ? `: ${source.rpcError}` : ""}`}
            </span>
          </div>
        </div>

        <div className="flex flex-wrap items-center gap-2">
          <Link
            href="/internal/moderation"
            replace
            className="px-3 py-1.5 rounded-lg bg-aisle hover:bg-aisle/80 text-xs font-mono text-gray-300 hover:text-white border border-rail flex items-center gap-1.5 transition-colors"
          >
            <ShieldAlert className="w-3.5 h-3.5 text-beam-300" />
            Moderation
          </Link>
          <Link
            href="/internal/bugs"
            replace
            className="px-3 py-1.5 rounded-lg bg-aisle hover:bg-aisle/80 text-xs font-mono text-gray-300 hover:text-white border border-rail flex items-center gap-1.5 transition-colors"
          >
            <Bug className="w-3.5 h-3.5 text-beam-300" />
            Bug Board
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
          <Stat label="Web MRR (USD equiv.)" value={mrr?.usdEquivalent != null ? money(mrr.usdEquivalent, "USD") : UNAVAILABLE} tone="text-brass"
            def={`Active web-provider rows, not past_due, charge normalised per month (annual / 12). INR at a fixed ${derived.inrPerUsd}/USD.`} />
          <Stat label="App Store subscribers" value={num(subs?.apple_production)}
            def={`Unrevoked, unexpired Production rows. Revenue lives in App Store Connect and is not computed. Sandbox: ${num(subs?.apple_sandbox)}.`} />
        </Grid>
        <div className="text-xs font-mono text-gray-400 space-y-1">
          <div>
            Web active {num(subs?.web_active)}{subs?.web_by_provider && Object.keys(subs.web_by_provider).length > 0 ? ` (${Object.entries(subs.web_by_provider).map(([k, n]) => `${k} ${n}`).join(", ")})` : ""} · past_due {num(subs?.web_past_due)} (grace, excluded from MRR) · canceling at period end{" "}
            {num(subs?.web_canceling)} · no recorded price {num(subs?.web_unpriced)} (excluded until their next webhook) · manual/debug grants{" "}
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
          <Stat label="Visitors who downloaded" value={num(db?.website.visitors_who_downloaded)} def="Distinct cookies that clicked a download button. History only: the site now links to the stores." />
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

      <Section icon={<Eye className="w-5 h-5 text-beam-400" />} title="Traffic sources"
        note="New visitors by first referrer · organic reach playbook, step 5">
        {trafficSources == null ? (
          <div className="text-xs font-mono text-gray-500 py-2">{UNAVAILABLE}</div>
        ) : (
          <>
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
              {PLAYBOOK_CHANNELS.map((c) => {
                const row = trafficSources.sources.filter((s) => c.hosts.some((h) => s.source === h || s.source.endsWith(`.${h}`)));
                const v7 = row.reduce((n, s) => n + s.visitors_7d, 0);
                const v30 = row.reduce((n, s) => n + s.visitors_30d, 0);
                return (
                  <div key={c.label} className="p-3 rounded-md bg-aisle/60 border border-rail space-y-0.5">
                    <div className="text-[11px] font-mono uppercase tracking-wider text-gray-400">{c.label}</div>
                    <div className={`text-xl font-bold font-mono ${v30 ? "text-beam-300" : "text-gray-500"}`}>{v30.toLocaleString()}</div>
                    <div className="text-[11px] font-mono text-gray-500">{v7.toLocaleString()} this week</div>
                    <Sparkline values={trendFor(trafficSources, c.hosts)} />
                  </div>
                );
              })}
            </div>
            <div className="space-y-2">
              <div className="text-xs font-mono text-gray-400">All sources, visitors first seen in the last 30 days (7d in brackets)</div>
              <RankedList
                rows={trafficSources.sources.map((s) => ({ key: `${s.source} (${s.visitors_7d.toLocaleString()} in 7d)`, count: s.visitors_30d }))}
                empty="No visitors in 30 days." unit="visitors" />
            </div>
            <p className="text-xs font-mono text-gray-400">
              Instagram and TikTok in-app browsers often hide the referrer, so some of them sit in (direct). Read the channel tiles as a floor.
              Sparklines show new visitors per rolling 7 days over the last 8 weeks, newest on the right; after 8 weeks double the time on the top source and cut the weakest.
            </p>
          </>
        )}
      </Section>

      <Section icon={<Download className="w-5 h-5 text-beam-400" />} title="Downloads">
        <Grid>
          <Stat label="Site downloads (acquisition)" value={num(db?.website.downloads_total)} tone="text-beam-300"
            def={`Clicks logged before the site moved to store links. 24h ${num(db?.website.downloads_24h)} · 7d ${num(db?.website.downloads_7d)} · 30d ${num(db?.website.downloads_30d)}.`} />
          <PlatformBreakdown counts={db?.website.downloads_by_platform ?? null} />
        </Grid>
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
          <Stat label="Database size" value={bytes(db?.storage.db_bytes)} href={consoleLinks.supabaseDatabase}
            def={
              derived.dbCapBytes && db ? (
                <>
                  pg_database_size,{" "}
                  <span className={`text-sm font-bold ${capTone(db.storage.db_bytes / derived.dbCapBytes)}`}>
                    {Math.round((db.storage.db_bytes / derived.dbCapBytes) * 100)}%
                  </span>{" "}
                  of your {formatBytes(derived.dbCapBytes)} plan limit.
                </>
              ) : (
                "pg_database_size. Set SUPABASE_DB_CAP_BYTES to see it against your plan."
              )
            } />
          <Stat label="R2: room media" value={bytes(db?.storage.active_room_media_bytes)} def="Rooms whose shared upload is ready. What the DB references, not a bucket listing." />
          <Stat label="R2: staged uploads" value={bytes(db?.storage.staged_ready_bytes)} def="Ready lobby pre-uploads not yet claimed by a room." />
          <Stat label="R2: queued deletions" value={num(db?.storage.pending_r2_deletions)} def="Objects in pending_r2_deletions. The queue records no sizes." />
          <R2BucketStat r2={metrics.r2} referencedBytes={db ? db.storage.active_room_media_bytes + db.storage.staged_ready_bytes : null} />
        </Grid>
      </Section>
    </div>
  );
}
