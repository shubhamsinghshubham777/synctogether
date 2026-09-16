const GRADE_COLORS: Record<string, string> = {
  bronze: "#D08C60",
  silver: "#CBD5E1",
  gold: "#FBBF24",
  secret: "#C084FC",
};

export function BadgeChip({ title, grade }: { title: string; grade: string }) {
  const color = GRADE_COLORS[grade] ?? GRADE_COLORS.bronze;
  return (
    <span
      className="inline-flex items-center gap-2 rounded-full px-3 py-1.5 text-xs font-semibold"
      style={{
        color,
        background: `${color}1F`,
        border: `1px solid ${color}59`,
      }}
    >
      <span
        className="inline-block h-1.5 w-1.5 rounded-full"
        style={{ background: color }}
        aria-hidden
      />
      {title}
    </span>
  );
}
