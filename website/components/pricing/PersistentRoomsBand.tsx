import Image from "next/image";
import { Crown } from "lucide-react";
import { PRICING_TIERS } from "@/lib/constants";

/**
 * The one place on the site where character art earns its keep. Persistent rooms are
 * the highest-LTV feature, and the audience that recognises itself here is the one
 * watching across a time zone - so this band leads with the emotional line and lets
 * the number sit underneath it, per the positioning doctrine.
 *
 * Every figure reads from PRICING_TIERS: lib/constants.ts is the single source of
 * truth and the app's tier_limits table is tuned independently of deploys.
 *
 * Deliberately not a .glass-panel: the pricing page already spends its backdrop-filter
 * budget on the configurator above, and the art is the surface here.
 */
export function PersistentRoomsBand() {
  const { limits } = PRICING_TIERS.premium;

  return (
    <section className="relative max-w-5xl mx-auto">
      <div className="relative rounded-3xl overflow-hidden border border-white/10 bg-white/[0.02] grid grid-cols-1 md:grid-cols-2 items-center">
        <div className="relative aspect-[3/2] md:aspect-auto md:h-full md:min-h-[20rem]">
          <Image
            src="/art/pair-room.avif"
            alt="Two rooms lit by the same screen - morning through one window, night through the other."
            fill
            sizes="(max-width: 768px) 100vw, 480px"
            className="object-cover object-center"
          />
          {/* Carries the art into the copy column instead of ending on a hard seam.
              The fade has to land on the edge the copy sits against - bottom when
              stacked, right on desktop - or it dims the daylight room instead. */}
          <div className="absolute inset-0 bg-gradient-to-t md:bg-gradient-to-l from-[#0A0814] via-[#0A0814]/20 to-transparent" />
        </div>

        <div className="relative p-6 sm:p-10 space-y-4">
          <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full border border-[color:var(--pt-premium-border)]/50 bg-[color:var(--pt-premium)]/10 text-[10px] font-bold uppercase tracking-wider text-[color:var(--pt-premium)]">
            <Crown className="w-3 h-3" />
            Premium
          </span>

          <h2 className="text-2xl sm:text-3xl font-extrabold text-white font-[family-name:var(--font-space-grotesk)]">
            Your room is still there.
          </h2>

          <p className="text-sm sm:text-base text-gray-300 leading-relaxed">
            Premium rooms don&apos;t end when the night does. Close the app, sleep, cross a
            time zone - the room keeps its name and its place, and whoever opens it next
            picks up where you stopped.
          </p>

          <ul className="flex flex-wrap gap-x-5 gap-y-2 text-xs font-mono text-gray-400">
            <li>{limits.rooms} persistent rooms</li>
            <li>Custom names</li>
            <li>Never expires</li>
          </ul>
        </div>
      </div>
    </section>
  );
}
