import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { formatPoints, formatWatchTime, getWrapped } from "@/lib/rewards";
import { SITE_CONFIG } from "@/lib/constants";
import { PublicAvatar } from "@/components/rewards/PublicAvatar";
import { StatTile } from "@/components/rewards/StatTile";
import { BadgeTile } from "@/components/rewards/BadgeTile";
import { Ticket } from "@/components/Ticket";
import { PTButton } from "@/components/PTButton";
import { Kicker, Headline, display, mono } from "@/components/booth/Booth";

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
    <div className="px-4 sm:px-6 lg:px-8 max-w-6xl mx-auto pt-8 pb-12 md:pt-12 md:pb-16 space-y-10">
      <header className="space-y-8">
        <div className="flex items-center gap-4">
          <PublicAvatar seed={card.handle} name={card.name} avatar={card.avatar} size={56} />
          <div className="min-w-0">
            <Kicker>{card.year} · the season in review</Kicker>
          </div>
        </div>
        <div className="relative">
          <span
            aria-hidden="true"
            className={`${display} pointer-events-none select-none absolute -top-6 sm:-top-10 right-0 font-extrabold text-[clamp(6rem,22vw,16rem)] leading-none tracking-[-0.06em] text-seat`}
          >
            {card.year}
          </span>
          <Headline className="relative text-[clamp(2.75rem,9vw,6.5rem)] max-w-4xl break-words">
            <span className="line-in">{card.name} watched</span>
            <span className="line-in [animation-delay:90ms] text-beam-500">together.</span>
          </Headline>
        </div>
        <p className="text-lg sm:text-xl text-gray-400 leading-relaxed max-w-xl">
          Across {card.days} different days, {card.name} watched things with people
          instead of alone: {formatWatchTime(card.seconds)} in all.
        </p>
      </header>

      <div className="grid grid-cols-3 gap-x-4 sm:gap-x-6">
        <StatTile value={`${card.days}`} label="days watching" />
        <StatTile value={`${card.longest_streak}`} label="longest streak" accent="text-signal" />
        <StatTile value={formatPoints(card.points)} label="points" />
      </div>

      <div className="grid lg:grid-cols-[1.2fr_1fr] gap-14">
        {card.top_co_watchers.length > 0 && (
          <section className="space-y-5">
            <Kicker tone="muted">The people who showed up</Kicker>
            <ol className="border-t border-rail">
              {card.top_co_watchers.map((person, i) => (
                <li key={`${person.seed}-${i}`} className="flex items-center gap-4 py-4 border-b border-aisle">
                  <span className={`${mono} w-6 text-sm text-gray-500`}>{String(i + 1).padStart(2, "0")}</span>
                  <PublicAvatar seed={person.seed} name={person.name} avatar={person.avatar} size={36} />
                  <span className={`flex-1 min-w-0 truncate ${person.name ? "text-white font-semibold" : "text-gray-500 italic"}`}>
                    {person.name ?? "A friend"}
                  </span>
                  <span className={`${mono} text-sm text-white tabular-nums`}>{person.hours}h</span>
                </li>
              ))}
            </ol>
          </section>
        )}

        {card.badges.length > 0 && (
          <section className="space-y-5">
            <Kicker tone="muted">Earned in {card.year}</Kicker>
            <div className="flex flex-wrap gap-x-3 gap-y-5">
              {card.badges.map((badge) => (
                <BadgeTile key={badge.id} title={badge.title} grade={badge.grade} />
              ))}
            </div>
          </section>
        )}
      </div>

      <section className="max-w-3xl space-y-8">
        <Link href="/download" className="block rounded-md focus-visible:outline-2 focus-visible:outline-beam-500">
          <Ticket
            stub={
              <span className={`${mono} text-base sm:text-xl font-semibold tracking-[0.1em]`}>{card.year + 1}</span>
            }
          >
            <p className={`${mono} text-[11px] tracking-[0.16em] text-[#A33A22]`}>NEXT SEASON</p>
            <p className={`${display} mt-2 text-3xl sm:text-4xl font-extrabold tracking-[-0.04em] leading-[0.95]`}>
              Your turn next year.
            </p>
            <p className={`${mono} mt-2 text-xs text-[#5A4F44]`}>{SITE_CONFIG.url.replace(/^https?:\/\//, "")}/download</p>
          </Ticket>
        </Link>
        <PTButton href="/download" size="lg">
          Get {SITE_CONFIG.name}
        </PTButton>
      </section>
    </div>
  );
}
