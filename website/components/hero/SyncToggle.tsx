"use client";

export function SyncToggle({
  synced,
  onToggle,
  disabled,
}: {
  synced: boolean;
  onToggle: () => void;
  disabled?: boolean;
}) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={synced}
      aria-label={synced ? "Perfectly in sync. Toggle to see what desync looks like." : "Out of sync. Toggle to bring everyone back together."}
      onClick={onToggle}
      disabled={disabled}
      className="inline-flex items-center gap-3 px-4 py-2 rounded-full bg-[#141022]/80 border border-white/10 hover:border-purple-400/40 transition-colors cursor-pointer disabled:cursor-default disabled:opacity-70"
    >
      <span className={`text-xs font-mono font-semibold ${synced ? "text-gray-500" : "text-red-300"}`}>
        Without sync
      </span>
      <span className="relative w-10 h-5 rounded-full bg-white/15">
        <span
          className={`absolute inset-0 rounded-full bg-emerald-500/70 transition-opacity ${
            synced ? "opacity-100" : "opacity-0"
          }`}
        />
        <span
          className={`absolute top-0.5 left-0.5 w-4 h-4 rounded-full bg-white shadow transition-transform ${
            synced ? "translate-x-5" : "translate-x-0"
          }`}
        />
      </span>
      <span className={`text-xs font-mono font-semibold ${synced ? "text-emerald-300" : "text-gray-500"}`}>
        With SyncTogether
      </span>
    </button>
  );
}
