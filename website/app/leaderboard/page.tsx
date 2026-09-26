import type { Metadata } from "next";
import Link from "next/link";
import { formatPoints, getPublicBoard, type LeaderboardEntry } from "@/lib/rewards";
import { SITE_CONFIG } from "@/lib/constants";
import { PublicAvatar } from "@/components/rewards/PublicAvatar";
import { PTButton } from "@/components/PTButton";
import { Kicker, Headline, Stamp, display, mono } from "@/components/booth/Booth";

export const revalidate = 300;

export const metadata: Metadata = {
  title: "Leaderboard",
  description:
    "The most consistent watch-together crews this week on SyncTogether. Points come from time spent watching with other people, multiplied by your streak.",
};

/** Podium places: Beam for first, Screen for second, Signal for third. */
const PLACE: Record<number, { text: string; bar: string; ring: string; block: string; order: string }> = {
  1: { text: "text-beam-500", bar: "border-t-beam-500", ring: "ring-beam-500", block: "h-28 sm:h-32", order: "order-2" },
  2: { text: "text-screen", bar: "border-t-screen", ring: "ring-screen", block: "h-20 sm:h-24", order: "order-1" },
  3: { text: "text-signal", bar: "border-t-signal", ring: "ring-signal", block: "h-14 sm:h-16", order: "order-3" },
};

const RULES = [
  { k: "per minute together", v: "1 pt" },
  { k: "each person, up to 5", v: "+15" },
  { k: "a room fills to four", v: "+25" },
  { k: "streak (3 / 7 / 30 d)", v: "up to ×1.5" },
];

function ScoreKey() {
  return (
    <div className="rounded-md ring-1 ring-inset ring-rail px-5 py-4">
      <p className={`${mono} text-[10px] tracking-[0.16em] uppercase text-gray-500 mb-2`}>How the score is kept</p>
      <dl className={`${mono} grid sm:grid-cols-2 gap-x-10 gap-y-1.5 text-xs`}>
        {RULES.map((r) => (
          <div key={r.k} className="flex justify-between gap-4">
            <dt className="text-gray-400">{r.k}</dt>
            <dd className="text-white font-semibold whitespace-nowrap">{r.v}</dd>
          </div>
        ))}
      </dl>
    </div>
  );
}

function Name({ row, className = "" }: { row: LeaderboardEntry; className?: string }) {
  return row.handle ? (
    <Link
      href={`/u/${row.handle}`}
      className={`hover:text-beam-500 transition-colors truncate block ${className}`}
    >
      {row.name}
    </Link>
  ) : (
    <span className={`truncate block ${className}`}>{row.name}</span>
  );
}

export default async function LeaderboardPage() {
  const board = await getPublicBoard("week", 50);
  const podium = board.open ? board.rows.slice(0, 3) : [];
  const rest = board.open ? board.rows.slice(3) : [];

  return (
    <div className="px-4 sm:px-6 lg:px-8 max-w-4xl mx-auto pt-8 pb-12 md:pt-12 md:pb-16 space-y-10 md:space-y-12">
      <header>
        <div className="space-y-5">
          <Kicker>The board · this week</Kicker>
          <Headline className="text-[clamp(2.75rem,7.5vw,5.5rem)]">
            <span className="line-in">This week&apos;s</span>
            <span className="line-in [animation-delay:90ms] text-beam-500">regulars.</span>
          </Headline>
          <p className="text-lg text-gray-400 leading-relaxed max-w-xl">
            A minute watched <em className="text-white not-italic font-semibold">with someone</em> is a point,
            plus a bonus per different person, times your streak. Consistency beats one long Saturday.
          </p>
        </div>
      </header>

      {board.open ? (
        <section className="space-y-10" aria-label="Leaderboard">
          <ol className="grid grid-cols-3 gap-2 sm:gap-4 items-end max-w-xl mx-auto">
            {podium.map((row) => {
              const place = PLACE[row.rank] ?? PLACE[3];
              return (
                <li
                  key={`${row.rank}-${row.handle ?? row.name}`}
                  className={`booth-rise flex flex-col items-center min-w-0 ${place.order}`}
                  style={{ animationDelay: `${row.rank * 80}ms` }}
                >
                  {/* The rank colour rings the seat's avatar, as on the board. */}
                  <div className={`rounded-full ring-2 ${place.ring} ring-offset-2 ring-offset-booth`}>
                    <PublicAvatar
                      seed={row.handle ?? row.name}
                      name={row.name}
                      avatar={row.avatar}
                      frame={row.frame}
                      size={row.rank === 1 ? 52 : 44}
                    />
                  </div>
                  <Name row={row} className="mt-2.5 max-w-full text-center font-semibold text-white" />
                  <span className={`${mono} mt-0.5 text-xs text-gray-400 tabular-nums`}>{formatPoints(row.points)}</span>
                  <div
                    className={`mt-3 w-full ${place.block} bg-seat border border-rail border-t-[3px] ${place.bar} rounded-t-[4px] flex items-center justify-center`}
                  >
                    <span className={`${display} font-extrabold text-3xl sm:text-4xl leading-none ${place.text}`}>{row.rank}</span>
                  </div>
                </li>
              );
            })}
          </ol>

          {rest.length > 0 && (
            <ol className="border-t border-rail" start={4}>
              {rest.map((row) => (
                <li
                  key={`${row.rank}-${row.handle ?? row.name}`}
                  className="flex items-center gap-4 py-4 border-b border-aisle"
                >
                  <span className={`${mono} w-8 text-sm text-gray-500 tabular-nums`}>
                    {String(row.rank).padStart(2, "0")}
                  </span>
                  <PublicAvatar
                    seed={row.handle ?? row.name}
                    name={row.name}
                    avatar={row.avatar}
                    frame={row.frame}
                    size={36}
                  />
                  <div className="flex-1 min-w-0">
                    <Name row={row} className="font-semibold text-white" />
                    <span className={`${mono} text-[11px] text-gray-500`}>
                      {row.streak > 0 ? `${row.streak}-day streak` : "no streak yet"}
                    </span>
                  </div>
                  <span className={`${mono} text-sm font-semibold text-white tabular-nums`}>
                    {formatPoints(row.points)}
                  </span>
                </li>
              ))}
            </ol>
          )}
        </section>
      ) : (
        <section className="grid lg:grid-cols-[1.2fr_1fr] gap-12 items-center">
          <div className="relative" aria-hidden="true">
            <div className="grid grid-cols-3 gap-3 sm:gap-4 items-end">
              {[2, 1, 3].map((n) => (
                <div
                  key={n}
                  className={`rounded-md border-2 border-dashed border-rail flex items-start justify-start p-4 ${
                    n === 1 ? "h-48 sm:h-60" : n === 2 ? "h-36 sm:h-44" : "h-28 sm:h-36"
                  }`}
                >
                  <span className={`${display} font-extrabold text-4xl sm:text-6xl text-aisle leading-none`}>{n}</span>
                </div>
              ))}
            </div>
            <div className="absolute left-1/2 top-[48%] -translate-x-1/2">
              <Stamp top="THE BOARD" main="WARMING UP" bottom="SEATS RESERVED" shape="rect" tilt={-6} />
            </div>
          </div>
          <div className="space-y-4">
            <Headline as="h2" className="text-3xl sm:text-4xl">The board is still warming up.</Headline>
            <p className="text-gray-400 leading-relaxed max-w-md">
              It opens once enough people are playing. A leaderboard with a handful of
              names on it is worse than none, so this one waits.
            </p>
          </div>
        </section>
      )}

      <ScoreKey />

      <section className="border-t border-rail pt-12 grid md:grid-cols-[1fr_auto] gap-8 items-end">
        <div className="space-y-4 max-w-xl">
          <Kicker tone="muted">Want to be on it?</Kicker>
          <Headline as="h2" className="text-3xl sm:text-4xl">Twenty minutes with someone and the day counts.</Headline>
          <p className="text-gray-400 leading-relaxed">
            Appearing here is opt-in. Turn it on from your profile in the app whenever you like.
          </p>
        </div>
        <PTButton href="/download" size="lg">
          Get {SITE_CONFIG.name}
        </PTButton>
      </section>
    </div>
  );
}
