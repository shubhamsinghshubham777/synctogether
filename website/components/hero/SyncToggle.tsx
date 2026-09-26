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
      className={`inline-flex items-center gap-3.5 px-4 py-2.5 rounded-[4px] bg-seat border border-rail cursor-pointer disabled:cursor-progress`}
    >
      <span className={`text-sm sm:text-[15px] font-semibold transition-colors ${synced ? "text-gray-500" : "text-screen"}`}>
        Without sync
      </span>
      <span className="relative shrink-0 w-[52px] h-7 rounded-full bg-rail">
        <span
          className={`absolute inset-0 rounded-full bg-beam-500 transition-opacity duration-300 ${
            synced ? "opacity-100" : "opacity-0"
          }`}
        />
        <span
          className={`absolute top-[3px] left-[3px] w-[22px] h-[22px] rounded-full transition-[transform,background-color] ${synced ? "bg-[#1A1206]" : "bg-screen"} duration-300 ease-[cubic-bezier(0.34,1.56,0.64,1)] ${
            synced ? "translate-x-6" : "translate-x-0"
          } ${disabled ? "translate-x-3" : ""} flex items-center justify-center`}
        >
          {/* Disabled only while the sync tween runs - say so, rather than go dead. */}
          {disabled && <Loader2 className="w-3.5 h-3.5 text-booth animate-spin" />}
        </span>
      </span>
      <span className={`text-sm sm:text-[15px] font-semibold transition-colors ${synced ? "text-screen" : "text-gray-500"}`}>
        With SyncTogether
      </span>
    </button>
  );
}
