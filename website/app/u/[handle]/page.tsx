import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { formatPoints, getProfileCard } from "@/lib/rewards";
import { SITE_CONFIG } from "@/lib/constants";
import { PublicAvatar } from "@/components/rewards/PublicAvatar";
import { StatTile } from "@/components/rewards/StatTile";
import { BadgeTile } from "@/components/rewards/BadgeTile";
import { SeasonTicket } from "@/components/rewards/SeasonTicket";
import { PTButton } from "@/components/PTButton";
import { Kicker, Headline, display, mono } from "@/components/booth/Booth";

export const revalidate = 3600;

/**
 * A public profile card.
 *
 * `public_profile_card` returns nothing at all for an account that has not
 * opted in, which is why this 404s rather than rendering an empty page: the
 * absence has to be indistinguishable from "no such handle", or the page itself
 * becomes a way to confirm that a given handle belongs to somebody.
 */
export async function generateMetadata({
  params,
}: {
  params: Promise<{ handle: string }>;
}): Promise<Metadata> {
  const { handle } = await params;
  const card = await getProfileCard(handle);
  if (!card) {
    return { title: "Profile not found", robots: { index: false, follow: false } };
  }
  const title = `${card.name} on ${SITE_CONFIG.name}`;
  const description =
    `${card.streak}-day streak · ${card.hours}h watched together · ` +
    `${card.badges.length} badge${card.badges.length === 1 ? "" : "s"}.`;
  return {
    title,
    description,
    alternates: { canonical: `${SITE_CONFIG.url}/u/${card.handle}` },
    openGraph: {
      title,
      description,
      type: "profile",
      url: `${SITE_CONFIG.url}/u/${card.handle}`,
    },
    twitter: { card: "summary_large_image", title, description },
  };
}

export default async function ProfilePage({
  params,
}: {
  params: Promise<{ handle: string }>;
}) {
  const { handle } = await params;
  const card = await getProfileCard(handle);
  if (!card) notFound();

  return (
    <div className="px-4 sm:px-6 lg:px-8 max-w-4xl mx-auto pt-8 pb-12 md:pt-12 md:pb-16 space-y-10">
      <header className="flex items-center gap-5 sm:gap-6 min-w-0">
        <PublicAvatar
          seed={card.handle}
          name={card.name}
          avatar={card.avatar}
          frame={card.frame}
          size={80}
        />
        <div className="min-w-0 space-y-2">
          <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
            <Headline className="text-[clamp(2.5rem,7vw,4rem)] break-words line-in">{card.name}</Headline>
            {card.premium && (
              <span className={`${mono} rounded-[4px] border border-brass/60 px-2 py-0.5 text-[10px] tracking-[0.14em] text-brass`}>
                ★ PATRON
              </span>
            )}
          </div>
          <p className={`${mono} text-xs text-gray-400 truncate`}>
            @{card.handle} · watching since {monthYear(card.joined)}
          </p>
        </div>
      </header>

      <section className="grid grid-cols-2 rounded-md bg-seat ring-1 ring-inset ring-rail" aria-label="Streak">
        <div className="px-5 py-5 sm:px-6 sm:py-6 min-w-0">
          <p className={`${mono} text-[11px] tracking-[0.14em] text-signal`}>CURRENT STREAK</p>
          <p className="mt-3 flex items-baseline gap-2">
            <svg width="34" height="34" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" className="text-signal self-center shrink-0">
              <path d="M12 21c4 0 7-3 7-7 0-5-5-7-5-11-3 2-5 5-4 8-2-1-3-3-3-3-1 2-2 4-2 6 0 4 3 7 7 7z" />
            </svg>
            <span className={`${display} text-[clamp(2.5rem,7vw,3.75rem)] leading-none font-extrabold tracking-[-0.04em] text-signal tabular-nums`}>
              {card.streak}
            </span>
            <span className="text-base text-gray-300">days</span>
          </p>
        </div>
        <div className="px-5 py-5 sm:px-6 sm:py-6 border-l border-rail min-w-0">
          <p className={`${mono} text-[11px] tracking-[0.14em] text-gray-500`}>BEST RUN</p>
          <p className="mt-3 flex items-baseline gap-2">
            <span className={`${display} text-[clamp(2.5rem,7vw,3.75rem)] leading-none font-extrabold tracking-[-0.04em] text-white tabular-nums`}>
              {card.longest_streak}
            </span>
            <span className="text-base text-gray-300">days</span>
          </p>
        </div>
      </section>

      <div className="grid grid-cols-3 gap-x-4 sm:gap-x-6">
        <StatTile value={`${card.hours}h`} label="watched" />
        <StatTile value={`${card.co_watchers}`} label="watched with" />
        <StatTile value={formatPoints(card.points_week)} label="points this week" accent="text-beam-500" />
      </div>

      {card.seasons?.length > 0 && (
        <section className="space-y-4">
          <Kicker tone="muted">Seasons</Kicker>
          <div className="flex flex-wrap gap-4">
            {card.seasons.map((award) => (
              <SeasonTicket key={award.season} season={award.season} rank={award.rank} />
            ))}
          </div>
        </section>
      )}

      {card.badges.length > 0 && (
        <section className="space-y-4">
          <Kicker tone="muted">Badges</Kicker>
          <div className="flex flex-wrap gap-x-3 gap-y-5">
            {card.badges.map((badge) => (
              <BadgeTile key={badge.id} title={badge.title} grade={badge.grade} />
            ))}
          </div>
        </section>
      )}

      <section className="border-t border-rail pt-12 grid md:grid-cols-[1fr_auto] gap-8 items-end">
        <div className="space-y-4 max-w-xl">
          <Kicker tone="muted">Start one of your own</Kicker>
          <Headline as="h2" className="text-3xl sm:text-4xl">Movie night, same second.</Headline>
          <p className="text-gray-400 leading-relaxed">
            Streaks count days you actually watched something with someone. Start one. It is free.
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-x-6 gap-y-3">
          <PTButton href="/download" size="lg">
            Get {SITE_CONFIG.name}
          </PTButton>
          <Link
            href="/leaderboard"
            className="text-[15px] font-semibold text-white underline underline-offset-[6px] decoration-rail hover:decoration-beam-500 transition-colors"
          >
            See the leaderboard
          </Link>
        </div>
      </section>
    </div>
  );
}

/** "2026-05-29" -> "May 2026", the board's form; anything unparseable passes through. */
function monthYear(iso: string) {
  const d = new Date(`${iso}T00:00:00Z`);
  return Number.isNaN(d.getTime()) ? iso : d.toLocaleDateString("en-GB", { month: "short", year: "numeric", timeZone: "UTC" });
}
