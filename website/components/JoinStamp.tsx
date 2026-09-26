import React from "react";

/**
 * The rubber stamp inked onto an invite ticket ("SEAT SAVED", "KEEP CODE FOR
 * LATER"). Purely decorative: it composes around `Ticket` rather than living
 * inside it, and callers position it so it overhangs the ticket's top edge -
 * a stamp never covers text.
 */
export function JoinStamp({
  top,
  big,
  bottom,
  className = "",
  size = "h-20 w-20 sm:h-24 sm:w-24",
  rotate = "rotate-[14deg]",
}: {
  top: string;
  big: string;
  bottom: string;
  className?: string;
  /** The boards size and angle each stamp: 96px at 14deg on /join, 90px at -10deg on /download. */
  size?: string;
  rotate?: string;
}) {
  return (
    <div
      aria-hidden="true"
      className={`pointer-events-none select-none flex ${size} flex-col items-center justify-center gap-0.5 rounded-full border-[3px] border-signal text-signal ${rotate} ${className}`}
    >
      <span className="font-[family-name:var(--font-jetbrains-mono)] text-[8px] sm:text-[10px] tracking-[0.14em] uppercase">
        {top}
      </span>
      <span className="font-[family-name:var(--font-space-grotesk)] font-extrabold text-base sm:text-xl leading-none uppercase">
        {big}
      </span>
      <span className="font-[family-name:var(--font-jetbrains-mono)] text-[8px] sm:text-[10px] tracking-[0.14em] uppercase">
        {bottom}
      </span>
    </div>
  );
}
