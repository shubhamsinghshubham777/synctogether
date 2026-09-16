import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { formatPoints, formatWatchTime, getWrapped } from "@/lib/rewards";
import { SITE_CONFIG } from "@/lib/constants";
import { PublicAvatar } from "@/components/rewards/PublicAvatar";
import { StatTile } from "@/components/rewards/StatTile";
import { BadgeChip } from "@/components/rewards/BadgeChip";

export const revalidate = 3600;

/**
 * The year in one page.
 *
 * Built from the same ledger the board reads, so by the time this ships there is
 * nothing new to collect - it is a rendering job, not a data job. Year comes from
 * the query string so last year's card stays linkable after the calendar turns.
 */
export async function generateMetadata({
  params,
  searchParams,
}: {
  params: Promise<{ handle: string }>;
  searchParams: Promise<{ year?: string }>;
}): Promise<Metadata> {
  const [{ handle }, { year }] = await Promise.all([params, searchParams]);
  const card = await getWrapped(handle, resolveYear(year));
  if (!card) {
    return { title: "Wrapped not found", robots: { index: false, follow: false } };
  }
  const title = `${card.name}'s ${card.year} on ${SITE_CONFIG.name}`;
  const description = `${formatWatchTime(card.seconds)} watched together across ${card.days} days.`;
  return {
    title,
    description,
    openGraph: { title, description, type: "article" },
    twitter: { card: "summary_large_image", title, description },
  };
}

function resolveYear(raw?: string): number {
  const parsed = Number.parseInt(raw ?? "", 10);
  const current = new Date().getUTCFullYear();
  if (!Number.isFinite(parsed) || parsed < 2025 || parsed > current) return current;
  return parsed;
}

export default async function WrappedPage({
  params,
  searchParams,
}: {
  params: Promise<{ handle: string }>;
  searchParams: Promise<{ year?: string }>;
}) {
  const [{ handle }, { year }] = await Promise.all([params, searchParams]);
  const card = await getWrapped(handle, resolveYear(year));
  if (!card) notFound();

  return (
    <div className="relative py-12 md:py-20 px-4 sm:px-6 lg:px-8 max-w-2xl mx-auto space-y-10">
      <div className="glow-blob-purple top-6 left-1/2 -translate-x-1/2 opacity-30" />

      <header className="text-center space-y-4">
        <p className="text-xs uppercase tracking-[0.24em] text-[var(--pt-text-accent)]">
          {card.year} wrapped
        </p>
        <div className="flex justify-center">
          <PublicAvatar seed={card.handle} name={card.name} avatar={card.avatar} size={72} />
        </div>
        <h1 className="text-3xl sm:text-5xl font-extrabold text-white tracking-tight font-[family-name:var(--font-space-grotesk)]">
          {formatWatchTime(card.seconds)}{" "}
          <span className="text-gradient-brand">together</span>.
        </h1>
        <p className="text-gray-300">
          Across {card.days} different days, {card.name} watched things with people
          instead of alone.
        </p>
      </header>

      <div className="grid grid-cols-3 gap-3">
        <StatTile value={`${card.days}`} label="days watching" />
        <StatTile
          value={`${card.longest_streak}`}
          label="longest streak"
          accent="text-[#FB923C]"
        />
        <StatTile
          value={formatPoints(card.points)}
          label="points"
          accent="text-[var(--pt-text-accent)]"
        />
      </div>

      {card.top_co_watchers.length > 0 && (
        <section className="space-y-4">
          <h2 className="text-sm uppercase tracking-[0.16em] text-gray-400">
            The people who showed up
          </h2>
          <div className="space-y-3">
            {card.top_co_watchers.map((person, i) => (
              <div
                key={`${person.seed}-${i}`}
                className="glass-panel rounded-xl px-5 py-4 flex items-center gap-4"
              >
                <PublicAvatar seed={person.seed} name={person.name} avatar={person.avatar} size={36} />
                <span className={`flex-1 ${person.name ? "text-white" : "text-gray-500 italic"}`}>
                  {person.name ?? "A friend"}
                </span>
                <span className="font-[family-name:var(--font-jetbrains-mono)] text-sm text-gray-400">
                  {person.hours}h
                </span>
              </div>
            ))}
          </div>
        </section>
      )}

      {card.badges.length > 0 && (
        <section className="space-y-4">
          <h2 className="text-sm uppercase tracking-[0.16em] text-gray-400">
            Earned in {card.year}
          </h2>
          <div className="flex flex-wrap gap-2.5">
            {card.badges.map((badge) => (
              <BadgeChip key={badge.id} title={badge.title} grade={badge.grade} />
            ))}
          </div>
        </section>
      )}

      <div className="glass-panel rounded-2xl px-6 py-7 text-center space-y-4">
        <p className="text-lg font-semibold text-white">Your turn next year.</p>
        <Link
          href="/download"
          className="btn-primary-gradient inline-block px-6 py-3 rounded-xl font-semibold text-white"
        >
          Get {SITE_CONFIG.name}
        </Link>
      </div>
    </div>
  );
}
