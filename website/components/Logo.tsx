import Link from "next/link";

interface LogoProps {
  className?: string;
  size?: "sm" | "md" | "lg" | "xl";
  /** False renders the square mark (s·t) instead of the wordmark. */
  showText?: boolean;
  asLink?: boolean;
}

const wordSize = { sm: "text-lg", md: "text-[19px] sm:text-2xl", lg: "text-3xl", xl: "text-4xl" };
const markSize = { sm: "w-8 h-8 text-sm", md: "w-10 h-10 text-base", lg: "w-14 h-14 text-2xl", xl: "w-20 h-20 text-3xl" };

/**
 * The Booth Light brand: a lowercase wordmark whose middle dot is the Beam -
 * the one light in the room. No tile, no gradient. The square mark (for the
 * app icon, favicons, auth screens) is the same idea compressed to "s·t".
 *
 * On hover the dot brightens and spills, like a projector warming up; it is a
 * transition, never a loop.
 */
export function Logo({ className = "", size = "md", showText = true, asLink = true }: LogoProps) {
  const content = showText ? (
    <span
      className={`${wordSize[size]} font-extrabold tracking-[-0.035em] text-white font-[family-name:var(--font-space-grotesk)] leading-none whitespace-nowrap`}
    >
      sync
      <span className="logo-dot text-beam-500">·</span>
      together
    </span>
  ) : (
    <SyncTogetherMark className={markSize[size]} />
  );

  if (!asLink) {
    return <div className={`inline-flex items-center group ${className}`}>{content}</div>;
  }
  return (
    <Link
      href="/"
      aria-label="SyncTogether home"
      className={`inline-flex items-center group rounded-sm focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-beam-500 ${className}`}
    >
      {content}
    </Link>
  );
}

/** The square mark: Screen "s·t" with a Beam dot on a Booth tile. */
export function SyncTogetherMark({ className = "" }: { className?: string }) {
  return (
    <span
      aria-hidden="true"
      className={`inline-flex shrink-0 items-center justify-center rounded-md bg-booth ring-1 ring-inset ring-rail font-extrabold tracking-[-0.04em] text-white font-[family-name:var(--font-space-grotesk)] ${className}`}
    >
      s<span className="logo-dot text-beam-500">·</span>t
    </span>
  );
}

/** Kept for existing imports; the mark replaced the old play-button tile. */
export const SyncTogetherIcon = SyncTogetherMark;
