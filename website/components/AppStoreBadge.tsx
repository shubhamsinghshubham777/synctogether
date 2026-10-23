import { AppleLogo } from "@/components/Icons";
import { SITE_CONFIG } from "@/lib/constants";

interface AppStoreBadgeProps {
  className?: string;
  /** The one lit button on the page. Everything else stays outline. */
  lit?: boolean;
}

/**
 * Mac App Store link, set like `MicrosoftStoreBadge` so the two doors match.
 * The Apple mark keeps its own shape and is never recoloured.
 */
export function AppStoreBadge({ className = "", lit = false }: AppStoreBadgeProps) {
  const tone = lit
    ? "bg-beam-500 border-beam-500 text-booth hover:bg-beam-400"
    : "border-[#5A4F44] text-white hover:border-gray-600 hover:bg-white/5";
  return (
    <a
      href={SITE_CONFIG.appStoreUrl}
      target="_blank"
      rel="noopener noreferrer"
      aria-label="Get SyncTogether from the App Store"
      className={`inline-flex items-center justify-center gap-2.5 h-[54px] rounded-[4px] border px-[22px] text-base font-semibold transition-colors duration-150 active:translate-y-px focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-beam-500/60 select-none ${tone} ${className}`}
    >
      <AppleLogo className="h-[18px] w-[18px] shrink-0" />
      <span>App Store</span>
    </a>
  );
}
