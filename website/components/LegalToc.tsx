"use client";

import React, { useEffect, useState } from "react";
import { mono } from "@/components/booth/Booth";

export type LegalTocItem = { id: string; n: string; label: string };

/**
 * "On this page": anchors to each numbered section, with the one currently
 * under the reading line lit. The observer only flips state on a section
 * edge, never per scroll tick.
 */
export function LegalToc({ items }: { items: LegalTocItem[] }) {
  const [active, setActive] = useState<string | null>(null);

  useEffect(() => {
    const els = items.map((i) => document.getElementById(i.id)).filter((e): e is HTMLElement => !!e);
    if (!els.length || typeof IntersectionObserver === "undefined") return;
    const obs = new IntersectionObserver(
      (entries) => {
        const hit = entries.filter((e) => e.isIntersecting).sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top)[0];
        if (hit) setActive(hit.target.id);
      },
      { rootMargin: "-20% 0px -70% 0px" },
    );
    els.forEach((e) => obs.observe(e));
    return () => obs.disconnect();
  }, [items]);

  return (
    <nav aria-label="On this page" className="border-t border-rail pt-6">
      <p className={`${mono} text-[10px] tracking-[0.16em] uppercase text-gray-500 mb-3`}>On this page</p>
      <ol className="space-y-2">
        {items.map((i) => (
          <li key={i.id}>
            <a
              href={`#${i.id}`}
              aria-current={active === i.id ? "location" : undefined}
              className={`flex gap-3 text-sm leading-snug transition-colors ${
                active === i.id ? "text-white" : "text-gray-400 hover:text-white"
              }`}
            >
              <span className={`${mono} text-[11px] pt-[3px] w-5 shrink-0 ${active === i.id ? "text-beam-500" : "text-gray-600"}`}>
                {i.n}
              </span>
              <span className="min-w-0">{i.label}</span>
            </a>
          </li>
        ))}
      </ol>
    </nav>
  );
}
