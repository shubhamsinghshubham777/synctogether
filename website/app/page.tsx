import { Reveal } from "@/components/motion/Reveal";
import { HeroScrub } from "@/components/hero/HeroScrub";
import { HeroStage } from "@/components/hero/HeroStage";
import { DownloadCTA } from "@/components/hero/DownloadCTA";
import { TrustStrip } from "@/components/TrustStrip";
import { WhyNotScreenShare } from "@/components/WhyNotScreenShare";
import { ReactionPlayground } from "@/components/ReactionPlayground";
import { TierPreviewSection } from "@/components/TierPreviewSection";
import { Ticket } from "@/components/Ticket";
import Image from "next/image";
import Link from "next/link";
import { getPatronPrices } from "@/lib/store-prices";

export const revalidate = 3600; // ISR hourly

/** Section kicker: the mono label motif. Numbered like reels. */
function Kicker({ n, children }: { n: string; children: React.ReactNode }) {
  return (
    <p className="font-[family-name:var(--font-jetbrains-mono)] text-xs tracking-[0.16em] text-beam-500 uppercase">
      <span className="text-[#5A4F44]">{n} · </span>
      {children}
    </p>
  );
}

const display = "font-[family-name:var(--font-space-grotesk)]";
const mono = "font-[family-name:var(--font-jetbrains-mono)]";

const STEPS = [
  {
    n: "01",
    title: "Open a room",
    body: "Pick a film on your computer or paste a YouTube link. The room prints a six-letter code and a ticket.",
  },
  {
    n: "02",
    title: "Send the ticket",
    body: "It's a normal link. Paste it in any chat. Whoever taps it lands in the room. No account needed to join.",
  },
  {
    n: "03",
    title: "Press play once",
    body: "Everyone starts on the same frame. Pause, skip or scrub and the whole room follows.",
  },
];

const FEATURES = [
  {
    tag: "LOCAL OR YOUTUBE",
    title: "Your file, or a link.",
    body: "MKV, MP4, 4K HDR: every machine plays its own copy natively, hardware accelerated. Or paste a YouTube URL and skip the file entirely.",
  },
  {
    tag: "FACECAMS",
    title: "Faces down the side.",
    body: "Voice and video beside the film, not on top of it. Light on the CPU, so the bandwidth goes to what you came to watch.",
  },
  {
    tag: "CHAT + REACTIONS",
    title: "Say it, or throw it.",
    body: "A chat that remembers the night, and animated reactions that float over everyone's screen the moment you tap.",
  },
  {
    tag: "INTERMISSION",
    title: "Rooms that wait for you.",
    body: "Stop for dinner. The room remembers where you were and reopens right there: for a day on Free, for 90 idle days on Patron.",
  },
  {
    tag: "PRIVATE",
    title: "Your film never leaves.",
    body: "Files play from your own disk. Paths never leave your machine, and the chat is wiped when the room closes.",
  },
  {
    tag: "HOST CONTROLS",
    title: "One remote, if you want.",
    body: "Everyone can drive, or the host keeps the remote. Late arrivals are held at the door until their copy loads.",
  },
];

export default async function HomePage() {
  const { prices } = await getPatronPrices();

  return (
    <div className="relative overflow-x-clip">
      {/* 1. HERO - the projection booth canvas's split composition */}
      <section className="relative px-4 sm:px-6 lg:px-8 max-w-7xl min-[2000px]:max-w-[1920px] mx-auto pt-4 sm:pt-6 pb-10 lg:pt-10 lg:pb-8">
        {/* Below lg the left column dissolves into the flex column so the
            cluster can sit between the headline and the button (CSS order;
            DOM and tab order stay kicker, headline, copy, button, cluster). */}
        <div className="flex flex-col gap-4 lg:grid lg:grid-cols-[1.05fr_1fr] lg:gap-14 lg:items-start min-[2000px]:items-center">
          <div className="contents lg:flex lg:flex-col lg:gap-[26px]">
            <div className="flex flex-wrap items-center gap-4 max-lg:order-1">
              <p className={`${mono} text-xs tracking-[0.14em] text-gray-500`}>
                IPHONE · IPAD · MAC · WINDOWS
              </p>
            </div>
            <h1
              className={`${display} font-extrabold text-[clamp(50px,6vw,86px)] min-[2000px]:text-[clamp(96px,5vw,132px)] leading-[0.88] tracking-[-0.045em] max-lg:order-2`}
            >
              <span className="line-in">Same movie.</span>
              <span className="line-in [animation-delay:90ms]">Same second.</span>
              <span className="line-in [animation-delay:180ms] text-beam-500">Different couches.</span>
            </h1>
            <p className="text-base sm:text-[19px] leading-[1.55] text-gray-300 max-w-[520px] min-[2000px]:max-w-[720px] min-[2000px]:text-[24px] max-lg:order-5">
              Open a room, send the ticket, press play once. Your own files or YouTube, with
              chat, reactions and facecams, and everyone stays within a frame of each other.
            </p>
            <div className="max-lg:order-4">
              <DownloadCTA align="start" />
            </div>
          </div>
          <HeroScrub className="max-lg:order-3" />
        </div>
      </section>

      <TrustStrip />

      {/* 2 + 3. On very wide screens the steps and the demo sit side by side. */}
      <div className="min-[2000px]:grid min-[2000px]:grid-cols-[26rem_minmax(0,1fr)] min-[2000px]:gap-x-14 min-[2000px]:items-start min-[2000px]:max-w-[1920px] min-[2000px]:mx-auto min-[2000px]:px-8 min-[2000px]:py-10">
      {/* 2. HOW IT WORKS - three reels */}
      <section id="how" className="px-4 sm:px-6 lg:px-8 max-w-7xl mx-auto py-10 scroll-mt-24 min-[2000px]:max-w-none min-[2000px]:mx-0 min-[2000px]:px-0 min-[2000px]:py-0">
        <Reveal>
          <div className="grid lg:grid-cols-[1fr_2fr] gap-10 lg:gap-16 min-[2000px]:grid-cols-1! min-[2000px]:gap-8">
            <div className="flex flex-col gap-4">
              <Kicker n="01">How it works</Kicker>
              <h2 className={`${display} text-[34px] sm:text-5xl font-extrabold tracking-[-0.04em] leading-[0.92]`}>
                Three steps.
                <br />
                One of them is pressing play.
              </h2>
            </div>
            <ol className="grid sm:grid-cols-3 gap-0 sm:gap-8 min-[2000px]:grid-cols-1! min-[2000px]:gap-6">
              {STEPS.map((s) => (
                <li key={s.n} className="step border-t-2 border-rail py-4 sm:pt-5 sm:pb-0 flex flex-col gap-2 sm:gap-3">
                  <p className={`${mono} text-[13px] text-beam-500`}>{s.n}</p>
                  <h3 className={`${display} text-xl sm:text-[28px] font-extrabold tracking-[-0.03em] leading-tight`}>{s.title}</h3>
                  <p className="hidden sm:block text-[15px] leading-[1.55] text-gray-400">{s.body}</p>
                </li>
              ))}
            </ol>
          </div>
        </Reveal>
      </section>

      {/* 3. THE DEMO - flip the sync off and watch the room fall apart */}
      <section className="bg-[#0D0B0B] border-y border-aisle py-10 md:py-11 min-[2000px]:border min-[2000px]:rounded-[6px] min-[2000px]:min-w-0">
        <div className="px-4 sm:px-6 lg:px-8 max-w-7xl mx-auto min-[2000px]:max-w-none">
          <HeroStage
            header={
              <div className="max-w-[640px] flex flex-col gap-4">
                <Kicker n="02">The sync</Kicker>
                <h2 className={`${display} text-[34px] sm:text-5xl font-extrabold tracking-[-0.04em] leading-[0.92]`}>
                  Flip it off. That&apos;s movie night without us.
                </h2>
              </div>
            }
          />
        </div>
      </section>
      </div>

      {/* 3b + 4. Likewise the comparison and the feature grid. */}
      <div className="min-[2000px]:grid min-[2000px]:grid-cols-2 min-[2000px]:gap-x-16 min-[2000px]:items-start min-[2000px]:max-w-[1920px] min-[2000px]:mx-auto min-[2000px]:px-8">
      <Reveal className="min-[2000px]:col-start-1 min-[2000px]:row-start-1">
        <WhyNotScreenShare />
      </Reveal>

      {/* 4. FEATURES - an editorial grid, not a wall of icon cards */}
      <section id="features" className="border-t border-aisle px-4 sm:px-6 lg:px-8 max-w-7xl mx-auto pt-12 pb-10 scroll-mt-24 min-[2000px]:max-w-none min-[2000px]:mx-0 min-[2000px]:px-0 min-[2000px]:border-t-0 min-[2000px]:pt-14 min-[2000px]:min-w-0 min-[2000px]:col-start-2 min-[2000px]:row-start-1 min-[2000px]:row-span-2">
        <Reveal>
          <div className="max-w-2xl space-y-4 mb-10">
            <Kicker n="04">What&apos;s in the room</Kicker>
            <h2 className={`${display} text-4xl sm:text-5xl font-extrabold tracking-[-0.035em] leading-[0.95]`}>
              Everything a couch has. Minus the couch.
            </h2>
          </div>
          <div className="grid sm:grid-cols-2 lg:grid-cols-3 min-[2000px]:grid-cols-2! gap-x-10 gap-y-10">
            {FEATURES.map((f) => (
              <div key={f.tag} className="feature border-t border-rail pt-5 space-y-3">
                <p className={`${mono} text-[11px] tracking-[0.16em] text-beam-500`}>{f.tag}</p>
                <h3 className={`${display} text-xl sm:text-2xl font-bold tracking-[-0.02em]`}>{f.title}</h3>
                <p className="text-[15px] leading-relaxed text-gray-400">{f.body}</p>
              </div>
            ))}
          </div>
        </Reveal>
      </section>

      <section className="px-4 sm:px-6 lg:px-8 max-w-7xl mx-auto pt-2 md:pt-6 pb-10 min-[2000px]:max-w-none min-[2000px]:mx-0 min-[2000px]:px-0 min-[2000px]:pt-10 min-[2000px]:col-start-1 min-[2000px]:row-start-2 min-[2000px]:min-w-0">
        <Reveal>
          <div className="grid lg:grid-cols-[1fr_1.4fr] gap-10 items-center">
            <div className="space-y-4">
              <p className={`${mono} text-[11px] tracking-[0.16em] text-signal`}>TRY IT</p>
              <h3 className={`${display} text-3xl sm:text-4xl font-extrabold tracking-[-0.03em] leading-[0.95]`}>
                Throw a reaction.
              </h3>
              <p className="text-gray-400 leading-relaxed">
                Exactly what everyone in the room sees, floating over the film the moment you
                tap.
              </p>
            </div>
            <ReactionPlayground />
          </div>
        </Reveal>
      </section>
      </div>

      {/* 5. FOR TWO - the pairing feature, for long-distance couples */}
      <section className="px-4 sm:px-6 lg:px-8 max-w-7xl min-[2000px]:max-w-[1920px] mx-auto py-10 md:py-12">
        <Reveal>
          <div className="grid lg:grid-cols-[1fr_1.1fr] gap-10 lg:gap-14 items-center">
            <div className="space-y-5">
              <Kicker n="05">For two</Kicker>
              <h2 className={`${display} text-4xl sm:text-5xl font-extrabold tracking-[-0.035em] leading-[0.95]`}>
                A room that&apos;s only ever yours.
              </h2>
              <p className="text-[17px] leading-relaxed text-gray-400 max-w-xl">
                Far from your person? Pair two accounts and you get Our Room, a private room that stays put
                between nights, free on every plan. Plan a date night that shows each of you your own local
                time, get a nudge before it starts, and build a weekly streak of films watched together.
              </p>
              <ul className="space-y-2 text-[15px] text-gray-300">
                <li>Date nights across time zones, with a reminder 15 minutes before.</li>
                <li>Nicknames, a reunion countdown and a shareable year card for the two of you.</li>
                <li>The chat carries over, and a finished film waits for you to pick it up again.</li>
              </ul>
              <Link
                href="/guides/long-distance-date-night-ideas"
                className="inline-block text-white font-semibold underline underline-offset-[6px] decoration-gray-600 hover:decoration-beam-500"
              >
                Long-distance date night ideas
              </Link>
            </div>
            <Image
              src="/art/pair-room.avif"
              alt="Our Room: two people watching the same film from different cities"
              width={1200}
              height={800}
              sizes="(min-width: 1024px) 560px, 100vw"
              className="w-full h-auto rounded-md border border-rail"
            />
          </div>
        </Reveal>
      </section>

      <Reveal>
        <TierPreviewSection prices={prices} />
      </Reveal>

      {/* 5. CLOSING - the ticket, one more time */}
      <section className="px-4 sm:px-6 lg:px-8 max-w-[960px] min-[2000px]:max-w-[1920px] mx-auto pt-4 pb-14">
        <Reveal>
          <div className="space-y-8 min-[2000px]:space-y-0 min-[2000px]:flex min-[2000px]:items-center min-[2000px]:gap-16">
            <Ticket
              className="min-[2000px]:flex-1"
              stubClassName="w-24 sm:w-[140px]"
              stub={
                <span className={`${mono} text-base sm:text-xl font-semibold tracking-[0.1em]`}>FREE</span>
              }
            >
              <p className={`${mono} text-[11px] tracking-[0.16em] text-[#A33A22]`}>
                ADMIT YOUR WHOLE GROUP CHAT
              </p>
              <p className={`${display} mt-2 text-3xl sm:text-5xl min-[2000px]:text-[68px]! font-extrabold tracking-[-0.04em] leading-[0.95]`}>
                Tonight&apos;s showing starts when you do.
              </p>
            </Ticket>
            <div className="min-[2000px]:shrink-0">
              <DownloadCTA />
            </div>
          </div>
        </Reveal>
      </section>
    </div>
  );
}
