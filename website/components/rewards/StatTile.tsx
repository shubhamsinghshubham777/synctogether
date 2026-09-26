/**
 * A number and what it counts, set like a programme credit: a hairline above,
 * a Bricolage figure, a mono caption. No box - the rule does the framing.
 */
export function StatTile({
  value,
  label,
  accent = "text-white",
}: {
  value: string;
  label: string;
  accent?: string;
}) {
  return (
    <div className="border-t-2 border-rail pt-4 min-w-0">
      <p
        className={`text-[clamp(1.75rem,5vw,2.75rem)] leading-none font-extrabold tracking-[-0.04em] tabular-nums font-[family-name:var(--font-space-grotesk)] truncate ${accent}`}
      >
        {value}
      </p>
      <p className="mt-2 font-[family-name:var(--font-jetbrains-mono)] text-[10px] sm:text-[11px] uppercase tracking-[0.14em] text-gray-500">
        {label}
      </p>
    </div>
  );
}
