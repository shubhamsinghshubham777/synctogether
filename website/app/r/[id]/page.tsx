import type { Metadata } from "next";
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
import { Ticket } from "@/components/Ticket";
import { PTButton } from "@/components/PTButton";
import { Kicker, Headline, Stamp, display, mono } from "@/components/booth/Booth";

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
    <div className="px-4 sm:px-6 lg:px-8 max-w-6xl mx-auto pt-8 pb-12 md:pt-12 md:pb-16 space-y-10">
      <header className="grid lg:grid-cols-[1.25fr_1fr] gap-10 lg:gap-16 items-center">
        <div className="space-y-6 min-w-0">
          <Kicker>Watch party recap</Kicker>
          <Headline className="text-[clamp(2.75rem,8vw,5.5rem)] break-words">
            {recap.room_name ? (
              <span className="line-in">{recap.room_name}</span>
            ) : (
              <>
                <span className="line-in">A good</span>
                <span className="line-in [animation-delay:90ms] text-beam-500">one.</span>
              </>
            )}
          </Headline>
          <p className="text-lg sm:text-xl text-gray-400 leading-relaxed max-w-xl">
            {formatWatchTime(recap.seconds)} in sync with {others}{" "}
            {others === 1 ? "other person" : "other people"}
            {recap.top_emoji ? ` ${recap.top_emoji}` : ""}
          </p>
        </div>

        <div className="relative pt-10">
          <Ticket
            animate
            stub={
              <span className={`${mono} text-sm sm:text-base font-semibold tracking-[0.12em] whitespace-nowrap`}>
                ADMIT {recap.peak_members}
              </span>
            }
          >
            <p className={`${mono} text-[10px] sm:text-[11px] tracking-[0.14em] text-[#A33A22]`}>ONE NIGHT ONLY</p>
            <p className={`${display} mt-1.5 text-3xl sm:text-4xl font-extrabold tracking-[-0.04em] leading-none tabular-nums`}>
              {formatWatchTime(recap.seconds)}
            </p>
            <p className="mt-2 text-xs sm:text-sm text-[#5A4F44]">in the same second, start to finish</p>
          </Ticket>
          {/* Sits above the ticket's top edge, left of the perforation: never on the stub, never on text. */}
          <div className="absolute top-0 right-[7.5rem] sm:right-[9.5rem] scale-75 sm:scale-90 origin-top-right">
            <Stamp top="HOUSE" main="FULL" bottom="IN SYNC" tone="signal" tilt={14} />
          </div>
        </div>
      </header>

      <div className="grid grid-cols-3 gap-x-4 sm:gap-x-6">
        <StatTile value={formatWatchTime(recap.seconds)} label="watched" />
        <StatTile value={`${recap.reactions}`} label="reactions" accent="text-signal" />
        <StatTile value={`${recap.messages}`} label="messages" />
      </div>

      <div className="grid lg:grid-cols-2 gap-14">
        {cast.length > 0 && (
          <section className="space-y-5">
            <Kicker tone="muted">Who was there</Kicker>
            <ul className="border-t border-rail">
              {cast.map((person, i) => (
                <li key={`${person.seed}-${i}`} className="flex items-center gap-4 py-3.5 border-b border-aisle">
                  <PublicAvatar
                    seed={person.seed}
                    name={person.public ? person.name : null}
                    avatar={person.public ? person.avatar : null}
                    frame={person.public ? person.frame : null}
                    size={40}
                  />
                  <span className={`flex-1 min-w-0 truncate ${person.public ? "text-white font-semibold" : "text-gray-500 italic"}`}>
                    {displayNameFor(person)}
                  </span>
                  {i === 0 && <span className={`${mono} text-[10px] tracking-[0.14em] text-gray-500`}>SHARED IT</span>}
                </li>
              ))}
            </ul>
            <p className="text-sm text-gray-500">
              People who haven&apos;t turned on a public profile stay anonymous here.
            </p>
          </section>
        )}

        {recap.superlatives.length > 0 && (
          <section className="space-y-5">
            <Kicker tone="muted">The awards</Kicker>
            <ul className="space-y-3">
              {recap.superlatives.map((award, i) => (
                <li
                  key={`${award.key}-${i}`}
                  className="booth-rise bg-seat ring-1 ring-inset ring-rail rounded-md px-5 py-4 flex flex-wrap items-center gap-x-4 gap-y-3"
                  style={{ animationDelay: `${i * 90}ms` }}
                >
                  <span className={`${mono} text-xs text-signal`}>{String(i + 1).padStart(2, "0")}</span>
                  <p className={`${display} flex-1 min-w-[10rem] text-xl font-extrabold tracking-[-0.02em] text-white`}>
                    {SUPERLATIVE_TITLES[award.key] ?? award.key}
                  </p>
                  <div className="flex items-center gap-2.5 min-w-0">
                    {award.person && (
                      <PublicAvatar
                        seed={award.person.seed}
                        name={award.person.public ? award.person.name : null}
                        avatar={award.person.public ? award.person.avatar : null}
                        frame={award.person.public ? award.person.frame : null}
                        size={28}
                      />
                    )}
                    <span className={`text-sm truncate ${award.person?.public ? "text-gray-300" : "text-gray-500 italic"}`}>
                      {displayNameFor(award.person)}
                    </span>
                  </div>
                </li>
              ))}
            </ul>
          </section>
        )}
      </div>

      <section className="border-t border-rail pt-12 grid md:grid-cols-[1fr_auto] gap-8 items-end">
        <div className="space-y-4 max-w-xl">
          <Kicker tone="muted">Want one of these?</Kicker>
          <Headline as="h2" className="text-3xl sm:text-4xl">Your group chat, same second.</Headline>
          <p className="text-gray-400 leading-relaxed">
            {SITE_CONFIG.name} keeps local files and YouTube in sync across every device
            in the room, with chat, reactions and facecams. Free, no ads.
          </p>
        </div>
        <PTButton href="/download" size="lg">
          Get {SITE_CONFIG.name}
        </PTButton>
      </section>
    </div>
  );
}
