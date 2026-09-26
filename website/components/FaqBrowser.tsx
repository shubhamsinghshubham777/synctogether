"use client";

import { useEffect, useMemo, useState } from "react";
import { FAQAccordion } from "@/components/FAQAccordion";
import { display, mono } from "@/components/PageHead";

export interface FaqCategory {
  category: string;
  questions: { q: string; a: string; n: number }[];
}

export const faqSlug = (c: string) =>
  c.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/(^-|-$)/g, "");

/**
 * The FAQ body: search field (rendered into the masthead via `FaqSearch`),
 * a numbered category rail with a Beam rule on the section in view, and the
 * ruled accordions. Filtering is purely client-side over the static list.
 */
export function FaqBrowser({
  categories,
  supportEmail,
}: {
  categories: FaqCategory[];
  supportEmail: string;
}) {
  const [query, setQuery] = useState("");
  const [active, setActive] = useState(faqSlug(categories[0]?.category ?? ""));

  // The masthead's search input lives outside this tree; it broadcasts.
  useEffect(() => {
    const onQuery = (e: Event) => setQuery((e as CustomEvent<string>).detail);
    window.addEventListener("faq-query", onQuery);
    return () => window.removeEventListener("faq-query", onQuery);
  }, []);

  const filtered = useMemo(() => {
    const terms = query.trim().toLowerCase().split(/\s+/).filter(Boolean);
    if (!terms.length) return categories;
    return categories
      .map((c) => ({
        ...c,
        questions: c.questions.filter((q) => {
          const hay = `${q.q} ${q.a} ${c.category}`.toLowerCase();
          return terms.every((t) => hay.includes(t));
        }),
      }))
      .filter((c) => c.questions.length > 0);
  }, [categories, query]);

  // Light the rail entry for whichever section sits under the header.
  useEffect(() => {
    const els = filtered
      .map((c) => document.getElementById(faqSlug(c.category)))
      .filter((el): el is HTMLElement => !!el);
    if (!els.length) return;
    const io = new IntersectionObserver(
      (entries) => {
        const hit = entries.filter((e) => e.isIntersecting).sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top)[0];
        if (hit) setActive(hit.target.id);
      },
      { rootMargin: "-120px 0px -55% 0px" },
    );
    els.forEach((el) => io.observe(el));
    // Back at the top nothing intersects the band, so name the first section.
    const onScroll = () => {
      if (window.scrollY < 80) setActive(els[0].id);
    };
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => {
      io.disconnect();
      window.removeEventListener("scroll", onScroll);
    };
  }, [filtered]);

  const counts = new Map(filtered.map((c) => [c.category, c.questions.length]));
  const searching = query.trim().length > 0;

  return (
    <div className="grid lg:grid-cols-[260px_1fr] gap-10 lg:gap-[72px] items-start">
      <aside className="lg:sticky lg:top-28 flex flex-col gap-8 min-w-0">
        <nav aria-label="FAQ sections">
          <ol className={`${mono} flex flex-wrap lg:flex-col gap-x-5 gap-y-1 text-xs tracking-[0.12em] uppercase`}>
            {categories.map((cat, idx) => {
              const slug = faqSlug(cat.category);
              const count = counts.get(cat.category) ?? 0;
              const isActive = active === slug && count > 0;
              return (
                <li key={cat.category}>
                  <a
                    href={`#${slug}`}
                    onClick={() => setActive(slug)}
                    aria-current={isActive ? "true" : undefined}
                    className={`flex items-center gap-3 py-2 lg:pl-3 lg:border-l-2 transition-colors ${
                      isActive ? "lg:border-beam-500 text-white" : "lg:border-aisle text-gray-500 hover:text-white"
                    } ${count === 0 ? "opacity-40 pointer-events-none" : ""}`}
                  >
                    <span className="text-[#5A4F44]">{String(idx + 1).padStart(2, "0")}</span>
                    <span className="flex-1">{cat.category}</span>
                    <span className="text-[#5A4F44] hidden lg:inline">{count}</span>
                  </a>
                </li>
              );
            })}
          </ol>
        </nav>

        <div className="hidden lg:flex flex-col gap-3 rounded-md border border-rail bg-seat p-5">
          <p className={`${mono} text-[11px] tracking-[0.14em] uppercase text-gray-500`}>Still stuck?</p>
          <p className="text-sm leading-[1.55] text-gray-400">A real person reads every email.</p>
          <a
            href={`mailto:${supportEmail}`}
            className={`${mono} inline-block text-[13px] text-white underline underline-offset-4 decoration-rail hover:decoration-beam-500 transition-colors break-all`}
          >
            {supportEmail}
          </a>
        </div>
      </aside>

      <div className="space-y-10 min-w-0">
        {filtered.length === 0 && (
          <div className="border-y border-rail py-12 space-y-3">
            <p className={`${display} text-2xl font-extrabold tracking-[-0.03em] text-white`}>Nothing on the reel for that.</p>
            <p className="text-gray-400">
              Try another word, or{" "}
              <a href={`mailto:${supportEmail}`} className="text-white underline underline-offset-4 decoration-rail hover:decoration-beam-500">
                ask us directly
              </a>
              .
            </p>
          </div>
        )}
        {filtered.map((cat, idx) => {
          const orig = categories.findIndex((c) => c.category === cat.category);
          return (
            <section key={cat.category} id={faqSlug(cat.category)} className="scroll-mt-28">
              <div className="flex items-baseline gap-3.5 pb-3.5 border-b border-rail">
                <span className={`${mono} text-xs text-[#5A4F44]`}>{String(orig + 1).padStart(2, "0")}</span>
                <h2 className={`${display} text-3xl sm:text-[36px] font-extrabold leading-[0.92] tracking-[-0.04em] text-white`}>{cat.category}</h2>
              </div>
              <FAQAccordion
                key={searching ? `s-${query}` : "all"}
                items={cat.questions}
                defaultOpen={idx === 0 && !searching ? 0 : null}
                bare
              />
            </section>
          );
        })}

        <div className="lg:hidden rounded-md border border-rail bg-seat p-4 space-y-2.5">
          <p className={`${mono} text-[10px] tracking-[0.16em] uppercase text-gray-500`}>Still stuck?</p>
          <p className="text-sm text-gray-300">A real person reads every email.</p>
          <a href={`mailto:${supportEmail}`} className={`${mono} text-xs text-white underline underline-offset-4 decoration-rail break-all`}>
            {supportEmail}
          </a>
        </div>
      </div>
    </div>
  );
}

/** The masthead search field; talks to `FaqBrowser` through a window event. */
export function FaqSearch() {
  const [value, setValue] = useState("");
  return (
    <label className="block space-y-2.5">
      <span className={`${mono} block text-[10px] tracking-[0.18em] uppercase text-gray-500`}>Search the answers</span>
      <input
        type="search"
        value={value}
        onChange={(e) => {
          setValue(e.target.value);
          window.dispatchEvent(new CustomEvent("faq-query", { detail: e.target.value }));
        }}
        placeholder="e.g. refund, subtitles, Windows"
        className="w-full h-12 rounded-[4px] border border-rail bg-seat px-4 text-[15px] text-white placeholder:text-gray-500 outline-none focus:border-beam-500 transition-colors"
      />
    </label>
  );
}
