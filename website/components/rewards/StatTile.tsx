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
    <div className="glass-panel rounded-xl px-4 py-5 text-center">
      <p
        className={`text-2xl sm:text-3xl font-extrabold font-[family-name:var(--font-space-grotesk)] ${accent}`}
      >
        {value}
      </p>
      <p className="mt-1 text-xs uppercase tracking-[0.14em] text-gray-400">{label}</p>
    </div>
  );
}
