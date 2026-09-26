import React from "react";
import { Check, Crown } from "lucide-react";
import { PTButton } from "./PTButton";

interface PlanCardProps {
  name: string;
  badge?: string;
  price: React.ReactNode;
  subPrice?: React.ReactNode;
  periodText?: string;
  description: string;
  features: string[];
  ctaText: string;
  isPopular?: boolean;
  isPremium?: boolean;
  isLoading?: boolean;
  className?: string;
  onSelect: () => void;
}

const display = "font-[family-name:var(--font-space-grotesk)]";
const mono = "font-[family-name:var(--font-jetbrains-mono)]";

/**
 * One ticket on the playbill. Each card carries a 3px rule across its head:
 * Rail for Guest, Beam for the popular (lit-button) plan, Brass for Patron.
 * Only the popular card gets the page's filled Beam button; Patron is an
 * outline in Brass.
 */
export function PlanCard({
  name,
  badge,
  price,
  subPrice,
  periodText = "/month",
  description,
  features,
  ctaText,
  isPopular = false,
  isPremium = false,
  isLoading = false,
  className = "",
  onSelect,
}: PlanCardProps) {
  const tone = isPremium ? "text-brass" : isPopular ? "text-beam-500" : "text-gray-500";
  const rule = isPremium ? "border-t-brass" : isPopular ? "border-t-beam-500" : "border-t-rail";
  return (
    <div className={`flex flex-col gap-[18px] p-7 bg-seat border border-rail border-t-[3px] ${rule} rounded-md ${className}`}>
      <p className={`${mono} min-h-4 text-[11px] tracking-[0.14em] uppercase ${tone}`}>{badge}</p>

      <h3
        className={`${display} flex items-center gap-2.5 text-[40px] font-extrabold tracking-[-0.04em] leading-[0.92] ${
          isPremium ? "text-brass" : "text-white"
        }`}
      >
        {name}
        {isPremium && <Crown aria-hidden="true" className="w-[22px] h-[22px]" strokeWidth={1.8} />}
      </h3>
      <p className="text-[15px] text-gray-400 leading-[1.55] lg:min-h-[2.9rem]">{description}</p>

      <div className="h-px bg-rail shrink-0" />

      <div>
        <div className="flex items-baseline gap-2 flex-wrap">
          <span className={`${display} text-[52px] font-extrabold tracking-[-0.04em] leading-[1.2] text-white`}>{price}</span>
          {periodText && <span className={`${mono} text-xs text-gray-500`}>{periodText}</span>}
        </div>
        <p className={`${mono} mt-1.5 text-xs text-gray-500 min-h-4`}>{subPrice}</p>
      </div>

      <ul className="flex flex-col gap-[14px] flex-1">
        {features.map((feature) => (
          <li key={feature} className="flex gap-2.5 items-start text-[15px] text-gray-300 leading-[1.4]">
            <Check
              aria-hidden="true"
              strokeWidth={1.8}
              className={`mt-px w-4 h-4 shrink-0 ${isPremium ? "text-brass" : "text-cue"}`}
            />
            <span>{feature}</span>
          </li>
        ))}
      </ul>

      <PTButton
        variant={isPopular ? "primary" : "secondary"}
        className={`w-full !h-12 !rounded-[4px] !text-[15px] !font-semibold ${
          isPremium ? "!text-brass !border-[#6B5A2E]" : isPopular ? "" : "!border-[#5A4F44]"
        }`}
        isLoading={isLoading}
        onClick={onSelect}
      >
        {ctaText}
      </PTButton>
    </div>
  );
}
