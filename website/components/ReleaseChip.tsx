import Link from "next/link";

export interface ReleaseChipProps {
  /** Tag or version label, e.g. "v1.7.1". */
  tag?: string;
  /** Optional link destination, defaults to "/changelog". */
  href?: string;
  /** Optional additional class names. */
  className?: string;
}

/**
 * Announcement tag for the latest release: a Cue dot and mono label on a Rail
 * outline, linking to the changelog. Static - nothing pulses.
 */
export function ReleaseChip({
  tag,
  href = "/changelog",
  className = "",
}: ReleaseChipProps) {
  const cleanTag = tag ? (tag.startsWith("SyncTogether ") ? tag.replace(/^SyncTogether\s+/, "") : tag) : "";
  const version = cleanTag.replace(/^v/i, "");
  const label = version ? `V${version} is out` : "New release out";

  return (
    <Link
      href={href}
      className={`group inline-flex items-center gap-2 rounded-[4px] border border-rail px-2 py-1 font-[family-name:var(--font-jetbrains-mono)] text-[11px] uppercase tracking-[0.1em] text-screen transition-colors duration-200 hover:border-beam-400/60 hover:text-screen ${className}`.trim()}
    >
      <span aria-hidden className="h-[7px] w-[7px] rounded-full bg-cue" />
      <span>{label}</span>
    </Link>
  );
}
