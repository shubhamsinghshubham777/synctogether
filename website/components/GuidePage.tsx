import type { ReactNode } from "react";
import Link from "next/link";
import { PTButton } from "@/components/PTButton";
import { display, mono } from "@/components/booth/Booth";
import { GUIDES } from "@/app/facts/facts";

export interface GuideSection {
  heading: string;
  /** Paragraphs, or a numbered list when `items` is given. */
  body?: string[];
  items?: { title: string; text: string }[];
  /** On very wide screens, run across both columns instead of sitting in one. */
  fullWidth?: boolean;
}

/**
 * The shell behind `/guides/<slug>`: the real articles Pinterest pins link to.
 * Plain reading layout on purpose - these pages exist to answer a question
 * honestly, with the app mentioned where it genuinely fits and never as the
 * whole point. Written for people searching, not for the product's own users.
 */
export function GuidePage({
  eyebrow,
  title,
  answer,
  sections,
  cta,
  updated,
  path,
}: {
  eyebrow: string;
  title: ReactNode;
  /** The 40-60 word direct answer the article opens with. */
  answer: string;
  sections: GuideSection[];
  cta: { heading: string; text: string };
  updated: string;
  /** This guide's own path, so the "more guides" strip leaves it out. */
  path: string;
}) {
  // Numbering continues across sections, so work out where each one starts.
  const starts = sections.reduce<number[]>(
    (acc, section, i) => [...acc, (acc[i - 1] ?? 0) + (sections[i - 1]?.items?.length ?? 0)],
    [],
  );
  // Non-full-width sections alternate between the two wide columns.
  let stacked = 0;
  const stackOf = sections.map((section) => (section.fullWidth ? -1 : stacked++ % 2));
  const renderSection = (section: GuideSection, sectionIndex: number) => (
    <section
      key={section.heading}
      style={{ order: sectionIndex }}
      className={`mt-12 min-[2000px]:first:mt-0 ${section.fullWidth ? "min-[2000px]:col-span-2" : ""}`}
    >
      <h2 className={`${display} text-2xl sm:text-3xl font-extrabold tracking-[-0.03em] text-white`}>{section.heading}</h2>
      {section.body?.map((paragraph) => (
        <p key={paragraph.slice(0, 40)} className="mt-4 text-[17px] leading-[1.65] text-gray-300">
          {paragraph}
        </p>
      ))}
      {section.items && (
        <ol className="mt-5 border-t border-aisle">
          {section.items.map((item, itemIndex) => (
            <li key={item.title} className="grid grid-cols-[2.5rem_1fr] gap-3 border-b border-aisle py-4">
              <span className={`${mono} text-sm text-gray-500`}>{String(starts[sectionIndex] + itemIndex + 1).padStart(2, "0")}</span>
              <div>
                <p className="font-semibold text-white">{item.title}</p>
                <p className="mt-1 text-[16px] leading-[1.6] text-gray-400">{item.text}</p>
              </div>
            </li>
          ))}
        </ol>
      )}
    </section>
  );
  return (
    <article className="px-4 sm:px-6 lg:px-8 max-w-3xl min-[2000px]:max-w-[1920px] mx-auto pt-8 md:pt-12 pb-16 min-[2000px]:grid min-[2000px]:grid-cols-[30rem_minmax(0,1fr)] min-[2000px]:grid-rows-[auto_1fr] min-[2000px]:gap-x-24 min-[2000px]:items-start">
      <div className="min-[2000px]:col-start-1 min-[2000px]:row-start-1">
        <p className={`${mono} text-xs tracking-[0.14em] uppercase text-gray-500`}>
          <span className="text-beam-500">{eyebrow}</span> · Updated {updated}
        </p>
        <h1 className={`${display} mt-4 text-[clamp(2.25rem,5.5vw,3.75rem)] font-extrabold leading-[0.95] tracking-[-0.04em] text-white`}>{title}</h1>
        <p className="mt-6 text-lg sm:text-[19px] leading-[1.55] text-white">{answer}</p>
      </div>

      {/* Wide screens read across: 1st top-left, 2nd top-right, 3rd below the 1st, and so on. Two
          stacks (even | odd) do that without row-aligned gaps; below 2000px the stacks dissolve and
          `order` keeps the written sequence. A `fullWidth` section runs across both columns below. */}
      <div className="flex flex-col min-[2000px]:grid min-[2000px]:grid-cols-2 min-[2000px]:gap-x-16 min-[2000px]:items-start min-[2000px]:col-start-2 min-[2000px]:row-start-1 min-[2000px]:row-span-2 min-w-0">
        {[0, 1].map((col) => (
          <div key={col} className="contents min-[2000px]:block min-[2000px]:order-first min-w-0">
            {sections.map((section, i) => (!section.fullWidth && stackOf[i] === col ? renderSection(section, i) : null))}
          </div>
        ))}
        {sections.map((section, i) => (section.fullWidth ? renderSection(section, i) : null))}
      </div>

      <aside className="mt-14 min-[2000px]:col-start-1 min-[2000px]:row-start-2 rounded-md border border-rail bg-seat p-6 sm:p-8">
        <p className={`${display} text-2xl font-extrabold tracking-[-0.03em] text-white`}>{cta.heading}</p>
        <p className="mt-3 text-[16px] leading-[1.6] text-gray-300">{cta.text}</p>
        <div className="mt-5 flex flex-wrap gap-3">
          <PTButton href="/download">Get SyncTogether</PTButton>
          <Link href="/vs/syncplay" className="inline-flex items-center h-[44px] text-sm font-semibold text-white underline underline-offset-4 decoration-rail hover:decoration-beam-500">
            Compare with Syncplay
          </Link>
        </div>
      </aside>

      <nav aria-label="More guides" className="mt-14 border-t border-rail pt-6 min-[2000px]:col-span-2 flex flex-col gap-4 sm:flex-row sm:items-baseline sm:gap-8">
        <p className={`${mono} text-[11px] tracking-[0.16em] uppercase text-gray-500`}>More guides</p>
        <ul className="flex flex-col gap-2 sm:flex-row sm:flex-wrap sm:gap-x-8">
          {GUIDES.filter((g) => g.path !== path).map((g) => (
            <li key={g.path}>
              <Link href={g.path} className="text-white underline underline-offset-4 decoration-rail hover:decoration-beam-500">
                {g.name}
              </Link>
            </li>
          ))}
          <li>
            <Link href="/guides" className="text-gray-400 hover:text-white underline underline-offset-4 decoration-rail">
              All guides
            </Link>
          </li>
        </ul>
      </nav>

      <p className="mt-6 text-[13px] leading-[1.55] text-gray-500 min-[2000px]:col-span-2">
        Product names mentioned here belong to their owners and are used only to describe what works with what. SyncTogether is not affiliated with or
        endorsed by them.
      </p>
    </article>
  );
}
