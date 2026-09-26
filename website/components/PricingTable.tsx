"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { PRICING_TIERS } from "@/lib/constants";
import { PlanCard } from "./PlanCard";
import { Eyebrow, display, mono } from "./PageHead";
import { LocationDebugSwitcher } from "./LocationDebugSwitcher";
import { usePricing } from "@/lib/usePricing";
import { usePremiumCheckout } from "@/lib/usePremiumCheckout";
import { Loader2 } from "lucide-react";

export function PricingTable() {
  const [billingCycle, setBillingCycle] = useState<"monthly" | "annual">("annual");
  const router = useRouter();
  const { user, isPremium, isLoadingCheckout, goPremium } = usePremiumCheckout();
  const {
    monthlyFormatted,
    annualFormatted,
    monthlyEquivalentFormatted,
    monthlyAmount,
    annualAmount,
    currencyCode,
    currencySymbol,
    countryCode,
    isLoading: isPriceLoading,
  } = usePricing();

  const handleSelectPlan = async (tierKey: string) => {
    if (tierKey === "guest" || tierKey === "free") {
      router.push("/download");
      return;
    }
    if (tierKey === "premium") {
      await goPremium(billingCycle);
    }
  };

  const premiumPrice = isPriceLoading ? (
    <span className="inline-flex items-center py-1 text-brass">
      <Loader2 className="w-8 h-8 animate-spin" />
    </span>
  ) : billingCycle === "annual" ? (
    annualFormatted
  ) : (
    monthlyFormatted
  );

  // The discount is derived from the very two amounts the cards display, never
  // from a separately-carried figure: the live page once read "-58%" (the INR
  // ratio, 199x12 vs 999) beside USD prices. Computing it here from
  // monthlyAmount/annualAmount means the chip can only disagree with the
  // prices if the prices themselves are wrong.
  const savingsPct =
    monthlyAmount > 0 && annualAmount > 0
      ? `${Math.max(1, Math.round((1 - annualAmount / (monthlyAmount * 12)) * 100))}%`
      : null;

  const isUsdOutsideUs = currencyCode === "USD" && countryCode !== "US";
  // Free tiers speak the same currency as the Patron card beside them.
  const zeroPrice = `${isUsdOutsideUs ? "US$" : currencySymbol}0`;
  const premiumSubPrice = isPriceLoading
    ? "Fetching live pricing..."
    : billingCycle === "annual"
    ? `${monthlyEquivalentFormatted} billed annually${isUsdOutsideUs ? " in USD" : ""}${savingsPct ? ` · save ${savingsPct}` : ""}`
    : isUsdOutsideUs
    ? "Billed monthly in USD. Cancel anytime."
    : "Billed monthly. Cancel anytime.";

  return (
    <section className="space-y-6">
      <div className="flex flex-col md:flex-row md:items-end justify-between gap-6">
        <div className="flex flex-col gap-3.5">
          <Eyebrow n="02">The plans</Eyebrow>
          <h2 className={`${display} text-4xl sm:text-[52px] font-extrabold tracking-[-0.04em] leading-[0.92]`}>
            Three tickets. Two of them free.
          </h2>
        </div>

        <div className="flex flex-col sm:flex-row sm:items-center gap-3">
          {/* Monthly / annual */}
          <div role="group" aria-label="Billing cycle" className={`${mono} inline-flex self-start p-[3px] rounded-[4px] border border-rail text-xs`}>
            <button
              onClick={() => setBillingCycle("monthly")}
              aria-pressed={billingCycle === "monthly"}
              className={`h-[34px] px-4 rounded-[2px] transition-colors cursor-pointer ${
                billingCycle === "monthly" ? "bg-screen text-booth font-semibold" : "text-gray-500 hover:text-white"
              }`}
            >
              Monthly
            </button>
            <button
              onClick={() => setBillingCycle("annual")}
              aria-pressed={billingCycle === "annual"}
              className={`h-[34px] px-4 rounded-[2px] transition-colors flex items-center gap-2 cursor-pointer ${
                billingCycle === "annual" ? "bg-screen text-booth font-semibold" : "text-gray-500 hover:text-white"
              }`}
            >
              <span>Annual</span>
              {savingsPct && !isPriceLoading && (
                <span className={billingCycle === "annual" ? "text-[#A33A22]" : "text-signal"}>−{savingsPct}</span>
              )}
            </button>
          </div>

          <LocationDebugSwitcher />
        </div>
      </div>

      {/* The playbill: three tickets. Phones stack Free, Patron, Guest. */}
      <div className="space-y-4">
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <PlanCard
            className="order-3 md:order-1"
            name={PRICING_TIERS.guest.name}
            badge={PRICING_TIERS.guest.badge}
            price={zeroPrice}
            periodText="forever"
            description="Join with a six-letter code in seconds. For a quick one."
            features={CARD_FEATURES.guest}
            ctaText="Download the app"
            onSelect={() => handleSelectPlan("guest")}
          />
          <PlanCard
            className="order-1 md:order-2"
            name={PRICING_TIERS.free.name}
            badge="Most nights"
            price={zeroPrice}
            periodText="with a free account"
            description="Friend groups and watch parties, with voice beside the film."
            features={CARD_FEATURES.free}
            ctaText={PRICING_TIERS.free.cta}
            isPopular
            onSelect={() => handleSelectPlan("free")}
          />
          <PlanCard
            className="order-2 md:order-3"
            name="Patron"
            badge={isPremium ? "Your plan" : "The whole theatre"}
            price={premiumPrice}
            periodText={billingCycle === "annual" ? "/ year" : "/ month"}
            subPrice={premiumSubPrice}
            description="Video facecams, 16 seats, all-day shows and rooms that never close."
            features={CARD_FEATURES.premium}
            ctaText={isPremium ? "Manage Subscription" : user ? "Become a Patron" : "Sign in to become a Patron"}
            isPremium
            isLoading={isLoadingCheckout}
            onSelect={() => handleSelectPlan("premium")}
          />
        </div>
        {/* Wording follows app/refund/page.tsx: cancel any time, perks run to
            the end of the paid period, 14-day refund on a first purchase. */}
        <p className="text-sm text-gray-500 leading-relaxed">
          Cancel any time. You keep Premium until the end of the period you paid for. First purchase?{" "}
          <Link href="/refund" className="underline underline-offset-2 hover:text-white">14-day refund</Link>, no questions asked.
        </p>
      </div>

      {/* Comparison */}
      <div className="pt-2 space-y-4">
        <h3 className={`${display} text-3xl sm:text-[36px] font-extrabold tracking-[-0.04em] leading-[0.92]`}>Side by side.</h3>

        {/* One ruled table at every width: four columns fit 360px because the
            cells are short and the text steps down on phones. */}
        <table className="w-full table-fixed text-left text-[12px] sm:text-[15px]">
          <colgroup>
            <col className="w-[34%] sm:w-[31.8%]" />
            <col />
            <col />
            <col />
          </colgroup>
          <thead className={`${mono} text-[9px] sm:text-[11px] tracking-[0.14em] uppercase`}>
            <tr className="border-b border-rail">
              <th className="py-3.5 pr-3 font-normal text-gray-500">The seat</th>
              <th className="py-3.5 px-3 font-normal text-gray-500">Guest</th>
              <th className="py-3.5 px-3 font-normal text-beam-500">Free</th>
              <th className="py-3.5 pl-3 font-normal text-brass">Patron</th>
            </tr>
          </thead>
          <tbody>
            {COMPARISON.map((row) => (
              <tr key={row.feature} className="align-top border-b border-aisle leading-snug">
                <th scope="row" className="py-[11px] pr-3 font-semibold text-white">{row.feature}</th>
                {row.values.map((v, i) => (
                  <td key={i} className={`py-[11px] px-3 last:pr-0 break-words ${cellTone(v, i)}`}>
                    {cellText(v)}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}

/** Short lists for the cards; the full story is in the table below. */
const CARD_FEATURES = {
  guest: ["1 live room at a time", "Up to 4 people per room", "60-minute shows", "Local files & YouTube", "Chat and 8 reactions"],
  free: ["4 live rooms", "Up to 8 people per room", "4-hour shows, room waits 24 h", "Voice facecams", "Upload your film: 2.5 GB a week"],
  premium: [
    "20 rooms, kept for good",
    "Up to 16 people per room",
    "Shows up to 24 hours",
    "Voice + video facecams",
    "24 animated reactions",
    "Unlimited uploads, 10 GB a file",
    "Your page at /u/handle",
    "Your perks shared with the whole room",
  ],
};

/** `null` is "not on this plan", `true` is "included". */
type Cell = string | null | true;

// Mirrors tier_limits: guest dormant_hours 0 (room closes at expiry), free
// 24 h dormant, premium persistent. Handles are Patron-only (claim_handle).
const COMPARISON: { feature: string; values: [Cell, Cell, Cell] }[] = [
  { feature: "Live rooms", values: ["1", "4", "20, kept for good"] },
  { feature: "People per room", values: ["4", "8", "16"] },
  { feature: "Session length", values: ["60 min", "4 hours", "up to 24 hours"] },
  { feature: "Facecams", values: [null, "Voice", "Voice + video"] },
  { feature: "Room waits between shows", values: [null, "24 hours", "Never closes"] },
  { feature: "Upload your film for the room", values: [null, "2.5 GB / week · 2 GB file", "Unlimited · 10 GB file"] },
  { feature: "Local files + YouTube", values: [true, true, true] },
  { feature: "Public page at /u/handle", values: [null, null, true] },
];

function cellText(v: Cell) {
  if (v === null) return <span aria-label="Not included">×</span>;
  if (v === true) return <span aria-label="Included">Included</span>;
  return v;
}

// Guest reads muted, Free in Screen, Patron in Brass: the board's columns.
function cellTone(v: Cell, i: number) {
  if (v === null) return "text-[#5A4F44]";
  return ["text-gray-400", "text-white", "text-brass"][i];
}
