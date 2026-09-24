"use client";

import { useMemo, useState, type CSSProperties } from "react";
import { Users, Clock, Sparkles, Lock, Crown } from "lucide-react";
import { PRICING_TIERS, SITE_CONFIG } from "@/lib/constants";
import { cheapestTierFor, type ResolvableTier } from "@/lib/tier-resolver";
import { usePremiumCheckout } from "@/lib/usePremiumCheckout";
import { usePricing } from "@/lib/usePricing";
import { PTButton } from "@/components/PTButton";

const TIER_KEYS: ResolvableTier[] = ["guest", "free", "premium"];
const AVATAR_COUNT = 6;

function formatSession(hours: number): string {
  if (hours === 24) return "1 day";
  return `${hours} hour${hours === 1 ? "" : "s"}`;
}

function formatTierSession(totalMinutes: number): string {
  if (totalMinutes >= 1440) return `${totalMinutes / 60}h`;
  if (totalMinutes >= 60 && totalMinutes % 60 === 0) return `${totalMinutes / 60}h`;
  return `${totalMinutes}m`;
}

export function TierConfigurator() {
  const [people, setPeople] = useState(6);
  const [hours, setHours] = useState(4);
  const { isLoadingCheckout, goPremium } = usePremiumCheckout();
  const { monthlyFormatted, isLoading: isPriceLoading } = usePricing();

  const minutes = hours * 60;
  const cheapest = useMemo(() => cheapestTierFor(people, minutes), [people, minutes]);

  const peoplePct = ((people - 2) / (16 - 2)) * 100;
  const hoursPct = ((hours - 1) / (24 - 1)) * 100;

  return (
    <div className="relative max-w-5xl mx-auto">
      <div className="glow-blob-purple -top-20 left-1/4 opacity-20" />
      <div className="glow-blob-cyan -bottom-10 right-1/4 opacity-15" />

      <div className="relative glass-panel rounded-3xl p-6 sm:p-10 space-y-10 overflow-hidden">
        <div className="text-center space-y-2">
          <h2 className="text-2xl sm:text-3xl font-extrabold text-white font-[family-name:var(--font-space-grotesk)]">
            Find your fit.
          </h2>
          <p className="text-sm text-gray-400">Drag either slider - we&apos;ll tell you what you need.</p>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div className="rounded-2xl bg-white/[0.03] border border-white/10 p-5 space-y-4">
            <label htmlFor="pt-people-range" className="flex items-center justify-between text-sm text-gray-300">
              <span className="flex items-center gap-2">
                <Users className="w-4 h-4 text-purple-300" />
                How many people?
              </span>
              <span className="font-mono text-base font-bold text-white bg-purple-500/15 border border-purple-400/30 rounded-lg px-2.5 py-0.5">
                {people}
              </span>
            </label>
            <div className="pt-slider-wrap" style={{ "--pct": peoplePct } as CSSProperties}>
              <div className="pt-slider-track" />
              <div className="pt-slider-fill" />
              <input
                id="pt-people-range"
                type="range"
                min={2}
                max={16}
                step={1}
                value={people}
                onChange={(e) => setPeople(Number(e.target.value))}
                aria-valuetext={`${people} people`}
                className="pt-slider"
              />
              <div className="pt-slider-thumb" />
            </div>
          </div>

          <div className="rounded-2xl bg-white/[0.03] border border-white/10 p-5 space-y-4">
            <label htmlFor="pt-hours-range" className="flex items-center justify-between text-sm text-gray-300">
              <span className="flex items-center gap-2">
                <Clock className="w-4 h-4 text-purple-300" />
                How long are you watching?
              </span>
              <span className="font-mono text-base font-bold text-white bg-purple-500/15 border border-purple-400/30 rounded-lg px-2.5 py-0.5">
                {formatSession(hours)}
              </span>
            </label>
            <div className="pt-slider-wrap" style={{ "--pct": hoursPct } as CSSProperties}>
              <div className="pt-slider-track" />
              <div className="pt-slider-fill" />
              <input
                id="pt-hours-range"
                type="range"
                min={1}
                max={24}
                step={1}
                value={hours}
                onChange={(e) => setHours(Number(e.target.value))}
                aria-valuetext={formatSession(hours)}
                className="pt-slider"
              />
              <div className="pt-slider-thumb" />
            </div>
          </div>
        </div>

        {/* Room preview */}
        <div className="flex flex-wrap items-center justify-center gap-2 min-h-[2.75rem]">
          {Array.from({ length: people }, (_, i) => (
            // eslint-disable-next-line @next/next/no-img-element -- tiny fixed-size avatar chip, count changes on every drag tick
            <img
              key={i}
              src={`/avatars/av-0${(i % AVATAR_COUNT) + 1}.avif`}
              alt=""
              width={36}
              height={36}
              className="w-9 h-9 rounded-full border border-white/10 object-cover animate-chip-in shadow-lg shadow-black/40"
              style={{ animationDelay: `${Math.min(i, 8) * 15}ms` }}
            />
          ))}
        </div>

        {/* Tier cards */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          {TIER_KEYS.map((key) => {
            const tier = PRICING_TIERS[key];
            const sufficient = cheapest !== null && TIER_KEYS.indexOf(key) >= TIER_KEYS.indexOf(cheapest);
            const isCheapest = key === cheapest;
            const membersShort = tier.limits.members < people;
            const sessionShort = tier.limits.totalSessionMinutes < minutes;
            const priceLabel =
              key === "premium" ? (isPriceLoading ? "…" : `${monthlyFormatted}/mo`) : "Free";

            return (
              // A card is a preset: pressing it moves both sliders to that tier's
              // ceiling, which also makes it the recommendation and swaps the CTA.
              <button
                type="button"
                key={key}
                onClick={() => {
                  setPeople(Math.max(2, Math.min(16, tier.limits.members)));
                  setHours(Math.max(1, Math.min(24, Math.round(tier.limits.totalSessionMinutes / 60))));
                }}
                aria-pressed={isCheapest}
                aria-label={`Show what ${tier.name} covers: ${tier.limits.members} people, ${formatTierSession(tier.limits.totalSessionMinutes)} sessions`}
                className={`group relative text-left rounded-2xl border p-5 space-y-3 cursor-pointer hover:-translate-y-0.5 hover:border-purple-300/50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-purple-300 transition-[transform,box-shadow,border-color,opacity] duration-300 ease-out ${
                  isCheapest
                    ? "border-purple-400/60 bg-gradient-to-b from-purple-500/15 to-transparent shadow-[0_0_32px_-8px_rgba(139,92,246,0.5)] scale-[1.03]"
                    : "border-white/10 bg-white/[0.02] scale-100"
                } ${sufficient ? "opacity-100" : "opacity-55 hover:opacity-90"}`}
              >
                {isCheapest && (
                  <span className="absolute -top-3 left-1/2 -translate-x-1/2 inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full bg-purple-500 text-white text-[10px] font-bold uppercase tracking-wider shadow-lg">
                    <Sparkles className="w-3 h-3" /> Recommended
                  </span>
                )}

                <div className="flex items-center justify-between">
                  <span className="flex items-center gap-1.5 font-bold text-white font-[family-name:var(--font-space-grotesk)]">
                    {key === "premium" && <Crown className="w-4 h-4 text-[color:var(--pt-premium)]" />}
                    {tier.name}
                  </span>
                  <span className={`font-mono text-xs font-bold ${key === "premium" ? "text-[color:var(--pt-premium)]" : "text-gray-400"}`}>
                    {priceLabel}
                  </span>
                </div>

                <div className="flex items-center gap-3 text-xs">
                  <span className={`flex items-center gap-1 ${membersShort ? "text-amber-300/90" : "text-gray-400"}`}>
                    {membersShort ? <Lock className="w-3.5 h-3.5" /> : <Users className="w-3.5 h-3.5" />}
                    {tier.limits.members}
                  </span>
                  <span className={`flex items-center gap-1 ${sessionShort ? "text-amber-300/90" : "text-gray-400"}`}>
                    {sessionShort ? <Lock className="w-3.5 h-3.5" /> : <Clock className="w-3.5 h-3.5" />}
                    {formatTierSession(tier.limits.totalSessionMinutes)}
                  </span>
                </div>

                {/* One line, same two sentences, on every card at every setting -
                    a card with an extra sentence is a card of a different height,
                    and one that appears and disappears as the sliders move reflows
                    all three. The amber is what carries "this is the limit you just
                    crossed", spelled out in words because the amber number above it
                    is invisible to a screen reader. */}
                <p className="text-[11px] leading-snug">
                  <span className={membersShort ? "text-amber-200/80" : "text-gray-500"}>
                    {tier.name} rooms hold {tier.limits.members}.
                  </span>{" "}
                  <span className={sessionShort ? "text-amber-200/80" : "text-gray-500"}>
                    Sessions run {formatTierSession(tier.limits.totalSessionMinutes)}.
                  </span>
                </p>

                <span className="block text-[11px] font-medium text-purple-300/0 group-hover:text-purple-300/90 group-focus-visible:text-purple-300/90 transition-colors">
                  {isCheapest ? "Your pick" : `Try ${tier.name} →`}
                </span>
              </button>
            );
          })}
        </div>

        {/* CTA */}
        <div className="text-center">
          {cheapest === null ? (
            <p className="text-sm text-gray-400">
              Rooms hold up to 16.{" "}
              <a href={`mailto:${SITE_CONFIG.supportEmail}`} className="text-purple-300 hover:underline">
                Get in touch if you need more.
              </a>
            </p>
          ) : cheapest === "premium" ? (
            <PTButton
              variant="gold"
              size="lg"
              isLoading={isLoadingCheckout || isPriceLoading}
              onClick={() => goPremium("annual")}
            >
              Go Premium
            </PTButton>
          ) : (
            <PTButton href="/download" variant="primary" size="lg">
              Download free
            </PTButton>
          )}
          {cheapest !== "premium" && cheapest !== null && (
            <p className="mt-3 text-xs text-gray-500">
              Need more?{" "}
              <button
                type="button"
                onClick={() => goPremium("annual")}
                disabled={isLoadingCheckout || isPriceLoading}
                className="text-[color:var(--pt-premium)] font-semibold hover:underline cursor-pointer"
              >
                Go Premium{isPriceLoading ? "" : ` - ${monthlyFormatted}/mo`}
              </button>
            </p>
          )}
        </div>
      </div>
    </div>
  );
}
