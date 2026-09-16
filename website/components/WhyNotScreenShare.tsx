import { X, Check } from "lucide-react";

/**
 * The objection every visitor is actually holding. Deliberately a two-column
 * contrast rather than another card grid - it is the second of the two places
 * the homepage breaks its own rhythm. Screen sharing is named as a technique,
 * never as a product.
 */
const ROWS: { aspect: string; sharing: string; ours: string }[] = [
  {
    aspect: "Picture",
    sharing: "Re-encoded on the fly and squeezed through whoever is hosting's upload speed.",
    ours: "Every machine plays the file natively, hardware accelerated. 4K stays 4K.",
  },
  {
    aspect: "The remote",
    sharing: "One person drives. Everyone else asks them to pause.",
    ours: "Anyone can play, pause and scrub - or the host locks the remote when it matters.",
  },
  {
    aspect: "Talking over it",
    sharing: "Your voices and the film's audio fight over one stream.",
    ours: "Separate channels. The film plays locally; voices ride their own low-latency link.",
  },
  {
    aspect: "Your laptop",
    sharing: "Encoding and uploading video the whole time. Fans up, battery down.",
    ours: "Just playing a video file, the way it was always going to.",
  },
  {
    aspect: "Turning up late",
    sharing: "Rewind for everybody, or they miss what they missed.",
    ours: "They land on the exact frame the room is on, and nobody had to stop.",
  },
];

export function WhyNotScreenShare() {
  return (
    <section className="relative py-12 md:py-16 px-4 sm:px-6 lg:px-8 bg-[#090812] border-y border-purple-500/10">
      <div className="max-w-5xl mx-auto">
        <div className="text-center max-w-2xl mx-auto mb-10 md:mb-12 space-y-3">
          <p className="text-xs font-bold uppercase tracking-widest text-purple-400 font-mono">
            The obvious question
          </p>
          <h2 className="text-3xl sm:text-4xl font-extrabold text-white font-[family-name:var(--font-space-grotesk)]">
            Why not just share your screen?
          </h2>
          <p className="text-base text-gray-300 leading-relaxed">
            You can - people do it every night. It just turns one person into a
            broadcast server and everyone else into an audience.
          </p>
        </div>

        {/* Column headers, desktop only - on mobile each row carries its own labels. */}
        <div className="hidden md:grid grid-cols-[7rem_1fr_1fr] gap-x-6 mb-3 px-1">
          <div />
          <p className="text-xs font-bold uppercase tracking-widest text-gray-500 font-mono">
            Sharing a screen
          </p>
          <p className="text-xs font-bold uppercase tracking-widest text-purple-300 font-mono">
            SyncTogether
          </p>
        </div>

        <div className="divide-y divide-white/5 border-y border-white/5">
          {ROWS.map(({ aspect, sharing, ours }) => (
            <div
              key={aspect}
              className="grid md:grid-cols-[7rem_1fr_1fr] gap-x-6 gap-y-3 py-5 px-1"
            >
              <p className="text-sm font-bold text-white font-[family-name:var(--font-space-grotesk)] md:pt-0.5">
                {aspect}
              </p>

              <div className="flex gap-3">
                <X className="w-4 h-4 text-gray-600 shrink-0 mt-0.5" aria-hidden />
                <p className="text-sm text-gray-400 leading-relaxed">
                  <span className="md:hidden font-semibold text-gray-500">
                    Sharing a screen:{" "}
                  </span>
                  {sharing}
                </p>
              </div>

              <div className="flex gap-3">
                <Check className="w-4 h-4 text-purple-400 shrink-0 mt-0.5" aria-hidden />
                <p className="text-sm text-gray-200 leading-relaxed">
                  <span className="md:hidden font-semibold text-purple-300">
                    SyncTogether:{" "}
                  </span>
                  {ours}
                </p>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
