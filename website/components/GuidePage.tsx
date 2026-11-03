import type { ReactNode } from "react";
import Link from "next/link";
import { PTButton } from "@/components/PTButton";
import { display, mono } from "@/components/booth/Booth";

export interface GuideSection {
  heading: string;
  /** Paragraphs, or a numbered list when `items` is given. */
  body?: string[];
  items?: { title: string; text: string }[];
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
}: {
  eyebrow: string;
  title: ReactNode;
  /** The 40-60 word direct answer the article opens with. */
  answer: string;
  sections: GuideSection[];
  cta: { heading: string; text: string };
  updated: string;
}) {
  // Numbering continues across sections, so work out where each one starts.
  const starts = sections.reduce<number[]>(
    (acc, section, i) => [...acc, (acc[i - 1] ?? 0) + (sections[i - 1]?.items?.length ?? 0)],
    [],
  );
  return (
    <article className="px-4 sm:px-6 lg:px-8 max-w-3xl mx-auto pt-8 md:pt-12 pb-16">
      <p className={`${mono} text-xs tracking-[0.14em] uppercase text-gray-500`}>
        <span className="text-beam-500">{eyebrow}</span> · Updated {updated}
      </p>
      <h1 className={`${display} mt-4 text-[clamp(2.25rem,5.5vw,3.75rem)] font-extrabold leading-[0.95] tracking-[-0.04em] text-white`}>
        {title}
      </h1>
      <p className="mt-6 text-lg sm:text-[19px] leading-[1.55] text-white">{answer}</p>

      {sections.map((section, sectionIndex) => (
        <section key={section.heading} className="mt-12">
          <h2 className={`${display} text-2xl sm:text-3xl font-extrabold tracking-[-0.03em] text-white`}>
            {section.heading}
          </h2>
          {section.body?.map((paragraph) => (
            <p key={paragraph.slice(0, 40)} className="mt-4 text-[17px] leading-[1.65] text-gray-300">
              {paragraph}
            </p>
          ))}
          {section.items && (
            <ol className="mt-5 border-t border-aisle">
              {section.items.map((item, itemIndex) => (
                <li key={item.title} className="grid grid-cols-[2.5rem_1fr] gap-3 border-b border-aisle py-4">
                  <span className={`${mono} text-sm text-gray-500`}>
                    {String(starts[sectionIndex] + itemIndex + 1).padStart(2, "0")}
                  </span>
                  <div>
                    <p className="font-semibold text-white">{item.title}</p>
                    <p className="mt-1 text-[16px] leading-[1.6] text-gray-400">{item.text}</p>
                  </div>
                </li>
              ))}
            </ol>
          )}
        </section>
      ))}

      <aside className="mt-14 rounded-md border border-rail bg-seat p-6 sm:p-8">
        <p className={`${display} text-2xl font-extrabold tracking-[-0.03em] text-white`}>{cta.heading}</p>
        <p className="mt-3 text-[16px] leading-[1.6] text-gray-300">{cta.text}</p>
        <div className="mt-5 flex flex-wrap gap-3">
          <PTButton href="/download">Get SyncTogether</PTButton>
          <Link
            href="/vs/syncplay"
            className="inline-flex items-center h-[44px] px-4 text-sm font-semibold text-white underline underline-offset-4 decoration-rail hover:decoration-beam-500"
          >
            Compare with Syncplay
          </Link>
        </div>
      </aside>
    </article>
  );
}
