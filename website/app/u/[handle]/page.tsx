import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import {
  formatPoints,
  getProfileCard,
  seasonMonthLabel,
  seasonRankLabel,
} from "@/lib/rewards";
import { SITE_CONFIG } from "@/lib/constants";
import { PublicAvatar } from "@/components/rewards/PublicAvatar";
import { StatTile } from "@/components/rewards/StatTile";
import { BadgeChip } from "@/components/rewards/BadgeChip";

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
    <div className="relative py-12 md:py-20 px-4 sm:px-6 lg:px-8 max-w-2xl mx-auto space-y-10">
      <div className="glow-blob-purple top-6 left-1/2 -translate-x-1/2 opacity-30" />

      <header className="flex flex-col sm:flex-row items-center gap-5 text-center sm:text-left">
        <PublicAvatar
          seed={card.handle}
          name={card.name}
          avatar={card.avatar}
          frame={card.frame}
          size={84}
        />
        <div className="space-y-1">
          <h1 className="text-3xl font-extrabold text-white tracking-tight font-[family-name:var(--font-space-grotesk)]">
            {card.name}
            {card.premium && (
              <span className="ml-2 align-middle text-sm text-[var(--pt-premium)]">★</span>
            )}
          </h1>
          <p className="font-[family-name:var(--font-jetbrains-mono)] text-sm text-gray-400">
            @{card.handle}
          </p>
          <p className="text-xs text-gray-500">Watching together since {card.joined}</p>
        </div>
      </header>

      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
        <StatTile
          value={`${card.streak}`}
          label="day streak"
          accent="text-[#FB923C]"
        />
        <StatTile value={`${card.hours}h`} label="watched" />
        <StatTile value={`${card.co_watchers}`} label="watched with" />
        <StatTile
          value={formatPoints(card.points_week)}
          label="points this week"
          accent="text-[var(--pt-text-accent)]"
        />
      </div>

      {card.seasons?.length > 0 && (
        <section className="space-y-4">
          <h2 className="text-sm uppercase tracking-[0.16em] text-gray-400">Seasons</h2>
          <div className="flex flex-wrap gap-2.5">
            {card.seasons.map((award) => {
              const color =
                award.rank === 1 ? "#FBBF24" : award.rank === 2 ? "#CBD5E1" : "#D08C60";
              return (
                <span
                  key={award.season}
                  title={seasonRankLabel(award.rank)}
                  className="inline-flex items-center gap-2 rounded-full px-3 py-1.5 text-xs font-semibold"
                  style={{ color, background: `${color}1F`, border: `1px solid ${color}73` }}
                >
                  #{award.rank} · {seasonMonthLabel(award.season)}
                </span>
              );
            })}
          </div>
        </section>
      )}

      {card.badges.length > 0 && (
        <section className="space-y-4">
          <h2 className="text-sm uppercase tracking-[0.16em] text-gray-400">Badges</h2>
          <div className="flex flex-wrap gap-2.5">
            {card.badges.map((badge) => (
              <BadgeChip key={badge.id} title={badge.title} grade={badge.grade} />
            ))}
          </div>
        </section>
      )}

      <div className="glass-panel rounded-2xl px-6 py-7 text-center space-y-4">
        <p className="text-lg font-semibold text-white">
          Longest streak: {card.longest_streak} days
        </p>
        <p className="text-sm text-gray-300">
          Streaks count days you actually watched something with someone. Start one -
          it is free.
        </p>
        <div className="flex flex-col sm:flex-row gap-3 justify-center">
          <Link
            href="/download"
            className="btn-primary-gradient px-6 py-3 rounded-xl font-semibold text-white"
          >
            Get {SITE_CONFIG.name}
          </Link>
          <Link
            href="/leaderboard"
            className="px-6 py-3 rounded-xl font-semibold text-gray-200 border border-white/10 hover:border-white/25 transition-colors"
          >
            See the leaderboard
          </Link>
        </div>
      </div>
    </div>
  );
}
