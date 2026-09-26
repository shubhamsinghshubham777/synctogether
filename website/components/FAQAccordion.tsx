"use client";

import { useId, useState } from "react";

interface FAQItem {
  q: string;
  a: string;
  /** Fixed display number; wins over `startAt + idx` so filtering keeps numbers stable. */
  n?: number;
}

interface FAQAccordionProps {
  items: FAQItem[];
  /** Offsets the Q.nn numbering when a page splits one list into sections. */
  startAt?: number;
  /** Index open on first render; null (default) starts all closed. */
  defaultOpen?: number | null;
  /** Drop the top rule when a heading above already draws one. */
  bare?: boolean;
}

/**
 * Questions as a ruled list, not a stack of cards: Rail hairlines between rows,
 * a mono Q.nn number, and a plus that turns into a minus. The open answer
 * slides down via a grid-rows transition, which stops the moment it settles.
 *
 * Ids come from `useId` because a page renders several of these (one per FAQ
 * category), and index-based ids collided across them.
 */
export function FAQAccordion({ items, startAt = 0, defaultOpen = null, bare = false }: FAQAccordionProps) {
  // Keyed by question text so a filtered list keeps the right row open.
  const [openQ, setOpenQ] = useState<string | null>(
    defaultOpen == null ? null : (items[defaultOpen]?.q ?? null),
  );
  const uid = useId();

  return (
    <ul className={bare ? "" : "border-t border-rail"}>
      {items.map((item, idx) => {
        const isOpen = openQ === item.q;
        const panelId = `${uid}-panel-${idx}`;
        const buttonId = `${uid}-btn-${idx}`;
        const n = String(item.n ?? startAt + idx + 1).padStart(2, "0");

        return (
          <li key={item.q} className="border-b border-aisle">
            <button
              id={buttonId}
              onClick={() => setOpenQ(isOpen ? null : item.q)}
              aria-expanded={isOpen}
              aria-controls={panelId}
              className={`group w-full pt-[22px] ${isOpen ? "pb-3.5" : "pb-[22px]"} text-left grid grid-cols-[36px_1fr_auto] items-center gap-x-4 sm:gap-x-5 cursor-pointer transition-[padding] duration-300`}
            >
              <span
                className={`font-[family-name:var(--font-jetbrains-mono)] text-[11px] transition-colors ${
                  isOpen ? "text-beam-500" : "text-[#5A4F44]"
                }`}
              >
                Q.{n}
              </span>
              <span
                className={`font-[family-name:var(--font-space-grotesk)] text-[17px] sm:text-[22px] font-extrabold tracking-[-0.02em] leading-[1.2] transition-colors ${
                  isOpen ? "text-white" : "text-[#E4D9C8] group-hover:text-white"
                }`}
              >
                {item.q}
              </span>
              <span
                aria-hidden="true"
                className={`relative w-3 h-3 self-center shrink-0 transition-colors ${isOpen ? "text-beam-500" : "text-gray-500 group-hover:text-white"}`}
              >
                <span className="absolute inset-x-0 top-1/2 h-[1.5px] -translate-y-1/2 bg-current" />
                <span
                  className={`absolute inset-y-0 left-1/2 w-[1.5px] -translate-x-1/2 bg-current transition-transform duration-300 ease-[cubic-bezier(0.2,0.8,0.2,1)] ${
                    isOpen ? "scale-y-0" : "scale-y-100"
                  }`}
                />
              </span>
            </button>

            <div
              id={panelId}
              role="region"
              aria-labelledby={buttonId}
              className={`grid transition-[grid-template-rows,opacity] duration-300 ease-[cubic-bezier(0.2,0.8,0.2,1)] ${
                isOpen ? "grid-rows-[1fr] opacity-100" : "grid-rows-[0fr] opacity-0 pointer-events-none"
              }`}
            >
              <div className="overflow-hidden">
                <p className="pb-[22px] sm:pl-14 text-[15px] sm:text-base text-gray-300 leading-[1.55] max-w-[736px]">
                  {item.a}
                </p>
              </div>
            </div>
          </li>
        );
      })}
    </ul>
  );
}
