const GRADE_COLORS: Record<string, string> = {
  bronze: "#D08C60",
  silver: "#C9BDAC",
  gold: "#E8C877",
  secret: "#FFB23F",
};

/** A badge as a small ink tag: hairline border in the grade's colour, mono caps. */
export function BadgeChip({ title, grade }: { title: string; grade: string }) {
  const color = GRADE_COLORS[grade] ?? GRADE_COLORS.bronze;
  return (
    <span
      className="inline-flex items-center gap-2 rounded-[4px] px-2.5 py-1.5 font-[family-name:var(--font-jetbrains-mono)] text-[11px] uppercase tracking-[0.1em]"
      style={{ color, border: `1px solid ${color}80` }}
      title={`${title} · ${grade}`}
    >
      <span className="inline-block h-1.5 w-1.5 rounded-full" style={{ background: color }} aria-hidden />
      {title}
    </span>
  );
}
