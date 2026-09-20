import Link from "next/link";
import { ArrowRight, Sparkles } from "lucide-react";

export interface ReleaseChipProps {
  /** Tag or version label, e.g. "v1.7.1". */
  tag?: string;
  /** Optional link destination, defaults to "/changelog". */
  href?: string;
  /** Optional additional class names. */
  className?: string;
}

/**
 * Announcement chip displaying the latest release version with an animated sparkle,
 * violet glass styling, and a link to the changelog.
 */
export function ReleaseChip({
  tag,
  href = "/changelog",
  className = "",
}: ReleaseChipProps) {
  const cleanTag = tag ? (tag.startsWith("SyncTogether ") ? tag.replace(/^SyncTogether\s+/, "") : tag) : "";
  const label = cleanTag ? `SyncTogether ${cleanTag} is now live` : "SyncTogether is now live";

  return (
    <Link
      href={href}
      className={`inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full bg-purple-500/10 border border-purple-400/30 text-purple-200 text-xs font-semibold shadow-inner hover:bg-purple-500/20 hover:border-purple-400/50 hover:text-white transition-all duration-200 group cursor-pointer ${className}`.trim()}
    >
      <Sparkles className="w-3.5 h-3.5 text-amber-300 animate-pulse group-hover:scale-110 transition-transform" />
      <span>{label}</span>
      <ArrowRight className="w-3 h-3 text-purple-400 group-hover:translate-x-0.5 transition-transform" />
    </Link>
  );
}
