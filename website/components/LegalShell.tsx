import React from "react";
import Link from "next/link";
import { Headline, Kicker, mono } from "@/components/booth/Booth";
import { LegalToc, type LegalTocItem } from "@/components/LegalToc";
import "./LegalShell.css";

const LEGAL_PAGES = [
  { href: "/terms", label: "Terms of Service" },
  { href: "/privacy", label: "Privacy Policy" },
  { href: "/refund", label: "Refund Policy" },
  { href: "/dmca", label: "Copyright & DMCA" },
];

/** Section number prefix inside an `h2`, set as a Beam mono reel number. */
export function LegalNum({ n }: { n: string }) {
  return <span className="legal-num">{/^\d$/.test(n) ? `0${n}` : n}</span>;
}

/** The page's one headline note, printed as a notched paper ticket. */
export function LegalPledge({ title, children }: { title: React.ReactNode; children: React.ReactNode }) {
  return (
    <div className="legal-paper legal-pledge">
      <p className="legal-pledge-eyebrow">The short version</p>
      <h2 className="legal-pledge-title">{title}</h2>
      {children}
    </div>
  );
}

/** "August 30, 2026" -> "30 Aug 2026", the board's compact form; anything else passes through. */
function shortDate(value: string) {
  const m = /^([A-Z][a-z]+) (\d{1,2}), (\d{4})$/.exec(value);
  return m ? `${m[2]} ${m[1].slice(0, 3)} ${m[3]}` : value;
}

/**
 * Long-form legal shell: masthead, then a side rail (dates, "On this page",
 * the fine print) beside one readable column styled by `.legal-prose`.
 */
export function LegalShell({
  current,
  kicker,
  title,
  dek,
  dates,
  toc,
  children,
}: {
  current: string;
  kicker: string;
  title: React.ReactNode;
  dek?: React.ReactNode;
  dates: { label: string; value: string }[];
  toc: LegalTocItem[];
  children: React.ReactNode;
}) {
  return (
    <div className="pb-12 md:pb-16">
      {/* The masthead rule runs the full page width, as on the board. */}
      <div className="border-b border-rail">
        <header className="px-4 sm:px-6 lg:px-8 max-w-6xl mx-auto space-y-[18px] pt-8 pb-10 md:pt-[60px]">
          <Kicker tone="muted">
            <span className="text-beam-500">House rules</span> · {kicker}
          </Kicker>
          <Headline className="text-[clamp(2.5rem,7vw,5rem)] line-in">{title}</Headline>
          {dek && <p className="text-[17px] sm:text-[19px] leading-[1.55] text-gray-400 max-w-[720px]">{dek}</p>}
        </header>
      </div>

      <div className="px-4 sm:px-6 lg:px-8 max-w-6xl mx-auto">
        <div className="grid lg:grid-cols-[240px_minmax(0,1fr)] gap-10 lg:gap-[72px] pt-8 md:pt-12">
          <aside className="lg:sticky lg:top-28 self-start space-y-6 lg:max-h-[calc(100vh-8rem)] lg:overflow-y-auto">
            <dl className="flex flex-wrap gap-x-10 gap-y-4 pb-1 lg:grid lg:grid-cols-2 lg:gap-3">
              {dates.map((d) => (
                <div key={d.label}>
                  <dt className={`${mono} text-[10px] tracking-[0.16em] uppercase text-gray-500`}>{d.label}</dt>
                  <dd className={`${mono} text-[13px] text-white mt-1.5`}>{shortDate(d.value)}</dd>
                </div>
              ))}
            </dl>
            <div className="hidden lg:block">
              <LegalToc items={toc} />
            </div>
            <details className="lg:hidden border-y border-rail py-3 group">
              <summary
                className={`${mono} cursor-pointer list-none flex items-center justify-between text-[10px] tracking-[0.16em] uppercase text-gray-400`}
              >
                On this page
                <span className="text-beam-500 transition-transform group-open:rotate-45 text-base leading-none" aria-hidden="true">
                  +
                </span>
              </summary>
              <div className="pt-4 [&_nav]:border-t-0 [&_nav]:pt-0 [&_nav>p]:hidden">
                <LegalToc items={toc} />
              </div>
            </details>
            <nav aria-label="Legal pages" className="hidden lg:block border-t border-rail pt-6">
              <p className={`${mono} text-[10px] tracking-[0.16em] uppercase text-gray-500 mb-3`}>The fine print</p>
              <ul className="space-y-2">
                {LEGAL_PAGES.map((p) => (
                  <li key={p.href}>
                    <Link
                      href={p.href}
                      aria-current={p.href === current ? "page" : undefined}
                      className={`flex items-center gap-2 text-sm transition-colors ${
                        p.href === current ? "text-beam-500" : "text-gray-400 hover:text-white"
                      }`}
                    >
                      {p.href === current && <span className="h-1.5 w-1.5 rounded-full bg-beam-500" aria-hidden="true" />}
                      {p.label}
                    </Link>
                  </li>
                ))}
              </ul>
            </nav>
          </aside>

          <article className="legal-prose max-w-[45rem] min-w-0">{children}</article>
        </div>

        <nav aria-label="Legal pages" className="lg:hidden mt-10 border-t border-rail pt-6 flex flex-wrap gap-x-6 gap-y-3">
          {LEGAL_PAGES.filter((p) => p.href !== current).map((p) => (
            <Link key={p.href} href={p.href} className="text-sm text-gray-400 hover:text-white underline underline-offset-4 decoration-rail">
              {p.label}
            </Link>
          ))}
        </nav>
      </div>
    </div>
  );
}
