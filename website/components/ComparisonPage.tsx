import type { ReactNode } from "react";
import { Check, X, Minus, Download } from "lucide-react";
import { Ticket } from "@/components/Ticket";
import { PTButton } from "@/components/PTButton";
import { Kicker, display, mono } from "@/components/booth/Booth";
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
  if (value === "yes") return <Check strokeWidth={1.8} className="w-[18px] h-[18px] text-cue mx-auto" aria-label="Yes" />;
  if (value === "no") return <X strokeWidth={1.8} className="w-4 h-4 text-[#5A4F44] mx-auto" aria-label="No" />;
  if (value === "partial") return <Minus strokeWidth={1.8} className="w-4 h-4 text-beam-500 mx-auto" aria-label="Partly" />;
  return <span className="block text-xs sm:text-[13px] text-gray-300 leading-snug break-words">{value}</span>;
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
  const verdictN = String(sections.length + 2).padStart(2, "0");
  return (
    <div className="px-4 sm:px-6 lg:px-8 max-w-7xl mx-auto pt-8 md:pt-12 pb-12">
      <header className="grid lg:grid-cols-[1.3fr_1fr] gap-10 lg:gap-16 items-end border-b border-aisle pb-8 md:pb-11">
        <div className="flex flex-col gap-[22px] min-w-0">
          <p className={`${mono} text-xs tracking-[0.14em] uppercase text-gray-500`}>
            <span className="text-beam-500">{eyebrow}</span> · {SITE_CONFIG.name} vs {competitor}
          </p>
          <h1 className={`${display} text-[clamp(2.5rem,6vw,4.5rem)] font-extrabold leading-[0.9] tracking-[-0.045em] text-white`}>
            {headline}
          </h1>
          <p className="text-lg sm:text-[19px] leading-[1.55] text-gray-300 max-w-[600px]">{intro}</p>
        </div>
        <div className="min-w-0">
          <Ticket
            paper={false}
            animate
            stub={<span className={`${display} text-[40px] font-extrabold tracking-[-0.04em] text-beam-500`}>vs</span>}
          >
            <p className={`${mono} text-[11px] tracking-[0.14em] text-gray-500`}>TONIGHT&apos;S DOUBLE BILL</p>
            <p className={`${display} mt-2 text-[32px] font-extrabold tracking-[-0.03em] leading-none`}>{SITE_CONFIG.name}</p>
            <p className="mt-2.5 text-sm text-gray-400 truncate">and {competitor}, honestly compared</p>
          </Ticket>
        </div>
      </header>

      <section className="pt-10 pb-9 flex flex-col gap-5">
        <Kicker n="01">Side by side</Kicker>
        <table className="w-full table-fixed">
          <caption className="sr-only">
            {SITE_CONFIG.name} compared with {competitor}
          </caption>
          <colgroup>
            <col />
            <col className="w-[30%] sm:w-[240px]" />
            <col className="w-[30%] sm:w-[240px]" />
          </colgroup>
          <thead>
            <tr className="border-b border-rail">
              <th scope="col" className={`${mono} text-left py-3.5 pr-3 font-normal text-[10px] sm:text-[11px] text-gray-500 uppercase tracking-[0.14em]`}>
                Feature
              </th>
              <th scope="col" className={`${display} bg-seat rounded-t-md py-3.5 px-3 font-extrabold text-white text-center text-sm sm:text-[17px] tracking-[-0.01em] break-words`}>
                {SITE_CONFIG.name}
              </th>
              <th scope="col" className={`${display} py-3.5 px-3 font-semibold text-gray-400 text-center text-sm sm:text-[17px] break-words`}>
                {competitor}
              </th>
            </tr>
          </thead>
          <tbody>
            {rows.map((row) => (
              <tr key={row.feature} className="border-b border-aisle">
                <th scope="row" className="text-left py-[11px] pr-3 font-normal text-gray-300 text-[13px] sm:text-[15px] leading-snug break-words">
                  {row.feature}
                </th>
                <td className="bg-seat py-[11px] px-3 text-center align-middle">
                  <Cell value={row.ours} />
                </td>
                <td className="py-[11px] px-3 text-center align-middle">
                  <Cell value={row.theirs} />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        <p className="text-[13px] text-gray-500">
          {competitor} details last checked{" "}
          <time dateTime={lastChecked}>
            {new Date(lastChecked).toLocaleDateString("en-US", { month: "long", year: "numeric", timeZone: "UTC" })}
          </time>
          . Products change. Spotted something out of date?{" "}
          <a href={`mailto:${SITE_CONFIG.supportEmail}`} className="text-gray-300 underline underline-offset-4 decoration-rail hover:text-white">
            Tell us
          </a>
          .
        </p>
      </section>

      <div className="pb-9 flex flex-col gap-9">
        {sections.map((section, i) => (
          <section key={section.heading} className="grid lg:grid-cols-[1fr_1.4fr] gap-5 lg:gap-16 border-t border-aisle pt-7">
            <div className="flex flex-col gap-3">
              <p className={`${mono} text-xs text-gray-500`}>{String(i + 2).padStart(2, "0")}</p>
              <h2 className={`${display} text-2xl sm:text-[32px] font-extrabold tracking-[-0.03em] leading-[1.02] text-white`}>
                {section.heading}
              </h2>
            </div>
            <div className="flex flex-col gap-4">
              {section.body.map((paragraph, j) => (
                <p key={j} className="text-[17px] text-gray-300 leading-[1.6]">
                  {paragraph}
                </p>
              ))}
            </div>
          </section>
        ))}
      </div>

      <section className="pt-1 pb-10 flex flex-col gap-6">
        <div className="flex flex-col gap-3.5">
          <Kicker n={verdictN}>The verdict</Kicker>
          <h2 className={`${display} text-3xl sm:text-[44px] font-extrabold tracking-[-0.04em] leading-[0.92] text-white`}>
            Which one should you actually use?
          </h2>
        </div>
        <div className="grid gap-4 md:grid-cols-2">
          <div className="bg-seat border border-rail rounded-md p-7 flex flex-col gap-4">
            <p className={`${mono} text-[11px] tracking-[0.14em] uppercase text-cue`}>Pick {SITE_CONFIG.name} if…</p>
            {verdictFor.map((item) => (
              <p key={item} className="flex items-start gap-3 text-[15px] text-gray-200 leading-[1.4]">
                <Check strokeWidth={1.8} className="w-4 h-4 shrink-0 mt-px text-cue" />
                <span>{item}</span>
              </p>
            ))}
          </div>
          <div className="border border-rail rounded-md p-7 flex flex-col gap-4">
            <p className={`${mono} text-[11px] tracking-[0.14em] uppercase text-gray-500`}>Stick with {competitor} if…</p>
            {verdictAgainst.map((item) => (
              <p key={item} className="flex items-start gap-3 text-[15px] text-gray-400 leading-[1.4]">
                <Minus strokeWidth={1.8} className="w-4 h-4 shrink-0 mt-px text-[#5A4F44]" />
                <span>{item}</span>
              </p>
            ))}
          </div>
        </div>
      </section>

      <section className="border-t border-aisle pt-8 flex flex-col md:flex-row md:items-end justify-between gap-8">
        <div className="flex flex-col gap-3.5">
          <p className={`${mono} text-xs tracking-[0.16em] uppercase text-gray-500`}>Now showing</p>
          <h2 className={`${display} text-3xl sm:text-[40px] font-extrabold tracking-[-0.04em] leading-[0.92] text-white`}>
            Free on Mac and Windows.
          </h2>
          <p className="text-base text-gray-500">No account needed to join a room.</p>
        </div>
        <PTButton
          href="/download"
          className="!h-[52px] !px-6 !rounded-[4px] !text-base !font-semibold !gap-2.5 self-start md:self-auto"
          leftIcon={<Download aria-hidden="true" strokeWidth={1.8} className="w-[18px] h-[18px]" />}
        >
          Download {SITE_CONFIG.name}
        </PTButton>
      </section>
    </div>
  );
}
