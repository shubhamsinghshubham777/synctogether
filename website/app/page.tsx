import { FadeImage } from "@/components/motion/FadeImage";
import { Reveal } from "@/components/motion/Reveal";
import { GlassPanel } from "@/components/GlassPanel";
import { HeroStage } from "@/components/hero/HeroStage";
import { DownloadCTA } from "@/components/hero/DownloadCTA";
import { TrustStrip } from "@/components/TrustStrip";
import { ProductShot } from "@/components/ProductShot";
import { WhyNotScreenShare } from "@/components/WhyNotScreenShare";
import { ReactionPlayground } from "@/components/ReactionPlayground";
import { TierPreviewSection } from "@/components/TierPreviewSection";
import { ReleaseChip } from "@/components/ReleaseChip";
import { getLatestRelease } from "@/lib/github";
import {
  Film,
  MessageCircle,
  Video,
  Clock,
  ShieldCheck,
} from "lucide-react";

export const revalidate = 3600; // ISR hourly

export default async function HomePage() {
  const release = await getLatestRelease();
  const displayTag = release.name || `v${release.version || "0.11.0"}`;

  return (
    <div className="relative overflow-hidden">
      {/* Background Ambient Glows */}
      <div className="glow-blob-purple top-10 left-1/2 -translate-x-1/2 opacity-40" />
      <div className="glow-blob-cyan top-96 -left-40 opacity-25" />

      {/* 1. HERO SECTION */}
      <section className="relative pt-10 pb-12 md:pt-16 md:pb-16 px-4 sm:px-6 lg:px-8 max-w-7xl mx-auto text-center space-y-8">
        {/* Release / Intro Pill */}
        <ReleaseChip tag={displayTag} />

        {/* Hero Title */}
        <div className="space-y-4 max-w-4xl mx-auto">
          <h1 className="text-4xl sm:text-6xl lg:text-7xl font-extrabold tracking-tight font-[family-name:var(--font-space-grotesk)] leading-[1.1]">
            Movie night, even when you&apos;re{" "}
            <span className="text-gradient-brand">not in the same room.</span>
          </h1>
          <p className="text-lg sm:text-xl text-gray-300 max-w-2xl mx-auto leading-relaxed font-[family-name:var(--font-outfit)]">
            No more counting down from three. Open your own video file or paste
            a YouTube link, and everyone lands on the same frame at the same
            moment - with voice, facecams and reactions on top.
          </p>
        </div>

        {/* Interactive Sync Simulator + Download CTA */}
        <div className="pt-2 md:pt-4">
          <HeroStage />
        </div>
      </section>

      <TrustStrip />

      <Reveal><ProductShot /></Reveal>

      {/* 2. HOW IT WORKS */}
      <section className="relative py-12 md:py-16 bg-[#090812] border-y border-purple-500/10">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center max-w-2xl mx-auto mb-10 md:mb-12 space-y-3">
            <p className="text-xs font-bold uppercase tracking-widest text-purple-400 font-mono">
              Simple 3-Step Setup
            </p>
            <h2 className="text-3xl sm:text-4xl font-extrabold text-white font-[family-name:var(--font-space-grotesk)]">
              From zero to watching in under 10 seconds.
            </h2>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
            {/* Step 1 */}
            <GlassPanel hoverEffect className="space-y-4">
              <div className="w-12 h-12 rounded-xl bg-purple-600/20 border border-purple-500/30 flex items-center justify-center text-purple-300 font-bold font-mono text-lg">
                01
              </div>
              <h3 className="text-xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
                Create a Room
              </h3>
              <p className="text-sm text-gray-400 leading-relaxed">
                Launch the app and generate a private room in one click. Pick any
                local video file on your computer or paste a YouTube URL.
              </p>
            </GlassPanel>

            {/* Step 2 */}
            <GlassPanel hoverEffect className="space-y-4">
              <div className="w-12 h-12 rounded-xl bg-purple-600/20 border border-purple-500/30 flex items-center justify-center text-purple-300 font-bold font-mono text-lg">
                02
              </div>
              <h3 className="text-xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
                Share Room Code
              </h3>
              <p className="text-sm text-gray-400 leading-relaxed">
                Send your unique 6-character room code, or the{" "}
                <code className="text-xs text-purple-300 bg-purple-950/80 px-1 py-0.5 rounded">
                  synctogether.app/join
                </code>{" "}
                link that opens the room in one tap - it pastes anywhere.
              </p>
            </GlassPanel>

            {/* Step 3 */}
            <GlassPanel hoverEffect className="space-y-4">
              <div className="w-12 h-12 rounded-xl bg-purple-600/20 border border-purple-500/30 flex items-center justify-center text-purple-300 font-bold font-mono text-lg">
                03
              </div>
              <h3 className="text-xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
                Watch in Sync
              </h3>
              <p className="text-sm text-gray-400 leading-relaxed">
                Play, pause, seek, and scrub in perfect sync. Talk over
                low-latency voice or video, react with animated emoji, and chat.
              </p>
            </GlassPanel>
          </div>
        </div>
      </section>

      <Reveal><WhyNotScreenShare /></Reveal>

      {/* 3. CORE FEATURES */}
      <section id="features" className="relative py-12 md:py-16 px-4 sm:px-6 lg:px-8 max-w-7xl mx-auto">
        <div className="text-center max-w-3xl mx-auto mb-10 md:mb-12 space-y-3">
          <p className="text-xs font-bold uppercase tracking-widest text-purple-400 font-mono">
            Engineered for Media Enthusiasts
          </p>
          <h2 className="text-3xl sm:text-5xl font-extrabold text-white font-[family-name:var(--font-space-grotesk)]">
            Everything you need for the ultimate watch party.
          </h2>
        </div>

        {/* Lead feature, given an image row rather than a card - it is the
            differentiator, and it is the one that benefits from being shown. */}
        <div className="grid lg:grid-cols-2 gap-8 lg:gap-12 items-center mb-12 md:mb-16">
          <div className="space-y-4 order-2 lg:order-1">
            <div className="p-3 rounded-xl bg-purple-500/10 text-purple-300 w-fit border border-purple-500/20">
              <Film className="w-6 h-6" />
            </div>
            <h3 className="text-2xl sm:text-3xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
              Your file, or a link. Both stay in sync.
            </h3>
            <p className="text-base text-gray-300 leading-relaxed">
              Point the room at a local MKV, MP4 or 4K HDR file and every
              machine plays it natively, hardware accelerated - or paste a
              YouTube URL and skip the file entirely.
            </p>
            <p className="text-base text-gray-400 leading-relaxed">
              Whoever you invite doesn&apos;t need an account to join. One tap on
              the link puts them in the room.
            </p>
          </div>
          <div className="order-1 lg:order-2 rounded-2xl overflow-hidden border border-white/10 shadow-2xl shadow-purple-900/20">
            <FadeImage
              src="/shots/room-source.jpg"
              alt="The SyncTogether source picker over a paused film, asking &quot;What are we watching?&quot; with two choices: Local file, play from your device, and YouTube, paste a link."
              width={1920}
              height={1080}
              sizes="(min-width: 1024px) 50vw, 100vw"
              className="w-full h-auto"
            />
          </div>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
          {/* Feature 2 */}
          <GlassPanel hoverEffect className="space-y-3">
            <div className="p-3 rounded-xl bg-pink-500/10 text-pink-300 w-fit border border-pink-500/20">
              <Video className="w-6 h-6" />
            </div>
            <h3 className="text-xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
              Voice &amp; Video Facecams
            </h3>
            <p className="text-sm text-gray-400 leading-relaxed">
              See and hear the people you watch with, down the side of the
              film. Active speaker detection, and light enough on the CPU that
              the bandwidth stays where it belongs.
            </p>
          </GlassPanel>

          {/* Feature 3 */}
          <GlassPanel hoverEffect className="space-y-3">
            <div className="p-3 rounded-xl bg-cyan-500/10 text-cyan-300 w-fit border border-cyan-500/20">
              <MessageCircle className="w-6 h-6" />
            </div>
            <h3 className="text-xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
              Chat &amp; Animated Reactions
            </h3>
            <p className="text-sm text-gray-400 leading-relaxed">
              A chat panel with typing indicators, and 24 animated emoji that
              pop over the video the moment somebody taps one.
            </p>
          </GlassPanel>

          {/* Feature 4 */}
          <GlassPanel hoverEffect className="space-y-3">
            <div className="p-3 rounded-xl bg-amber-500/10 text-amber-300 w-fit border border-amber-500/20">
              <Clock className="w-6 h-6" />
            </div>
            <h3 className="text-xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
              Rooms You Can Reopen
            </h3>
            <p className="text-sm text-gray-400 leading-relaxed">
              Need a break? Your room remembers where you stopped and reopens
              right there. Free rooms stay resumable for 24h after they end;
              Premium rooms never expire at all.
            </p>
          </GlassPanel>

          {/* Feature 5 */}
          <GlassPanel hoverEffect className="space-y-3">
            <div className="p-3 rounded-xl bg-indigo-500/10 text-indigo-300 w-fit border border-indigo-500/20">
              <ShieldCheck className="w-6 h-6" />
            </div>
            <h3 className="text-xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
              Private by Default
            </h3>
            <p className="text-sm text-gray-400 leading-relaxed">
              Your files stay on your device - nothing uploads. File paths
              never leave your machine, and chat is wiped when the room
              closes.
            </p>
          </GlassPanel>
        </div>

        {/* Reaction Playground */}
        <div className="mt-14 text-center space-y-4">
          <h3 className="text-2xl sm:text-3xl font-extrabold text-white font-[family-name:var(--font-space-grotesk)]">
            Try a reaction.
          </h3>
          <p className="text-sm text-gray-300 max-w-md mx-auto">
            This is exactly what everyone in the room sees, floating over the
            video the moment you tap.
          </p>
          <div className="pt-2">
            <ReactionPlayground />
          </div>
        </div>
      </section>

      {/* 4. TIER PREVIEW SECTION */}
      <Reveal><TierPreviewSection /></Reveal>

      {/* 5. BOTTOM DOWNLOAD CTA */}
      <section className="relative py-12 md:py-16 px-4 sm:px-6 lg:px-8 max-w-5xl mx-auto text-center">
        <GlassPanel glow="purple" className="py-12 md:py-14 px-8 sm:px-12 space-y-8 border-purple-400/30">
          <div className="space-y-3 max-w-2xl mx-auto">
            <h2 className="text-3xl sm:text-5xl font-extrabold text-white font-[family-name:var(--font-space-grotesk)]">
              Ready to watch together?
            </h2>
            <p className="text-base text-gray-300">
              Download SyncTogether for free and host your first watch party in seconds.
            </p>
          </div>

          <DownloadCTA />
        </GlassPanel>
      </section>
    </div>
  );
}
