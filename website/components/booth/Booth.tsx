import React from "react";
import Link from "next/link";
import "./booth.css";

/**
 * Small Booth Light building blocks for the editorial pages (account, auth,
 * rewards, comparisons, legal). The home page and header have their own; these
 * mirror the same moves: a mono eyebrow, a Bricolage 800 headline with tight
 * tracking, ink stamps, and paper only for what is shared.
 */

export const display = "font-[family-name:var(--font-space-grotesk)]";
export const mono = "font-[family-name:var(--font-jetbrains-mono)]";

/** The uppercase mono eyebrow. `n` numbers it like a reel. */
export function Kicker({
  n,
  tone = "beam",
  children,
  className = "",
}: {
  n?: string;
  tone?: "beam" | "muted" | "brass" | "signal" | "cue" | "ink";
  children: React.ReactNode;
  className?: string;
}) {
  const color = {
    beam: "text-beam-500",
    muted: "text-gray-500",
    brass: "text-brass",
    signal: "text-signal",
    cue: "text-cue",
    ink: "text-[#A33A22]",
  }[tone];
  return (
    <p className={`${mono} text-[11px] sm:text-xs tracking-[0.16em] uppercase ${color} ${className}`}>
      {n && <span className="text-[#5A4F44]">{n} · </span>}
      {children}
    </p>
  );
}

/** The display headline. */
export function Headline({
  as: Tag = "h1",
  children,
  className = "",
}: {
  as?: "h1" | "h2" | "h3" | "p";
  children: React.ReactNode;
  className?: string;
}) {
  return <Tag className={`${display} font-extrabold tracking-[-0.04em] leading-[0.92] text-white ${className}`}>{children}</Tag>;
}

/**
 * An ink stamp, round or rectangular, pressed in once. Signal on the booth,
 * `ink` (the paper-safe coral) on a ticket, Brass for Patron, Cue for ready.
 */
export function Stamp({
  top,
  main,
  bottom,
  tone = "signal",
  shape = "round",
  tilt = -8,
  animate = true,
  className = "",
  label,
}: {
  top?: string;
  main: string;
  bottom?: string;
  tone?: "signal" | "ink" | "brass" | "cue" | "beam";
  shape?: "round" | "rect";
  tilt?: number;
  animate?: boolean;
  className?: string;
  label?: string;
}) {
  const color = {
    signal: "border-signal text-signal",
    ink: "border-[#A33A22] text-[#A33A22]",
    brass: "border-brass text-brass",
    cue: "border-cue text-cue",
    beam: "border-beam-500 text-beam-500",
  }[tone];
  const box = shape === "round" ? "w-28 h-28 sm:w-32 sm:h-32 rounded-full border-[3px] px-2" : "px-4 py-2 rounded-[4px] border-[3px]";
  return (
    <div
      role="img"
      aria-label={label ?? [top, main, bottom].filter(Boolean).join(" ")}
      style={{
        ["--tilt" as string]: `${tilt}deg`,
        transform: `rotate(${tilt}deg)`,
      }}
      className={`${animate ? "booth-stamp" : ""} inline-flex shrink-0 flex-col items-center justify-center leading-none select-none ${box} ${color} ${className}`}
    >
      {top && <span className={`${mono} text-[9px] sm:text-[10px] tracking-[0.14em]`}>{top}</span>}
      <span
        className={`${display} font-extrabold tracking-[-0.02em] ${shape === "round" ? "text-xl sm:text-3xl" : "text-lg sm:text-2xl"} my-1 whitespace-nowrap`}
      >
        {main}
      </span>
      {bottom && <span className={`${mono} text-[8px] sm:text-[9px] tracking-[0.12em]`}>{bottom}</span>}
    </div>
  );
}

/** A label, a dotted leader, a value: the programme row. */
export function LeaderRow({ label, value, className = "" }: { label: React.ReactNode; value: React.ReactNode; className?: string }) {
  return (
    <li className={`flex items-baseline gap-3 py-2.5 ${className}`}>
      <span className="text-[15px] text-gray-300">{label}</span>
      <span className="booth-leader" aria-hidden="true" />
      <span className={`${mono} text-sm text-white tabular-nums text-right`}>{value}</span>
    </li>
  );
}

/** A spinner-free waiting state: the projector warming up. */
export function Warming({ label }: { label: string }) {
  return (
    <div className="max-w-4xl mx-auto py-16 px-4 flex flex-col items-center gap-5 text-center">
      <span className="sync-dot" aria-hidden="true" />
      <p className={`${mono} text-xs tracking-[0.16em] uppercase text-gray-500`}>{label}</p>
    </div>
  );
}

const LEGAL_PAGES = [
  { href: "/terms", label: "Terms of Service" },
  { href: "/privacy", label: "Privacy Policy" },
  { href: "/refund", label: "Refund Policy" },
  { href: "/dmca", label: "Copyright & DMCA" },
];

/**
 * The long-form legal shell: a masthead, then a side rail (the house rules
 * index and the dates) beside a single readable column. The column's
 * typography comes from `.legal-prose`, which also flattens the older boxed
 * markup into margin notes.
 */
export function LegalPage({
  current,
  kicker,
  title,
  dek,
  dates,
  children,
}: {
  current: string;
  kicker: string;
  title: React.ReactNode;
  dek?: React.ReactNode;
  dates: { label: string; value: string }[];
  children: React.ReactNode;
}) {
  return (
    <div className="px-4 sm:px-6 lg:px-8 max-w-6xl mx-auto pt-8 pb-12 md:pt-12 md:pb-16">
      <header className="max-w-3xl space-y-5 pb-10 md:pb-10 border-b border-rail">
        <Kicker tone="muted">
          <span className="text-beam-500">House rules</span> · {kicker}
        </Kicker>
        <Headline className="text-[clamp(2.5rem,7vw,5rem)] line-in">{title}</Headline>
        {dek && <p className="text-lg sm:text-xl leading-relaxed text-gray-400 max-w-2xl">{dek}</p>}
      </header>

      <div className="grid lg:grid-cols-[14rem_minmax(0,1fr)] gap-10 lg:gap-16 pt-8 md:pt-12">
        <aside className="lg:sticky lg:top-28 self-start space-y-8">
          <dl className="flex flex-wrap gap-x-8 gap-y-4 lg:block lg:space-y-4">
            {dates.map((d) => (
              <div key={d.label}>
                <dt className={`${mono} text-[10px] tracking-[0.16em] uppercase text-gray-500`}>{d.label}</dt>
                <dd className={`${mono} text-sm text-white mt-1`}>{d.value}</dd>
              </div>
            ))}
          </dl>
          <nav aria-label="Legal pages" className="hidden lg:block border-t border-rail pt-6">
            <p className={`${mono} text-[10px] tracking-[0.16em] uppercase text-gray-500 mb-3`}>The fine print</p>
            <ul className="space-y-2">
              {LEGAL_PAGES.map((p) => (
                <li key={p.href}>
                  <Link
                    href={p.href}
                    aria-current={p.href === current ? "page" : undefined}
                    className={`flex items-center gap-2 text-sm transition-colors ${
                      p.href === current ? "text-white" : "text-gray-500 hover:text-white"
                    }`}
                  >
                    <span className={`h-1.5 w-1.5 rounded-full ${p.href === current ? "bg-beam-500" : "bg-transparent"}`} aria-hidden="true" />
                    {p.label}
                  </Link>
                </li>
              ))}
            </ul>
          </nav>
        </aside>

        <article className="legal-prose max-w-[44rem] min-w-0">{children}</article>
      </div>

      <nav aria-label="Legal pages" className="lg:hidden mt-10 border-t border-rail pt-6 flex flex-wrap gap-x-6 gap-y-3">
        {LEGAL_PAGES.filter((p) => p.href !== current).map((p) => (
          <Link key={p.href} href={p.href} className="text-sm text-gray-400 hover:text-white underline underline-offset-4 decoration-rail">
            {p.label}
          </Link>
        ))}
      </nav>
    </div>
  );
}
