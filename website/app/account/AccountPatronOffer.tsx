"use client";

import { useState } from "react";
import { Check, Crown } from "lucide-react";
import { PTButton } from "@/components/PTButton";
import { display, mono } from "@/components/booth/Booth";
import { PRICING_TIERS } from "@/lib/constants";
import { usePremiumCheckout } from "@/lib/usePremiumCheckout";
import { usePricing } from "@/lib/usePricing";

/**
 * The free seat's upsell: the same Paddle branch PricingTable and the Tier
 * Configurator use (`usePremiumCheckout().goPremium`), with a monthly/annual
 * toggle. The one lit button on the account page.
 */
export function AccountPatronOffer() {
  const [cycle, setCycle] = useState<"monthly" | "annual">("annual");
  const { isLoadingCheckout, goPremium } = usePremiumCheckout();
  const { monthlyFormatted, annualFormatted } = usePricing();
  const l = PRICING_TIERS.premium.limits;
  const perks = [
    `${l.members} people, video facecams`,
    `Shows up to ${l.totalSessionMinutes / 60} hours`,
    `${l.rooms} rooms that never close`,
    "Your page at /u/handle",
  ];

  const option = (value: "monthly" | "annual", label: string) => (
    <button
      type="button"
      role="radio"
      aria-checked={cycle === value}
      onClick={() => setCycle(value)}
      className={`${mono} flex-1 py-2.5 text-[13px] rounded-[3px] transition-colors cursor-pointer ${
        cycle === value ? "bg-screen text-booth font-bold" : "text-gray-400 hover:text-white"
      }`}
    >
      {label}
    </button>
  );

  return (
    <div className="bg-seat border border-brass/60 border-t-2 border-t-brass rounded-[6px] p-6 sm:p-8">
      <p className={`${mono} flex items-center gap-2 text-[11px] tracking-[0.16em] uppercase text-brass`}>
        <Crown className="w-4 h-4" aria-hidden="true" /> Patron seats
      </p>
      <h2 className={`${display} mt-4 text-[36px] font-extrabold tracking-[-0.04em] leading-[0.92] text-white`}>
        Bring the whole group.
      </h2>
      <ul className="mt-5 space-y-2.5">
        {perks.map((p) => (
          <li key={p} className="flex items-center gap-3 text-[15px] text-gray-300">
            <Check className="w-4 h-4 text-brass shrink-0" aria-hidden="true" />
            {p}
          </li>
        ))}
      </ul>
      <div role="radiogroup" aria-label="Billing cycle" className="mt-6 flex gap-1 p-1 border border-rail rounded-[4px]">
        {option("monthly", `${monthlyFormatted} / mo`)}
        {option("annual", `${annualFormatted} / yr`)}
      </div>
      <PTButton
        onClick={() => goPremium(cycle)}
        isLoading={isLoadingCheckout}
        variant="primary"
        size="lg"
        className="mt-5 w-full"
      >
        Become a Patron
      </PTButton>
      <p className="mt-5 text-[13px] text-gray-500">Secure checkout by Paddle. Cancel any time, 14-day refund.</p>
    </div>
  );
}
