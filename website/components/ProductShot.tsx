import { FadeImage } from "@/components/motion/FadeImage";

/**
 * Full-bleed product shot, deliberately not a card. It is the one place on the
 * homepage that breaks the grid rhythm, and it sits immediately after the trust
 * strip so the reader sees the real thing before taking anything else on faith.
 */
export function ProductShot() {
  return (
    <section className="relative py-10 md:py-14">
      <div className="max-w-3xl mx-auto px-4 sm:px-6 lg:px-8 text-center space-y-3 mb-8 md:mb-10">
        <p className="text-xs font-bold uppercase tracking-widest text-purple-400 font-mono">
          This is the room
        </p>
        <h2 className="text-3xl sm:text-4xl font-extrabold text-white font-[family-name:var(--font-space-grotesk)]">
          Same frame, same room: faces, chat, all of it.
        </h2>
      </div>

      {/* Edge-to-edge, with the canvas colour feathered back in so the shot
          dissolves into the page instead of ending on a hard seam. */}
      <div className="relative">
        <div className="relative w-full max-w-[1600px] mx-auto">
          <FadeImage
            src="/shots/room-theater.jpg"
            alt="A SyncTogether room: a film playing full-screen with four facecam tiles down the left edge, the room code and remaining time along the top, the party chat open on the right, and the shared transport bar across the bottom."
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
