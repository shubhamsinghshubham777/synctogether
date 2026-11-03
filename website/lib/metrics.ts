import { createProductionMetricsClient } from "@/lib/supabase/admin";
import {
  computeMrr,
  parseR2Metrics,
  type R2Usage,
  DEFAULT_INR_PER_USD,
  percent,
  type MrrSummary,
  type WebRevenueRow,
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
    web_active: number;
    web_past_due: number;
    web_canceling: number;
    web_unpriced: number;
    web_by_provider: Record<string, number>;
    manual_or_debug: number;
    apple_production: number;
    apple_sandbox: number;
    web_revenue: WebRevenueRow[];
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

/** One row of `public.internal_traffic_sources()`; first-time visitors by referrer host. */
export interface TrafficSource {
  source: string;
  visitors_7d: number;
  visitors_30d: number;
}

/** Result of `public.internal_traffic_sources()`. */
export interface TrafficSources {
  sources: TrafficSource[];
  /** New visitors per source in rolling 7-day buckets; age 0 = last 7 days, 7 = oldest. */
  weekly: { source: string; age: number; visitors: number }[];
}

export interface DashboardMetrics {
  timestamp: string;
  source: {
    host: string;
    projectRef: string | null;
    /** Whether the `internal_metrics` RPC answered. */
    supabaseConnected: boolean;
    /** Round trip of the RPC alone. */
    rpcLatencyMs: number | null;
    rpcError: string | null;
  };
  /** Null when the RPC failed. */
  db: InternalMetricsRpc | null;
  /** Null when its RPC failed (e.g. the migration is not applied yet). */
  trafficSources: TrafficSources | null;
  /**
   * Cloudflare's own R2 figures. `configured` is false when no Cloudflare token
   * is set (the card says how to enable it); `usage` is null when configured
   * but the call failed.
   */
  r2: { configured: boolean; usage: R2Usage | null; error: string | null };
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
    /** Supabase's Database Report: database size over time. */
    supabaseDatabase: string;
    livekitConsole: string;
    cloudflareR2: string;
    posthog: string;
  };
}

function positiveEnvNumber(name: string): number | null {
  const n = Number(process.env[name]);
  return Number.isFinite(n) && n > 0 ? n : null;
}

/** Needs a token with "Workers R2 Storage: Read" and the account id; both optional. */
async function getR2Usage(): Promise<DashboardMetrics["r2"]> {
  const account = process.env.CLOUDFLARE_ACCOUNT_ID;
  const token = process.env.CLOUDFLARE_API_TOKEN;
  if (!account || !token) return { configured: false, usage: null, error: null };
  try {
    const res = await fetch(`https://api.cloudflare.com/client/v4/accounts/${encodeURIComponent(account)}/r2/metrics`, {
      headers: { Authorization: `Bearer ${token}` },
      signal: AbortSignal.timeout(8000),
      cache: "no-store",
    });
    const body: unknown = await res.json().catch(() => null);
    const usage = res.ok ? parseR2Metrics(body) : null;
    if (usage) return { configured: true, usage, error: null };
    const msg = (body as { errors?: { message?: string }[] } | null)?.errors?.[0]?.message;
    return { configured: true, usage: null, error: msg ?? `HTTP ${res.status}` };
  } catch (err) {
    return { configured: true, usage: null, error: err instanceof Error ? err.message : String(err) };
  }
}

export async function getDashboardMetrics(): Promise<DashboardMetrics> {
  const { client: supabase, host } = createProductionMetricsClient();

  const rpcStart = Date.now();
  const rpcPromise = supabase.rpc("internal_metrics").then(
    (res) => ({ res, ms: Date.now() - rpcStart }),
    (error: unknown) => ({ res: { data: null, error }, ms: Date.now() - rpcStart })
  );
  const sourcesPromise = supabase.rpc("internal_traffic_sources").then(
    (r) => r,
    (error: unknown) => ({ data: null, error })
  );
  const [{ res, ms }, sourcesRes, r2] = await Promise.all([rpcPromise, sourcesPromise, getR2Usage()]);
  if (r2.error) console.error("R2 metrics failed:", r2.error);
  if (sourcesRes.error) console.error("internal_traffic_sources RPC failed:", sourcesRes.error);
  const trafficSources = sourcesRes.error ? null : ((sourcesRes.data as TrafficSources | null) ?? null);

  const rpcError = res.error
    ? res.error instanceof Error
      ? res.error.message
      : String((res.error as { message?: string }).message ?? res.error)
    : null;
  if (rpcError) console.error("internal_metrics RPC failed:", rpcError);
  const db = rpcError ? null : ((res.data as InternalMetricsRpc | null) ?? null);

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
    db,
    trafficSources,
    r2,
    derived: {
      mrr: db ? computeMrr(db.subscriptions.web_revenue, inrPerUsd) : null,
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
      supabaseDatabase: projectRef
        ? `https://supabase.com/dashboard/project/${projectRef}/observability/database`
        : "https://supabase.com/dashboard",
      livekitConsole: "https://cloud.livekit.io/projects",
      cloudflareR2: "https://dash.cloudflare.com/?to=/:account/r2/overview",
      posthog: process.env.POSTHOG_PROJECT_URL || "https://app.posthog.com",
    },
  };
}
