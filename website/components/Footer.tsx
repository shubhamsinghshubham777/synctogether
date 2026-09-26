"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { SITE_CONFIG } from "@/lib/constants";

type FooterLink = { label: string; href: string };

const COLUMNS: { title: string; links: FooterLink[] }[] = [
  {
    title: "Product",
    links: [
      { label: "Download for macOS", href: "/download" },
      { label: "Download for Windows", href: "/download" },
      { label: "Pricing", href: "/pricing" },
      { label: "Changelog", href: "/changelog" },
    ],
  },
  {
    title: "Resources",
    links: [
      { label: "Leaderboard", href: "/leaderboard" },
      { label: "vs Syncplay", href: "/vs/syncplay" },
      { label: "vs Discord", href: "/vs/discord" },
      { label: "vs Teleparty", href: "/vs/teleparty" },
      { label: "FAQ", href: "/faq" },
    ],
  },
  {
    title: "House rules",
    links: [
      { label: "Terms of Service", href: "/terms" },
      { label: "Privacy Policy", href: "/privacy" },
      { label: "Refund Policy (14 days)", href: "/refund" },
      { label: "Copyright & DMCA", href: "/dmca" },
    ],
  },
];

const mono = "font-[family-name:var(--font-jetbrains-mono)]";
const display = "font-[family-name:var(--font-space-grotesk)]";

/**
 * The end credits. A closing line set big, the wordmark, three ruled columns
 * of links in the mono label voice, and a credits bar. Flat Booth-black under
 * a Rail hairline - no glow, no icons standing in for words.
 */
const COMPACT_LINKS: FooterLink[] = [
  { label: "Download", href: "/download" },
  { label: "Pricing", href: "/pricing" },
  { label: "FAQ", href: "/faq" },
  { label: "Changelog", href: "/changelog" },
  { label: "Leaderboard", href: "/leaderboard" },
  { label: "Terms", href: "/terms" },
  { label: "Privacy", href: "/privacy" },
  { label: "Refunds", href: "/refund" },
  { label: "DMCA", href: "/dmca" },
];

/** Home and pricing close on one row; everything else gets the full credits. */
const COMPACT_PATHS = new Set(["/", "/pricing"]);

function Credits({ year }: { year: number }) {
  return (
    <>
      <span>
        © {year} {SITE_CONFIG.name} · Made by{" "}
        <a
          href={SITE_CONFIG.creatorLinkedIn}
          target="_blank"
          rel="noopener noreferrer"
          className="hover:text-white underline underline-offset-4 decoration-rail hover:decoration-beam-500 transition-colors"
        >
          {SITE_CONFIG.creatorName}
        </a>
      </span>
      <span>
        <a href={SITE_CONFIG.githubRepo} target="_blank" rel="noopener noreferrer" className="hover:text-white transition-colors">
          Source available
        </a>{" "}
        · PolyForm Noncommercial
      </span>
    </>
  );
}

export function Footer() {
  const currentYear = new Date().getFullYear();
  const pathname = usePathname();

  if (COMPACT_PATHS.has(pathname ?? "")) {
    return (
      <footer className="relative bg-[#0D0B0B] border-t border-aisle">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 pt-8 pb-7">
          <div className="flex flex-col lg:flex-row lg:items-end justify-between gap-5">
            <p className={`${display} text-[32px] leading-[0.92] font-extrabold tracking-[-0.04em] text-white`}>House lights up.</p>
            <nav aria-label="Footer" className="flex flex-wrap gap-x-[22px] gap-y-2 text-sm">
              {COMPACT_LINKS.map((l) => (
                <Link key={l.label} href={l.href} className="text-gray-300 hover:text-white transition-colors">
                  {l.label}
                </Link>
              ))}
            </nav>
          </div>
          <div className={`${mono} mt-5 flex flex-col md:flex-row justify-between gap-2 text-xs tracking-[0.08em] uppercase text-[#5A4F44]`}>
            <Credits year={currentYear} />
          </div>
        </div>
      </footer>
    );
  }

  return (
    <footer className="relative bg-[#0D0B0B] border-t border-aisle">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 pt-12 md:pt-14 pb-10 flex flex-col gap-12">
        <div className="grid grid-cols-2 lg:grid-cols-[1.3fr_1fr_1fr_1fr] gap-x-6 gap-y-10 lg:gap-12">
          <div className="col-span-2 lg:col-span-1 flex flex-col gap-5">
            <p className={`${display} text-4xl sm:text-[44px] font-extrabold tracking-[-0.04em] leading-[0.92] text-white`}>
              House lights up.
              <br />
              <span className="text-[#5A4F44]">See you next showing.</span>
            </p>
            <p className="text-[15px] text-gray-500 leading-[1.55]">Movie night, even when you&apos;re not in the same room.</p>
          </div>

          {COLUMNS.map((col) => (
            <nav key={col.title} aria-label={col.title} className="min-w-0 flex flex-col gap-3.5">
              <h4 className={`${mono} text-[11px] tracking-[0.14em] uppercase text-gray-500`}>{col.title}</h4>
              <div className="h-px bg-rail shrink-0" />
              {col.links.map((l) => (
                <Link key={l.label} href={l.href} className="text-[15px] text-gray-300 hover:text-white transition-colors">
                  {l.label}
                </Link>
              ))}
            </nav>
          ))}
        </div>

        <div className={`${mono} flex flex-col md:flex-row justify-between gap-2 text-xs tracking-[0.08em] uppercase text-[#5A4F44]`}>
          <Credits year={currentYear} />
        </div>
      </div>
    </footer>
  );
}
