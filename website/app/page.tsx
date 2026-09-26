import { Reveal } from "@/components/motion/Reveal";
import { HeroPoster } from "@/components/hero/HeroPoster";
import { TiltPoster } from "@/components/hero/TiltPoster";
import { HeroStage } from "@/components/hero/HeroStage";
import { DownloadCTA } from "@/components/hero/DownloadCTA";
import { TrustStrip } from "@/components/TrustStrip";
import { WhyNotScreenShare } from "@/components/WhyNotScreenShare";
import { ReactionPlayground } from "@/components/ReactionPlayground";
import { TierPreviewSection } from "@/components/TierPreviewSection";
import { ReleaseChip } from "@/components/ReleaseChip";
import { Ticket } from "@/components/Ticket";
import { getLatestRelease } from "@/lib/github";

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
    body: "Stop for dinner. The room remembers where you were and reopens right there: for a day on Free, for good on Patron.",
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
  const release = await getLatestRelease();
  const displayTag = release.name || `v${release.version || "0.11.0"}`;

  return (
    <div className="relative overflow-x-clip">
      {/* 1. HERO - the Booth Light canvas's split composition */}
      <section className="relative px-4 sm:px-6 lg:px-8 max-w-7xl mx-auto pt-6 pb-10 lg:pt-10 lg:pb-8">
        <div className="grid lg:grid-cols-[1.05fr_1fr] gap-12 lg:gap-14 items-start">
          <div className="flex flex-col gap-[26px]">
            <div className="flex flex-wrap items-center gap-4">
              <p className={`${mono} text-xs tracking-[0.14em] text-gray-500`}>
                NOW SHOWING ON MAC · WINDOWS
              </p>
              <ReleaseChip tag={displayTag} className="hidden sm:inline-flex" />
            </div>
            <h1
              className={`${display} font-extrabold text-[clamp(50px,6vw,86px)] leading-[0.88] tracking-[-0.045em]`}
            >
              <span className="line-in">Same movie.</span>
              <span className="line-in [animation-delay:90ms]">Same second.</span>
              <span className="line-in [animation-delay:180ms] text-beam-500">Different couches.</span>
            </h1>
            <p className="text-base sm:text-[19px] leading-[1.55] text-gray-300 max-w-[520px]">
              Open a room, send the ticket, press play once. Your own files or YouTube, with
              chat, reactions and facecams, and everyone stays within a frame of each other.
            </p>
            <DownloadCTA align="start" />
          </div>
          <TiltPoster>
            <HeroPoster />
          </TiltPoster>
        </div>
      </section>

      <TrustStrip />

      {/* 2. HOW IT WORKS - three reels */}
      <section id="how" className="px-4 sm:px-6 lg:px-8 max-w-7xl mx-auto py-10 scroll-mt-24">
        <Reveal>
          <div className="grid lg:grid-cols-[1fr_2fr] gap-10 lg:gap-16">
            <div className="flex flex-col gap-4">
              <Kicker n="01">How it works</Kicker>
              <h2 className={`${display} text-[34px] sm:text-5xl font-extrabold tracking-[-0.04em] leading-[0.92]`}>
                Three steps.
                <br />
                One of them is pressing play.
              </h2>
            </div>
            <ol className="grid sm:grid-cols-3 gap-0 sm:gap-8">
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
      <section className="bg-[#0D0B0B] border-y border-aisle py-10 md:py-11">
        <div className="px-4 sm:px-6 lg:px-8 max-w-7xl mx-auto">
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

      <Reveal>
        <WhyNotScreenShare />
      </Reveal>

      {/* 4. FEATURES - an editorial grid, not a wall of icon cards */}
      <section id="features" className="border-t border-aisle px-4 sm:px-6 lg:px-8 max-w-7xl mx-auto pt-12 pb-10 scroll-mt-24">
        <Reveal>
          <div className="max-w-2xl space-y-4 mb-10">
            <Kicker n="04">What&apos;s in the room</Kicker>
            <h2 className={`${display} text-4xl sm:text-5xl font-extrabold tracking-[-0.035em] leading-[0.95]`}>
              Everything a couch has. Minus the couch.
            </h2>
          </div>
          <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-x-10 gap-y-10">
            {FEATURES.map((f) => (
              <div key={f.tag} className="feature border-t border-rail pt-5 space-y-3">
                <p className={`${mono} text-[11px] tracking-[0.16em] text-beam-500`}>{f.tag}</p>
                <h3 className={`${display} text-xl sm:text-2xl font-bold tracking-[-0.02em]`}>{f.title}</h3>
                <p className="text-[15px] leading-relaxed text-gray-400">{f.body}</p>
              </div>
            ))}
          </div>
        </Reveal>

        <Reveal className="mt-12 md:mt-16">
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

      <Reveal>
        <TierPreviewSection />
      </Reveal>

      {/* 5. CLOSING - the ticket, one more time */}
      <section className="px-4 sm:px-6 lg:px-8 max-w-[960px] mx-auto pt-4 pb-14">
        <Reveal>
          <div className="space-y-8">
            <Ticket
              stubClassName="w-24 sm:w-[140px]"
              stub={
                <span className={`${mono} text-base sm:text-xl font-semibold tracking-[0.1em]`}>FREE</span>
              }
            >
              <p className={`${mono} text-[11px] tracking-[0.16em] text-[#A33A22]`}>
                ADMIT YOUR WHOLE GROUP CHAT
              </p>
              <p className={`${display} mt-2 text-3xl sm:text-5xl font-extrabold tracking-[-0.04em] leading-[0.95]`}>
                Tonight&apos;s showing starts when you do.
              </p>
            </Ticket>
            <DownloadCTA />
          </div>
        </Reveal>
      </section>
    </div>
  );
}
