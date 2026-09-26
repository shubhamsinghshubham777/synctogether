import { FadeImage } from "@/components/motion/FadeImage";

/**
 * Full-bleed product shot, deliberately not a card. It is the one place on the
 * homepage that breaks the grid rhythm, and it sits immediately after the trust
 * strip so the reader sees the real thing before taking anything else on faith.
 */
export function ProductShot() {
  return (
    <section className="relative py-10 md:py-14">
      <div className="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 mb-8 md:mb-10 flex flex-col md:flex-row md:items-end md:justify-between gap-4 border-b border-rail pb-6">
        <div className="space-y-3">
          <p className="font-mono text-[11px] uppercase tracking-[0.16em] text-screen/55">
            Screen 01 · This is the room
          </p>
          <h2 className="font-[family-name:var(--font-display)] font-extrabold tracking-[-0.03em] leading-[0.95] text-4xl sm:text-5xl text-screen">
            Same frame. Same room<span className="text-beam-400">.</span>
          </h2>
        </div>
        <p className="max-w-sm text-screen/65 text-base leading-relaxed">
          Faces down the side, the transport under the picture, and nothing painted over the
          subtitles.
        </p>
      </div>

      {/* Edge-to-edge, with the canvas colour feathered back in so the shot
          dissolves into the page instead of ending on a hard seam. */}
      <div className="relative">
        <div className="relative w-full max-w-[1600px] mx-auto">
          <FadeImage
            src="/shots/room-theater.jpg"
            alt="A SyncTogether room: a film playing with four facecam tiles down the left edge, the room name, paper room-code tag, in-sync indicator and remaining time along the top, and the shared transport bar under the picture."
            width={1920}
            height={1080}
            sizes="100vw"
            className="w-full h-auto"
            priority={false}
          />
        </div>
      </div>
    </section>
  );
}
