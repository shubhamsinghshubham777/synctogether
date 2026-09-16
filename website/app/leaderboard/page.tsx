import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import { formatPoints, getPublicBoard } from "@/lib/rewards";
import { SITE_CONFIG } from "@/lib/constants";
import { PublicAvatar } from "@/components/rewards/PublicAvatar";

export const revalidate = 300;

export const metadata: Metadata = {
  title: "Leaderboard",
  description:
    "The most consistent watch-together crews this week on SyncTogether. Points come from time spent watching with other people, multiplied by your streak.",
};

const MEDALS: Record<number, string> = {
  1: "#FBBF24",
  2: "#CBD5E1",
  3: "#D08C60",
};

export default async function LeaderboardPage() {
  const board = await getPublicBoard("week", 50);

  return (
    <div className="relative py-12 md:py-20 px-4 sm:px-6 lg:px-8 max-w-3xl mx-auto space-y-10">
      <div className="glow-blob-purple top-6 left-1/2 -translate-x-1/2 opacity-30" />

      <header className="text-center space-y-3 max-w-xl mx-auto">
        <h1 className="text-3xl sm:text-5xl font-extrabold text-white tracking-tight font-[family-name:var(--font-space-grotesk)]">
          This week&apos;s <span className="text-gradient-brand">regulars</span>.
        </h1>
        <p className="text-gray-300">
          Points are one a minute watched <em>with someone</em>, plus a bonus for each
          different person, multiplied by your streak. Consistency beats one long
          Saturday - that is the whole idea.
        </p>
      </header>

      {board.open ? (
        <ol className="glass-panel rounded-2xl divide-y divide-white/5 overflow-hidden">
          {board.rows.map((row) => (
            <li key={`${row.rank}-${row.handle ?? row.name}`} className="flex items-center gap-4 px-5 py-4">
              <span
                className="w-7 text-center font-[family-name:var(--font-jetbrains-mono)] text-sm font-semibold"
                style={{ color: MEDALS[row.rank] ?? "#6B7280" }}
              >
                {row.rank}
              </span>
              <PublicAvatar
                seed={row.handle ?? row.name}
                name={row.name}
                avatar={row.avatar}
                frame={row.frame}
                size={38}
              />
              <div className="flex-1 min-w-0">
                {row.handle ? (
                  <Link
                    href={`/u/${row.handle}`}
                    className="font-semibold text-white hover:text-[var(--pt-text-accent)] transition-colors truncate block"
                  >
                    {row.name}
                  </Link>
                ) : (
                  <span className="font-semibold text-white truncate block">{row.name}</span>
                )}
                <span className="text-xs text-gray-500">
                  {row.streak > 0 ? `${row.streak}-day streak` : "no streak yet"}
                </span>
              </div>
              <span className="font-[family-name:var(--font-jetbrains-mono)] text-sm font-semibold text-[var(--pt-text-accent)]">
                {formatPoints(row.points)}
              </span>
            </li>
          ))}
        </ol>
      ) : (
        <div className="glass-panel rounded-2xl px-6 pt-4 pb-12 text-center space-y-3">
          <Image
            src="/art/leaderboard-empty.avif"
            alt=""
            width={1200}
            height={800}
            priority
            className="mx-auto w-full max-w-md h-auto"
          />
          <p className="text-lg font-semibold text-white">The board is still warming up</p>
          <p className="text-sm text-gray-400 max-w-md mx-auto">
            It opens once enough people are playing. A leaderboard with a handful of
            names on it is worse than none - so this one waits.
          </p>
        </div>
      )}

      <div className="glass-panel rounded-2xl px-6 py-7 text-center space-y-4">
        <p className="text-lg font-semibold text-white">Want to be on it?</p>
        <p className="text-sm text-gray-300">
          Watch twenty minutes with someone and the day counts. Appearing here is
          opt-in - turn it on from your profile in the app whenever you like.
        </p>
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
