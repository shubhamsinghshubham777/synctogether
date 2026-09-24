"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";

/**
 * Below-the-fold sections rise into place once, the first time they scroll into
 * view. Never wrap the hero or anything above the fold: fading those in only
 * delays the moment the page looks ready. Reduced motion is handled in CSS.
 */
export function Reveal({ children, className = "" }: { children: ReactNode; className?: string }) {
  const ref = useRef<HTMLDivElement>(null);
  const [shown, setShown] = useState(false);

  useEffect(() => {
    const el = ref.current;
    if (!el || typeof IntersectionObserver === "undefined") {
      setShown(true);
      return;
    }
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          setShown(true);
          observer.disconnect();
        }
      },
      { rootMargin: "0px 0px -10% 0px" },
    );
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  return (
    <div ref={ref} className={`pt-reveal ${shown ? "pt-reveal-in" : ""} ${className}`}>
      {children}
    </div>
  );
}
