import Link from "next/link";
import { GitBranch, HardDrive, ShieldCheck, RefreshCw, EyeOff, Undo2 } from "lucide-react";
import { SITE_CONFIG } from "@/lib/constants";
import { getPublicStats } from "@/lib/public-metrics";

const ITEMS: { icon: typeof GitBranch; label: string; href?: string }[] = [
  { icon: GitBranch, label: "Source available", href: SITE_CONFIG.githubRepo },
  { icon: HardDrive, label: "Private by default" },
  { icon: ShieldCheck, label: "Signed & notarized" },
  { icon: RefreshCw, label: "Automatic updates" },
  { icon: EyeOff, label: "No ads, analytics opt-out", href: "/privacy" },
  { icon: Undo2, label: "14-day refund", href: "/refund" },
];

export async function TrustStrip() {
  const showUsageStats = process.env.NEXT_PUBLIC_SHOW_USAGE_STATS === "true";
  const stats = showUsageStats ? await getPublicStats().catch(() => null) : null;

  return (
    <section className="relative py-8 md:py-10 px-4 sm:px-6 lg:px-8 max-w-7xl mx-auto">
      {stats?.publishable && (
        <p className="text-center text-xs sm:text-sm font-mono text-purple-300/80 mb-6">
          {stats.roomsAllTime} rooms hosted · {stats.downloadsAllTime} downloads ·{" "}
          {stats.messagesSent} messages sent
        </p>
      )}
      <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-x-4 gap-y-5 max-w-4xl mx-auto">
        {ITEMS.map(({ icon: Icon, label, href }) => {
          const content = (
            <div className="flex items-center justify-center gap-2 text-center">
              <Icon className="w-4 h-4 text-purple-300 shrink-0" />
              <span className="text-xs sm:text-[13px] text-gray-300 font-medium">{label}</span>
            </div>
          );
          return href ? (
            <Link
              key={label}
              href={href}
              className="hover:text-white transition-colors"
              {...(href.startsWith("http") ? { target: "_blank", rel: "noopener noreferrer" } : {})}
            >
              {content}
            </Link>
          ) : (
            <div key={label}>{content}</div>
          );
        })}
      </div>
    </section>
  );
}
