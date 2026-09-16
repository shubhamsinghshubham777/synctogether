import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import {
  displayNameFor,
  formatWatchTime,
  getRecap,
  SUPERLATIVE_TITLES,
} from "@/lib/rewards";
import { SITE_CONFIG } from "@/lib/constants";
import { PublicAvatar } from "@/components/rewards/PublicAvatar";
import { StatTile } from "@/components/rewards/StatTile";

export const revalidate = 300;

/**
 * A shared session recap.
 *
 * `noindex` on purpose: the URL is unguessable and the owner chose to share it
 * with particular people, not with a search engine. It is also the reason the
 * payload is assembled server-side in `create_recap` rather than passed through -
 * nothing about what was watched, no file name, no link, no chat, and nobody
 * named who has not opted into a public profile.
 */
export async function generateMetadata({
  params,
}: {
  params: Promise<{ id: string }>;
}): Promise<Metadata> {
  const { id } = await params;
  const recap = await getRecap(id);
  if (!recap) {
    return { title: "Recap not found", robots: { index: false, follow: false } };
  }
  const others = recap.peak_members - 1;
  const title = recap.room_name
    ? `${recap.room_name} - a SyncTogether watch party`
    : "A SyncTogether watch party";
  const description =
    `${formatWatchTime(recap.seconds)} in sync with ` +
    `${others} other${others === 1 ? "" : "s"}, ` +
    `${recap.reactions} reactions and ${recap.messages} messages.`;
  return {
    title,
    description,
    robots: { index: false, follow: false },
    openGraph: {
      title,
      description,
      type: "article",
      url: `${SITE_CONFIG.url}/r/${id}`,
    },
    twitter: { card: "summary_large_image", title, description },
  };
}

export default async function RecapPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const recap = await getRecap(id);
  if (!recap) notFound();

  const others = recap.peak_members - 1;
  const cast = [recap.owner, ...recap.people];

  return (
    <div className="relative py-12 md:py-20 px-4 sm:px-6 lg:px-8 max-w-2xl mx-auto space-y-10">
      <div className="glow-blob-purple top-6 left-1/2 -translate-x-1/2 opacity-30" />

      <header className="text-center space-y-3">
        <p className="text-xs uppercase tracking-[0.24em] text-[var(--pt-text-accent)]">
          Watch party recap
        </p>
        <h1 className="text-3xl sm:text-4xl font-extrabold text-white tracking-tight font-[family-name:var(--font-space-grotesk)]">
          {recap.room_name ?? (
            <>
              A <span className="text-gradient-brand">good one</span>.
            </>
          )}
        </h1>
        <p className="text-gray-300">
          {formatWatchTime(recap.seconds)} in sync with {others}{" "}
          {others === 1 ? "other person" : "other people"}
          {recap.top_emoji ? ` ${recap.top_emoji}` : ""}
        </p>
      </header>

      <div className="grid grid-cols-3 gap-3">
        <StatTile value={formatWatchTime(recap.seconds)} label="watched" />
        <StatTile value={`${recap.reactions}`} label="reactions" />
        <StatTile value={`${recap.messages}`} label="messages" />
      </div>

      {cast.length > 0 && (
        <section className="space-y-4">
          <h2 className="text-sm uppercase tracking-[0.16em] text-gray-400">Who was there</h2>
          <div className="flex flex-wrap gap-4">
            {cast.map((person, i) => (
              <div key={`${person.seed}-${i}`} className="flex items-center gap-3">
                <PublicAvatar
                  seed={person.seed}
                  name={person.public ? person.name : null}
                  avatar={person.public ? person.avatar : null}
                  frame={person.public ? person.frame : null}
                  size={40}
                />
                <span className={person.public ? "text-white" : "text-gray-500 italic"}>
                  {displayNameFor(person)}
                </span>
              </div>
            ))}
          </div>
          <p className="text-xs text-gray-500">
            People who haven&apos;t turned on a public profile stay anonymous here.
          </p>
        </section>
      )}

      {recap.superlatives.length > 0 && (
        <section className="space-y-4">
          <h2 className="text-sm uppercase tracking-[0.16em] text-gray-400">
            The awards
          </h2>
          <div className="space-y-3">
            {recap.superlatives.map((award, i) => (
              <div
                key={`${award.key}-${i}`}
                className="glass-panel rounded-xl px-5 py-4 flex items-center gap-4"
              >
                <div className="flex-1">
                  <p className="font-semibold text-white">
                    {SUPERLATIVE_TITLES[award.key] ?? award.key}
                  </p>
                </div>
                <div className="flex items-center gap-2.5">
                  {award.person && (
                    <PublicAvatar
                      seed={award.person.seed}
                      name={award.person.public ? award.person.name : null}
                      avatar={award.person.public ? award.person.avatar : null}
                      frame={award.person.public ? award.person.frame : null}
                      size={28}
                    />
                  )}
                  <span className="text-sm text-gray-300">{displayNameFor(award.person)}</span>
                </div>
              </div>
            ))}
          </div>
        </section>
      )}

      <div className="glass-panel rounded-2xl px-6 py-7 text-center space-y-4">
        <p className="text-lg font-semibold text-white">Want one of these?</p>
        <p className="text-sm text-gray-300">
          {SITE_CONFIG.name} keeps local files and YouTube in sync across every device
          in the room, with chat, reactions and facecams. Free, no ads.
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
