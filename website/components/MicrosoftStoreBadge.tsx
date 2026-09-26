import { MicrosoftLogo } from "@/components/Icons";
import { SITE_CONFIG } from "@/lib/constants";

interface MicrosoftStoreBadgeProps {
  className?: string;
}

/**
 * Microsoft Store link, set as a Booth Light outline button so it sits beside
 * the `.exe` download without competing with the one lit button on the page.
 * The brand mark keeps its own colours - it is never recoloured.
 */
export function MicrosoftStoreBadge({ className = "" }: MicrosoftStoreBadgeProps) {
  return (
    <a
      href={SITE_CONFIG.microsoftStoreUrl}
      target="_blank"
      rel="noopener noreferrer"
      aria-label="Get SyncTogether from the Microsoft Store"
      className={`inline-flex items-center justify-center gap-2.5 h-[54px] rounded-[4px] border border-[#5A4F44] px-[22px] text-base font-semibold text-white transition-colors duration-150 hover:border-gray-600 hover:bg-white/5 active:translate-y-px focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-beam-500/60 select-none ${className}`}
    >
      <MicrosoftLogo className="h-4 w-4 shrink-0" />
      <span>Microsoft Store</span>
    </a>
  );
}
