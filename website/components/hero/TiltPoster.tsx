"use client";

import { useRef, type ReactNode, type PointerEvent } from "react";

/** Degrees of tilt at the poster's edge. Small: a nudge, not a card flip. */
const MAX_TILT = 6;

/**
 * Tilts the hero poster toward the pointer. The rotation is written straight
 * to CSS variables on the element (one rAF per pointer move, no React state),
 * and the children lift off it via `translateZ` so the ticket and the stamp
 * drift against the screen. Mouse and pen only; touch and reduced motion get
 * the still poster (the media query lives in globals.css).
 */
export function TiltPoster({ children }: { children: ReactNode }) {
  const ref = useRef<HTMLDivElement>(null);
  const frame = useRef(0);

  const set = (x: number, y: number) => {
    const el = ref.current;
    if (!el) return;
    cancelAnimationFrame(frame.current);
    frame.current = requestAnimationFrame(() => {
      el.style.setProperty("--tilt-x", `${(-y * MAX_TILT).toFixed(2)}deg`);
      el.style.setProperty("--tilt-y", `${(x * MAX_TILT).toFixed(2)}deg`);
    });
  };

  const onMove = (e: PointerEvent<HTMLDivElement>) => {
    if (e.pointerType === "touch") return;
    const r = e.currentTarget.getBoundingClientRect();
    set((e.clientX - r.left) / r.width - 0.5, (e.clientY - r.top) / r.height - 0.5);
  };

  return (
    <div className="tilt-stage" onPointerMove={onMove} onPointerLeave={() => set(0, 0)}>
      <div ref={ref} className="tilt-poster">
        {children}
      </div>
    </div>
  );
}
