/**
 * The internal dashboard's arithmetic, as pure functions over plain values so
 * it can be tested without Supabase, GitHub or a clock - the same seam
 * `lib/billing/core.ts` uses. Every function answers `null` rather than a number
 * when its inputs cannot support one: the dashboard renders null as
 * "unavailable", and a missing figure is better than a fabricated one.
 */

export function formatBytes(bytes: number, decimals = 2): string {
  if (!bytes || bytes <= 0) return "0 B";
  const k = 1024;
  const sizes = ["B", "KB", "MB", "GB", "TB"];
  const i = Math.min(sizes.length - 1, Math.floor(Math.log(bytes) / Math.log(k)));
  return `${parseFloat((bytes / Math.pow(k, i)).toFixed(Math.max(0, decimals)))} ${sizes[i]}`;
}

/** `num / den` as a percentage to one decimal, or null when undefined. */
export function percent(num: number | null | undefined, den: number | null | undefined): number | null {
  if (num == null || den == null || den <= 0) return null;
  return Math.round((num / den) * 1000) / 10;
}

/**
 * Fixed INR -> USD rate for the USD-equivalent MRR line. Deliberately a
 * constant rather than a live FX feed: the figure is for trend-reading, and a
 * rate that moves under it would move the line for reasons that have nothing
 * to do with the business. Override with METRICS_INR_PER_USD.
 */
export const DEFAULT_INR_PER_USD = 88;

/** Provider amounts are in the lowest denomination; these have no minor unit. */
const ZERO_DECIMAL = new Set(["JPY", "KRW"]);

export interface WebRevenueRow {
  currency: string;
  interval: string;
  frequency: number | null;
  subscribers: number;
  unit_amount_sum: number;
}

/** Months covered by one charge, or null for an interval we do not model. */
export function monthsPerCycle(interval: string, frequency: number | null): number | null {
  const f = frequency && frequency > 0 ? frequency : 1;
  switch (interval) {
    case "month":
      return f;
    case "year":
      return 12 * f;
    case "week":
      return (f * 12) / 52;
    case "day":
      return (f * 12) / 365;
    default:
      return null;
  }
}

export interface MrrSummary {
  /** Monthly recurring revenue per currency, in major units (e.g. 3.99). */
  byCurrency: { currency: string; monthly: number; subscribers: number }[];
  /** USD + INR (at the fixed rate) in USD, or null when neither is present. */
  usdEquivalent: number | null;
  /** Subscribers in currencies not folded into `usdEquivalent`. */
  unconvertedSubscribers: number;
}

/**
 * MRR from the RPC's grouped web-billing rows: each group's recurring charge
 * normalised to a month (annual / 12). Only USD and INR are folded into the
 * USD-equivalent total - those are the currencies the product is priced in;
 * anything else is listed natively and counted as unconverted, never guessed.
 */
export function computeMrr(rows: WebRevenueRow[], inrPerUsd = DEFAULT_INR_PER_USD): MrrSummary {
  const per = new Map<string, { monthly: number; subscribers: number }>();
  for (const r of rows) {
    const months = monthsPerCycle(r.interval, r.frequency);
    if (months == null) continue;
    const major = r.unit_amount_sum / (ZERO_DECIMAL.has(r.currency) ? 1 : 100);
    const cur = per.get(r.currency) ?? { monthly: 0, subscribers: 0 };
    cur.monthly += major / months;
    cur.subscribers += r.subscribers;
    per.set(r.currency, cur);
  }

  const byCurrency = [...per.entries()]
    .map(([currency, v]) => ({ currency, monthly: Math.round(v.monthly * 100) / 100, subscribers: v.subscribers }))
    .sort((a, b) => b.subscribers - a.subscribers);

  const usd = per.get("USD");
  const inr = per.get("INR");
  const usdEquivalent =
    usd || inr
      ? Math.round(((usd?.monthly ?? 0) + (inr ? inr.monthly / inrPerUsd : 0)) * 100) / 100
      : null;
  const unconvertedSubscribers = byCurrency
    .filter((c) => c.currency !== "USD" && c.currency !== "INR")
    .reduce((n, c) => n + c.subscribers, 0);

  return { byCurrency, usdEquivalent, unconvertedSubscribers };
}
