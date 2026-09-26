import { createProductionMetricsClient } from "@/lib/supabase/admin";
import {
  computeMrr,
  DEFAULT_INR_PER_USD,
  percent,
  summariseReleaseFetches,
  type MrrSummary,
  type PaddleRevenueRow,
  type ReleaseAssetCounts,
} from "@/lib/metrics_logic";

/**
 * Data for /internal/metrics. Everything countable comes from one
 * `internal_metrics()` RPC: fetching rows and counting them in JS was capped
 * at PostgREST's max_rows (1000) and silently stopped growing. Definitions of
 * each figure live beside its SQL in `…_internal_metrics.sql`.
 *
 * Any source that fails is `null`, and the page renders "unavailable". There
 * are no estimates and no hard-coded statuses anywhere in here.
 */

/** Shape returned by `public.internal_metrics()`. */
export interface InternalMetricsRpc {
  accounts: { total_profiles: number; guests: number; registered: number; premium: number; free: number };
  signups: { last_24h: number; last_7d: number; last_30d: number };
  activity: { dau: number; wau: number; mau: number; dau_by_tier: { premium: number; free: number; guest: number } };
  subscriptions: {
    paddle_active: number;
    paddle_past_due: number;
    paddle_canceling: number;
    paddle_unpriced: number;
    manual_or_debug: number;
    apple_production: number;
    apple_sandbox: number;
    paddle_revenue: PaddleRevenueRow[];
  };
  rooms: {
    total: number;
    last_7d: number;
    last_30d: number;
    live_now: number;
    media_kind: Record<string, number>;
    messages_total: number;
    member_rows_in_live_rooms: number;
  };
  website: {
    visitors_total: number;
    visitors_24h: number;
    visitors_7d: number;
    visitors_30d: number;
    single_page_visitors: number;
    pageviews_total: number;
    visitors_who_downloaded: number;
    downloads_total: number;
    downloads_24h: number;
    downloads_7d: number;
    downloads_30d: number;
    downloads_by_platform: Record<string, number>;
    top_paths_30d: { path: string; count: number }[];
    top_referrers_30d: { source: string; count: number }[];
  };
  storage: {
    db_bytes: number;
    active_room_media_bytes: number;
    staged_ready_bytes: number;
    pending_r2_deletions: number;
  };
}

export interface GithubFetches {
  total: number;
  mac: number;
  win: number;
  releases: ReturnType<typeof summariseReleaseFetches>["releases"];
}

export interface DashboardMetrics {
  timestamp: string;
  source: {
    host: string;
    projectRef: string | null;
    /** Whether the `internal_metrics` RPC answered. */
    supabaseConnected: boolean;
    /** Round trip of the RPC alone, not the GitHub fetch. */
    rpcLatencyMs: number | null;
    rpcError: string | null;
  };
  latestAppVersion: string | null;
  /** Null when the RPC failed. */
  db: InternalMetricsRpc | null;
  /** Null when GitHub could not be reached. */
  github: GithubFetches | null;
  derived: {
    mrr: MrrSummary | null;
    inrPerUsd: number;
    /** premium / MAU: share of active users who pay. */
    payingOfActivePercent: number | null;
    /** visitors_who_downloaded / visitors_total, one cookie population. */
    visitorToDownloadPercent: number | null;
    /** Lifetime single-page cookies / all cookies. Not a session bounce rate. */
    singlePageVisitorPercent: number | null;
    productStickinessPercent: number | null;
    websiteStickinessPercent: number | null;
    /** Configured plan cap, or null when SUPABASE_DB_CAP_BYTES is unset. */
    dbCapBytes: number | null;
  };
  consoleLinks: {
    supabaseUsage: string;
    livekitConsole: string;
    cloudflareR2: string;
    posthog: string;
  };
}

const GITHUB_RELEASES = "https://api.github.com/repos/shubhamsinghshubham777/synctogether/releases";

/**
 * Every release including pre-releases (their binaries are fetched too), all
 * pages, uncached. Unlike `getAllReleases`, which answers `[]` on failure for
 * the changelog's sake, a failure here is `null` - zero downloads and "GitHub
 * did not answer" must not look the same.
 */
async function fetchAllReleases(): Promise<ReleaseAssetCounts[] | null> {
  try {
    const all: ReleaseAssetCounts[] = [];
    for (let page = 1; page <= 10; page++) {
      const res = await fetch(`${GITHUB_RELEASES}?per_page=100&page=${page}`, {
        cache: "no-store",
        headers: { Accept: "application/vnd.github.v3+json", "User-Agent": "SyncTogether-Website" },
      });
      if (!res.ok) return null;
      const batch = (await res.json()) as (ReleaseAssetCounts & { draft?: boolean })[];
      all.push(...batch.filter((r) => !r.draft));
      if (batch.length < 100) break;
    }
    return all;
  } catch (err) {
    console.error("GitHub releases fetch failed:", err);
    return null;
  }
}

function positiveEnvNumber(name: string): number | null {
  const n = Number(process.env[name]);
  return Number.isFinite(n) && n > 0 ? n : null;
}

export async function getDashboardMetrics(): Promise<DashboardMetrics> {
  const { client: supabase, host } = createProductionMetricsClient();

  const rpcStart = Date.now();
  const rpcPromise = supabase.rpc("internal_metrics").then(
    (res) => ({ res, ms: Date.now() - rpcStart }),
    (error: unknown) => ({ res: { data: null, error }, ms: Date.now() - rpcStart })
  );
  const [{ res, ms }, releases] = await Promise.all([rpcPromise, fetchAllReleases()]);

  const rpcError = res.error
    ? res.error instanceof Error
      ? res.error.message
      : String((res.error as { message?: string }).message ?? res.error)
    : null;
  if (rpcError) console.error("internal_metrics RPC failed:", rpcError);
  const db = rpcError ? null : ((res.data as InternalMetricsRpc | null) ?? null);

  const github = releases ? summariseReleaseFetches(releases) : null;
  const latestStable = releases?.find((r) => !r.prerelease);
  const latestAppVersion = latestStable
    ? (latestStable.name || latestStable.tag_name).replace(/^v/, "").replace(/_\d+$/, "")
    : null;

  const inrPerUsd = positiveEnvNumber("METRICS_INR_PER_USD") ?? DEFAULT_INR_PER_USD;
  const projectRef = host.endsWith(".supabase.co") ? host.split(".")[0] : null;

  return {
    timestamp: new Date().toISOString(),
    source: {
      host,
      projectRef,
      supabaseConnected: db !== null,
      rpcLatencyMs: db ? ms : null,
      rpcError,
    },
    latestAppVersion,
    db,
    github,
    derived: {
      mrr: db ? computeMrr(db.subscriptions.paddle_revenue, inrPerUsd) : null,
      inrPerUsd,
      payingOfActivePercent: db ? percent(db.accounts.premium, db.activity.mau) : null,
      visitorToDownloadPercent: db ? percent(db.website.visitors_who_downloaded, db.website.visitors_total) : null,
      singlePageVisitorPercent: db ? percent(db.website.single_page_visitors, db.website.visitors_total) : null,
      productStickinessPercent: db ? percent(db.activity.dau, db.activity.mau) : null,
      websiteStickinessPercent: db ? percent(db.website.visitors_24h, db.website.visitors_30d) : null,
      dbCapBytes: positiveEnvNumber("SUPABASE_DB_CAP_BYTES"),
    },
    consoleLinks: {
      supabaseUsage: projectRef
        ? `https://supabase.com/dashboard/project/${projectRef}/settings/billing/usage`
        : "https://supabase.com/dashboard",
      livekitConsole: "https://cloud.livekit.io/projects",
      cloudflareR2: "https://dash.cloudflare.com/?to=/:account/r2/overview",
      posthog: process.env.POSTHOG_PROJECT_URL || "https://app.posthog.com",
    },
  };
}
