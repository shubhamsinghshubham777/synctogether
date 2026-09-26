import Link from "next/link";
import { GitBranch, HardDrive, ShieldCheck, RefreshCw, EyeOff, Undo2 } from "lucide-react";
import { SITE_CONFIG } from "@/lib/constants";
import { getPublicStats } from "@/lib/public-metrics";

const ITEMS: { icon: typeof GitBranch; label: string; href?: string; wide?: boolean }[] = [
  { icon: GitBranch, label: "Source available", href: SITE_CONFIG.githubRepo },
  { icon: HardDrive, label: "Private by default" },
  { icon: ShieldCheck, label: "Signed & notarized" },
  { icon: RefreshCw, label: "Updates itself", wide: true },
  { icon: EyeOff, label: "No ads · analytics opt-out", href: "/privacy", wide: true },
  { icon: Undo2, label: "14-day refund", href: "/refund" },
];

export async function TrustStrip() {
  const showUsageStats = process.env.NEXT_PUBLIC_SHOW_USAGE_STATS === "true";
  const stats = showUsageStats ? await getPublicStats().catch(() => null) : null;

  return (
    <section className="relative px-4 sm:px-6 lg:px-8 max-w-7xl mx-auto">
      {stats?.publishable && (
        <p className="text-center text-xs sm:text-sm font-mono text-gray-400 mb-6">
          {stats.roomsAllTime} rooms hosted · {stats.downloadsAllTime} downloads ·{" "}
          {stats.messagesSent} messages sent
        </p>
      )}
      {/* Two hairlines, six items spread edge to edge; a 2-column grid on phones and tablets. */}
      <ul className="grid grid-cols-2 md:grid-cols-3 lg:flex lg:justify-between gap-x-6 gap-y-3 border-y border-aisle py-4 lg:py-0 lg:h-16 lg:items-center">
        {ITEMS.map(({ icon: Icon, label, href, wide }) => {
          const content = (
            <span className="inline-flex items-center gap-2.5 text-[13px] lg:text-sm leading-5 text-gray-300">
              <Icon className="hidden sm:block w-4 h-4 shrink-0 text-gray-500" strokeWidth={1.8} aria-hidden />
              <span className={href ? "hover:text-screen transition-colors" : ""}>{label}</span>
            </span>
          );
          return (
            <li key={label} className={wide ? "hidden md:block" : undefined}>
              {href ? (
                <Link
                  href={href}
                  {...(href.startsWith("http") ? { target: "_blank", rel: "noopener noreferrer" } : {})}
                >
                  {content}
                </Link>
              ) : (
                content
              )}
            </li>
          );
        })}
      </ul>
    </section>
  );
}
