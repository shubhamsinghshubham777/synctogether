import React from "react";

export const display = "font-[family-name:var(--font-space-grotesk)]";
export const mono = "font-[family-name:var(--font-jetbrains-mono)]";

/** The mono eyebrow, numbered like a reel when `n` is given. */
export function Eyebrow({
  n,
  children,
  className = "",
}: {
  n?: string;
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <p className={`${mono} text-xs tracking-[0.16em] uppercase text-beam-500 ${className}`}>
      {n && <span className="text-[#5A4F44]">{n} · </span>}
      {children}
    </p>
  );
}

/**
 * An inner page's masthead: eyebrow, a Bricolage 800 headline set tight, and
 * a standfirst. Left-aligned and editorial, like the home hero - inner pages
 * used to open on a centred headline with a glow blob behind it.
 */
export function PageHead({
  eyebrow,
  title,
  lede,
  aside,
  titleClassName = "text-[clamp(2.5rem,6vw,4.5rem)]",
  gridClassName = "lg:grid-cols-[1.3fr_1fr] items-end",
}: {
  eyebrow: React.ReactNode;
  title: React.ReactNode;
  lede?: React.ReactNode;
  /** Sits to the right of the headline on wide screens, under it on narrow. */
  aside?: React.ReactNode;
  /** Headline size; the boards set most mastheads at 72px, Download at 88. */
  titleClassName?: string;
  gridClassName?: string;
}) {
  return (
    <header className={`relative grid ${gridClassName} gap-8 lg:gap-16 pb-8 md:pb-11 after:absolute after:bottom-0 after:left-1/2 after:-translate-x-1/2 after:w-screen after:h-px after:bg-aisle`}>
      <div className="flex flex-col gap-[22px] min-w-0">
        <Eyebrow>{eyebrow}</Eyebrow>
        <h1
          className={`${display} font-extrabold ${titleClassName} leading-[0.9] tracking-[-0.045em] text-white`}
        >
          {title}
        </h1>
        {lede && <p className="text-lg sm:text-[19px] leading-[1.55] text-gray-300 max-w-[35rem]">{lede}</p>}
      </div>
      {aside && <div className="min-w-0">{aside}</div>}
    </header>
  );
}
