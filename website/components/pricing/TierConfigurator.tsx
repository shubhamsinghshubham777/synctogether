"use client";

import { useMemo, useState, type CSSProperties } from "react";
import { PRICING_TIERS, SITE_CONFIG } from "@/lib/constants";
import { cheapestTierFor, type ResolvableTier } from "@/lib/tier-resolver";
import { usePremiumCheckout } from "@/lib/usePremiumCheckout";
import { usePricing } from "@/lib/usePricing";
import { Crown, Download } from "lucide-react";
import { PTButton } from "@/components/PTButton";
import { Eyebrow, display, mono } from "@/components/PageHead";

const TIER_KEYS: ResolvableTier[] = ["guest", "free", "premium"];
// The board's seat chips: one initial on a flat fill each, cycled.
const SEATS = [
  { i: "M", bg: "bg-[#7A5CFF]" },
  { i: "S", bg: "bg-[#2E8A6E]" },
  { i: "P", bg: "bg-[#B8462E]" },
  { i: "J", bg: "bg-[#3F6FB0]" },
  { i: "A", bg: "bg-[#8A5A2E]" },
  { i: "R", bg: "bg-[#6B3F8A]" },
];

function formatTierSession(totalMinutes: number): string {
  if (totalMinutes >= 1440) return `${totalMinutes / 60} h`;
  if (totalMinutes >= 60 && totalMinutes % 60 === 0) return `${totalMinutes / 60} h`;
  return `${totalMinutes} min`;
}

export function TierConfigurator() {
  const [people, setPeople] = useState(6);
  const [hours, setHours] = useState(4);
  const { isLoadingCheckout, goPremium } = usePremiumCheckout();
  const { monthlyFormatted, currencySymbol, isLoading: isPriceLoading } = usePricing();

  const minutes = hours * 60;
  const cheapest = useMemo(() => cheapestTierFor(people, minutes), [people, minutes]);
  // Empty dashed seats show the room the recommended ticket still has.
  const capacity = cheapest ? PRICING_TIERS[cheapest].limits.members : 16;
  const empty = Math.max(0, capacity - people);

  const peoplePct = ((people - 2) / (16 - 2)) * 100;
  const hoursPct = ((hours - 1) / (24 - 1)) * 100;
  const patronPrice = isPriceLoading ? "…" : `${monthlyFormatted}/mo`;

  const slider = (
    id: string,
    label: string,
    value: number,
    unit: string,
    pct: number,
    min: number,
    max: number,
    set: (n: number) => void,
  ) => (
    <div className="flex flex-col gap-3.5">
      <label htmlFor={id} className="flex items-baseline justify-between gap-4 leading-[1.2]">
        <span className={`${mono} text-[11px] tracking-[0.14em] uppercase text-gray-500`}>{label}</span>
        <span>
          <span className={`${display} text-[34px] leading-[1.2] font-extrabold tracking-[-0.03em] tabular-nums text-white`}>{value}</span>{" "}
          <span className="text-[15px] text-gray-500">{unit}</span>
        </span>
      </label>
      <div className="pt-slider-wrap" style={{ "--pct": pct } as CSSProperties}>
        <div className="pt-slider-track" />
        <div className="pt-slider-fill" />
        <input
          id={id}
          type="range"
          min={min}
          max={max}
          step={1}
          value={value}
          onChange={(e) => set(Number(e.target.value))}
          aria-valuetext={`${value} ${unit}`}
          className="pt-slider"
        />
        <div className="pt-slider-thumb" />
      </div>
    </div>
  );

  return (
    <section className="grid lg:grid-cols-2 gap-10 lg:gap-[72px] items-start">
      <div className="flex flex-col gap-[30px] min-w-0">
        <div className="flex flex-col gap-3.5">
          <Eyebrow n="01">Find your seat</Eyebrow>
          <h2 className={`${display} text-4xl sm:text-[44px] font-extrabold tracking-[-0.04em] leading-[0.92]`}>
            Who&apos;s coming, and for how long?
          </h2>
          <p className="text-base leading-[1.55] text-gray-500">Drag either one and we&apos;ll tell you which ticket covers it.</p>
        </div>

        {slider("pt-people-range", "Party size", people, people === 1 ? "person" : "people", peoplePct, 2, 16, setPeople)}
        {slider("pt-hours-range", "Running time", hours, hours === 1 ? "hour" : "hours", hoursPct, 1, 24, setHours)}

        {/* The house: one seat per person, the ticket's spare seats dashed */}
        <div aria-hidden="true" className="flex flex-wrap gap-2.5">
          {Array.from({ length: people }, (_, n) => {
            const seat = SEATS[n % SEATS.length];
            return (
              <span
                key={n}
                className={`w-[30px] h-[30px] shrink-0 rounded-full ${seat.bg} shadow-[0_0_0_2px_var(--color-booth),0_0_0_4px_var(--color-cue)] flex items-center justify-center text-xs font-semibold text-screen animate-chip-in`}
                style={{ animationDelay: `${Math.min(n, 8) * 15}ms` }}
              >
                {seat.i}
              </span>
            );
          })}
          {Array.from({ length: empty }, (_, n) => (
            <span key={`e${n}`} className="w-[30px] h-[30px] shrink-0 rounded-full border border-dashed border-rail" />
          ))}
        </div>
      </div>

      <div className="min-w-0 flex flex-col gap-6">
        <ul className="border-t border-aisle">
          {TIER_KEYS.map((key) => {
            const tier = PRICING_TIERS[key];
            const sufficient = cheapest !== null && TIER_KEYS.indexOf(key) >= TIER_KEYS.indexOf(cheapest);
            const isCheapest = key === cheapest;
            const isPatron = key === "premium";
            const name = isPatron ? "Patron" : tier.name;
            const holds = tier.limits.members;
            const runs = formatTierSession(tier.limits.totalSessionMinutes);
            // Marks only where they say something: why a row is out, or that
            // the lit row covers both.
            const mark = (ok: boolean) => (!sufficient ? (ok ? "✓ " : "× ") : isCheapest ? "✓ " : "");
            const detail = `${mark(holds >= people)}holds ${holds} · ${mark(tier.limits.totalSessionMinutes >= minutes)}runs ${
              isPatron ? "up to " : ""
            }${runs}`;
            const price = isPatron ? patronPrice : `${currencySymbol}0`;

            return (
              <li key={key} className="border-b border-aisle">
                {/* A row is a preset: pressing it moves both sliders to that tier's ceiling. */}
                <button
                  type="button"
                  onClick={() => {
                    setPeople(Math.max(2, Math.min(16, tier.limits.members)));
                    setHours(Math.max(1, Math.min(24, Math.round(tier.limits.totalSessionMinutes / 60))));
                  }}
                  aria-pressed={isCheapest}
                  aria-label={`Show what ${name} covers: ${holds} people, ${runs} sessions`}
                  className={`w-full text-left flex justify-between gap-4 py-[18px] px-5 border-l-[3px] cursor-pointer transition-[background-color,opacity,border-color] duration-200 ${
                    isCheapest ? "bg-seat border-beam-500" : "border-transparent hover:bg-seat/60"
                  } ${sufficient ? "opacity-100" : "opacity-50 hover:opacity-80"}`}
                >
                  <span className="min-w-0">
                    <span
                      className={`${display} block text-[22px] leading-[1.2] font-extrabold tracking-[-0.02em] ${
                        !sufficient ? "text-gray-500" : isPatron ? "text-brass" : "text-white"
                      }`}
                    >
                      {name}
                      {isCheapest && (
                        <span className={`${mono} ml-2.5 text-[10px] tracking-[0.14em] uppercase text-beam-500`}>Your seat</span>
                      )}
                    </span>
                    <span className={`${mono} block mt-1.5 text-xs leading-[1.2] text-gray-500`}>{detail}</span>
                  </span>
                  <span
                    className={`${mono} text-[13px] ${
                      !sufficient ? "text-gray-500" : isPatron ? "text-brass" : "text-white"
                    }`}
                  >
                    {price}
                  </span>
                </button>
              </li>
            );
          })}
        </ul>

        <div className="flex flex-col sm:flex-row sm:items-center gap-5">
          {cheapest === null ? (
            <p className="text-[15px] text-gray-400">
              Rooms hold up to 16.{" "}
              <a href={`mailto:${SITE_CONFIG.supportEmail}`} className="text-white underline underline-offset-[6px] decoration-gray-600 hover:decoration-beam-500">
                Get in touch if you need more.
              </a>
            </p>
          ) : cheapest === "premium" ? (
            <PTButton
              variant="secondary"
              className="!h-[52px] !px-6 !rounded-[4px] !text-brass !border-[#6B5A2E]"
              isLoading={isLoadingCheckout || isPriceLoading}
              onClick={() => goPremium("annual")}
              leftIcon={<Crown aria-hidden="true" className="w-[18px] h-[18px]" strokeWidth={1.8} />}
            >
              Become a Patron
            </PTButton>
          ) : (
            <PTButton href="/download" variant="primary" className="!h-[52px] !px-6 !rounded-[4px] !text-base !font-semibold !gap-2.5"
              leftIcon={<Download aria-hidden="true" className="w-[18px] h-[18px]" strokeWidth={1.8} />}
            >
              Download free
            </PTButton>
          )}
          {cheapest !== "premium" && cheapest !== null && (
            <span className="text-[15px] text-gray-500">
              Need more?{" "}
              <button
                type="button"
                onClick={() => goPremium("annual")}
                disabled={isLoadingCheckout || isPriceLoading}
                className="text-white font-semibold underline underline-offset-[6px] decoration-gray-600 hover:decoration-beam-500 cursor-pointer"
              >
                Patron · {patronPrice}
              </button>
            </span>
          )}
        </div>
      </div>
    </section>
  );
}
