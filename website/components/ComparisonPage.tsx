import Link from "next/link";
import type { ReactNode } from "react";
import { Check, X, Minus, Scale } from "lucide-react";
import { GlassPanel } from "@/components/GlassPanel";
import { SITE_CONFIG } from "@/lib/constants";

/**
 * The shared shell behind every `/vs/<competitor>` page.
 *
 * These pages exist for long-tail search ("teleparty alternative for downloaded
 * movies") - low competition, no ongoing cost, and the only marketing asset
 * that keeps working when nobody is posting. One shell rather than three
 * near-identical files, for the same reason `usePremiumCheckout` is one hook
 * with two call sites.
 *
 * The `verdictAgainst` section is not modesty, it is the point. A comparison
 * page that finds its author superior on every row reads as an advertisement
 * and is treated as one by both readers and search engines; naming the cases
 * where the competitor genuinely wins is what makes the rest credible. It is
 * also the same posture the Reddit strategy depends on, and these pages get
 * linked from there.
 */

export type Support = "yes" | "no" | "partial";

export interface ComparisonRow {
  feature: string;
  /** A tick/cross/dash, or a short qualifying note rendered as text. */
  ours: Support | ReactNode;
  theirs: Support | ReactNode;
}

export interface ComparisonPageProps {
  competitor: string;
  eyebrow: string;
  headline: ReactNode;
  intro: string;
  /** ISO date the competitor's side of the table was last verified. */
  lastChecked: string;
  rows: ComparisonRow[];
  sections: { heading: string; body: string[] }[];
  verdictAgainst: string[];
  verdictFor: string[];
}

function Cell({ value }: { value: Support | ReactNode }) {
  if (value === "yes")
    return <Check className="w-5 h-5 text-emerald-400 mx-auto" aria-label="Yes" />;
  if (value === "no")
    return <X className="w-5 h-5 text-gray-600 mx-auto" aria-label="No" />;
  if (value === "partial")
    return <Minus className="w-5 h-5 text-amber-400 mx-auto" aria-label="Partial" />;
  return <span className="text-xs text-gray-300 leading-snug">{value}</span>;
}

export function ComparisonPage({
  competitor,
  eyebrow,
  headline,
  intro,
  lastChecked,
  rows,
  sections,
  verdictAgainst,
  verdictFor,
}: ComparisonPageProps) {
  return (
    <div className="relative py-12 md:py-20 px-4 sm:px-6 lg:px-8 max-w-4xl mx-auto space-y-12">
      <div className="glow-blob-purple top-10 left-1/2 -translate-x-1/2 opacity-25" />

      <header className="space-y-4">
        <span className="text-xs sm:text-sm font-mono text-purple-400 font-bold uppercase tracking-wider">
          {eyebrow}
        </span>
        <h1 className="text-4xl sm:text-5xl font-extrabold text-white tracking-tight font-[family-name:var(--font-space-grotesk)] leading-[1.1]">
          {headline}
        </h1>
        <p className="text-base sm:text-lg text-gray-300 leading-relaxed max-w-2xl">
          {intro}
        </p>
      </header>

      <GlassPanel className="p-0 overflow-hidden border-purple-500/20">
        <table className="w-full text-sm">
          <caption className="sr-only">
            {SITE_CONFIG.name} compared with {competitor}
          </caption>
          <thead>
            <tr className="border-b border-white/10 bg-white/[0.03]">
              <th scope="col" className="text-left p-4 font-semibold text-gray-400 text-xs uppercase tracking-wider">
                Feature
              </th>
              <th scope="col" className="p-4 font-bold text-white text-center w-1/4">
                {SITE_CONFIG.name}
              </th>
              <th scope="col" className="p-4 font-semibold text-gray-400 text-center w-1/4">
                {competitor}
              </th>
            </tr>
          </thead>
          <tbody>
            {rows.map((row) => (
              <tr key={row.feature} className="border-b border-white/5 last:border-0">
                <th scope="row" className="text-left p-4 font-normal text-gray-300">
                  {row.feature}
                </th>
                <td className="p-4 text-center align-middle">
                  <Cell value={row.ours} />
                </td>
                <td className="p-4 text-center align-middle">
                  <Cell value={row.theirs} />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        <p className="px-4 py-3 border-t border-white/10 text-xs text-gray-500">
          {competitor} details last checked{" "}
          <time dateTime={lastChecked}>
            {new Date(lastChecked).toLocaleDateString("en-US", { month: "long", year: "numeric", timeZone: "UTC" })}
          </time>
          . Products change - spotted something out of date?{" "}
          <a href={`mailto:${SITE_CONFIG.supportEmail}`} className="underline hover:text-white">
            Tell us
          </a>
          .
        </p>
      </GlassPanel>

      {sections.map((section) => (
        <section key={section.heading} className="space-y-3">
          <h2 className="text-2xl sm:text-3xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
            {section.heading}
          </h2>
          {section.body.map((paragraph, i) => (
            <p key={i} className="text-base text-gray-300 leading-relaxed">
              {paragraph}
            </p>
          ))}
        </section>
      ))}

      <GlassPanel className="p-8 space-y-6 border-amber-400/20">
        <div className="flex items-center gap-2.5">
          <Scale className="w-5 h-5 text-amber-400 shrink-0" />
          <h2 className="text-xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
            Which one should you actually use?
          </h2>
        </div>
        <div className="grid gap-6 sm:grid-cols-2">
          <div className="space-y-2">
            <p className="text-sm font-semibold text-emerald-300">
              Pick {SITE_CONFIG.name} if…
            </p>
            <ul className="space-y-2">
              {verdictFor.map((item) => (
                <li key={item} className="flex items-start gap-2 text-sm text-gray-300 leading-snug">
                  <Check className="w-4 h-4 shrink-0 mt-0.5 text-emerald-400" />
                  <span>{item}</span>
                </li>
              ))}
            </ul>
          </div>
          <div className="space-y-2">
            <p className="text-sm font-semibold text-gray-300">
              Stick with {competitor} if…
            </p>
            <ul className="space-y-2">
              {verdictAgainst.map((item) => (
                <li key={item} className="flex items-start gap-2 text-sm text-gray-400 leading-snug">
                  <Minus className="w-4 h-4 shrink-0 mt-0.5 text-gray-500" />
                  <span>{item}</span>
                </li>
              ))}
            </ul>
          </div>
        </div>
      </GlassPanel>

      <div className="text-center space-y-4 py-4">
        <p className="text-lg text-gray-300">
          Free to use on Mac and Windows. No account needed to join a room.
        </p>
        <Link
          href="/download"
          className="btn-primary-gradient inline-block px-8 py-3.5 rounded-xl font-bold text-white"
        >
          Download {SITE_CONFIG.name}
        </Link>
      </div>
    </div>
  );
}
