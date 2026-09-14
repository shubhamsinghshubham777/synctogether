import { MicrosoftLogo } from "@/components/Icons";
import { SITE_CONFIG } from "@/lib/constants";

interface MicrosoftStoreBadgeProps {
  className?: string;
}

/**
 * Microsoft Store badge, laid out like Microsoft's own "Get it from" badge
 * (brand mark + two-line lockup) on a Fluent-style dark surface, so it reads
 * as a store badge rather than one more purple button. The hairline of the
 * four brand colors sliding in on hover is the only flourish - the mark itself
 * is never recolored or rotated.
 */
export function MicrosoftStoreBadge({
  className = "",
}: MicrosoftStoreBadgeProps) {
  return (
    <a
      href={SITE_CONFIG.microsoftStoreUrl}
      target="_blank"
      rel="noopener noreferrer"
      aria-label="Get SyncTogether from the Microsoft Store"
      className={`ms-store-badge group relative isolate flex items-center gap-3.5 overflow-hidden rounded-xl border border-white/15 px-5 py-3 select-none focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#00A4EF]/70 focus-visible:ring-offset-2 focus-visible:ring-offset-[#0B0917] active:scale-[0.98] ${className}`}
    >
      <MicrosoftLogo className="h-6 w-6 shrink-0 drop-shadow-[0_0_10px_rgba(0,164,239,0.25)]" />

      <span className="flex min-w-0 flex-col items-start leading-none">
        <span className="text-[10px] font-medium uppercase tracking-[0.18em] text-gray-400 transition-colors duration-200 group-hover:text-gray-300">
          Get it from
        </span>
        <span className="mt-1 text-base font-semibold text-white font-[family-name:var(--font-space-grotesk)]">
          Microsoft Store
        </span>
      </span>

      {/* Four-color hairline, Fluent's accent stroke */}
      <span
        aria-hidden="true"
        className="ms-store-badge__accent pointer-events-none absolute inset-x-0 bottom-0 h-[2px]"
      />
    </a>
  );
}
