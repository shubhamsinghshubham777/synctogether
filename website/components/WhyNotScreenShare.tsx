import { X, Check } from "lucide-react";

/**
 * The objection every visitor is actually holding. A three-row contrast rather
 * than another card grid. Screen sharing is named as a technique, never as a
 * product.
 */
const ROWS: { aspect: string; sharing: string; ours: string }[] = [
  {
    aspect: "Picture",
    sharing: "Re-encoded on the fly, squeezed through the host's upload.",
    ours: "Every machine plays the file natively. 4K stays 4K.",
  },
  {
    aspect: "The remote",
    sharing: "One person drives. Everyone else asks them to pause.",
    ours: "Anyone can play, pause and scrub, or the host locks the remote.",
  },
  {
    aspect: "Turning up late",
    sharing: "Rewind for everybody, or miss what they missed.",
    ours: "They land where the room is. Nobody stops.",
  },
];

const mono = "font-[family-name:var(--font-jetbrains-mono)]";

export function WhyNotScreenShare() {
  return (
    <section className="relative pt-12 md:pt-14 pb-8">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="mb-6 space-y-3.5">
          <p className={`${mono} text-xs tracking-[0.16em] text-beam-500 uppercase`}>
            <span className="text-[#5A4F44]">03 · </span>The obvious question
          </p>
          <h2 className="text-4xl sm:text-5xl font-extrabold tracking-[-0.035em] leading-[0.95] text-screen font-[family-name:var(--font-space-grotesk)]">
            Why not just share your screen?
          </h2>
        </div>

        <div className="hidden md:grid grid-cols-[11rem_1fr_1fr] gap-x-8 pb-3">
          <div />
          <p className={`${mono} text-[11px] tracking-[0.16em] uppercase text-gray-500`}>Sharing a screen</p>
          <p className={`${mono} text-[11px] tracking-[0.16em] uppercase text-beam-500`}>SyncTogether</p>
        </div>

        <div className="divide-y divide-aisle border-y border-aisle">
          {ROWS.map(({ aspect, sharing, ours }) => (
            <div key={aspect} className="grid md:grid-cols-[11rem_1fr_1fr] gap-x-8 gap-y-2 py-4">
              <p className="text-sm font-bold text-screen">{aspect}</p>
              <div className="flex gap-3">
                <X className="w-4 h-4 text-gray-600 shrink-0 mt-0.5" aria-hidden />
                <p className="text-sm text-gray-400 leading-relaxed">
                  <span className="sr-only">Sharing a screen: </span>
                  {sharing}
                </p>
              </div>
              <div className="flex gap-3">
                <Check className="w-4 h-4 text-cue shrink-0 mt-0.5" aria-hidden />
                <p className="text-sm text-gray-200 leading-relaxed">
                  <span className="sr-only">SyncTogether: </span>
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
