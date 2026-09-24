"use client";

import { Loader2 } from "lucide-react";

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
      aria-busy={disabled}
      aria-label={synced ? "Perfectly in sync. Toggle to see what desync looks like." : "Out of sync. Toggle to bring everyone back together."}
      onClick={onToggle}
      disabled={disabled}
      className={`inline-flex items-center gap-4 sm:gap-5 px-5 py-3 sm:px-7 sm:py-4 rounded-full bg-[#141022]/90 border transition-[border-color,box-shadow] duration-300 cursor-pointer disabled:cursor-progress ${synced ? "border-emerald-400/40 shadow-[0_0_40px_-10px_rgba(52,211,153,0.55)]" : "border-red-400/40 shadow-[0_0_40px_-10px_rgba(248,113,113,0.55)]"} hover:border-purple-300/60`}
    >
      <span className={`text-sm sm:text-lg font-bold font-[family-name:var(--font-space-grotesk)] transition-colors ${synced ? "text-gray-500" : "text-red-300"}`}>
        Without sync
      </span>
      <span className="relative shrink-0 w-14 h-7 sm:w-16 sm:h-8 rounded-full bg-red-500/40">
        <span
          className={`absolute inset-0 rounded-full bg-emerald-500/80 transition-opacity duration-300 ${
            synced ? "opacity-100" : "opacity-0"
          }`}
        />
        <span
          className={`absolute top-1 left-1 w-5 h-5 sm:w-6 sm:h-6 rounded-full bg-white shadow-lg transition-transform duration-300 ease-[cubic-bezier(0.34,1.56,0.64,1)] ${
            synced ? "translate-x-7 sm:translate-x-8" : "translate-x-0"
          } ${disabled ? "translate-x-3.5 sm:translate-x-4" : ""} flex items-center justify-center`}
        >
          {/* Disabled only while the sync tween runs - say so, rather than go dead. */}
          {disabled && <Loader2 className="w-3.5 h-3.5 text-emerald-600 animate-spin" />}
        </span>
      </span>
      <span className={`text-sm sm:text-lg font-bold font-[family-name:var(--font-space-grotesk)] transition-colors ${synced ? "text-emerald-300" : "text-gray-500"}`}>
        With SyncTogether
      </span>
    </button>
  );
}
