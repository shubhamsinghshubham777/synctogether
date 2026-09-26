"use client";

import { useState, useRef, useEffect } from "react";
import { useIsClient } from "@/lib/useIsClient";
import { usePricing } from "@/lib/usePricing";
import { COUNTRY_CURRENCY_MAP, isLocalEnvironment } from "@/lib/pricing";
import { Globe, ChevronDown, Check } from "lucide-react";

const mono = "font-[family-name:var(--font-jetbrains-mono)]";

interface LocationDebugSwitcherProps {
  className?: string;
}

export function LocationDebugSwitcher({ className = "" }: LocationDebugSwitcherProps) {
  // Reads window.location, so it must not run until the client render.
  const isLocal = useIsClient() && isLocalEnvironment();
  const { countryCode, currencyCode, currencySymbol, isMocked, mockCountry, setMockCountry } =
    usePricing();
  const [isOpen, setIsOpen] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

  // Close dropdown on outside click
  useEffect(() => {
    function handleClickOutside(event: MouseEvent) {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target as Node)) {
        setIsOpen(false);
      }
    }
    document.addEventListener("mousedown", handleClickOutside);
    return () => {
      document.removeEventListener("mousedown", handleClickOutside);
    };
  }, []);

  const chip = `${mono} inline-flex items-center gap-2 h-[38px] px-3 rounded-md border text-[11px] tracking-[0.08em] uppercase`;

  // Production shows the active currency as a plain chip; the simulator
  // dropdown is strictly local-only.
  if (!isLocal) {
    return (
      <span className={`${chip} border-rail text-gray-300 ${className}`} title="Prices shown in this currency">
        {currencyCode} · {currencySymbol}
      </span>
    );
  }

  const activeConfig = COUNTRY_CURRENCY_MAP[countryCode] || COUNTRY_CURRENCY_MAP["US"];

  return (
    <div ref={dropdownRef} className={`relative inline-block ${className}`}>
      {/* Trigger Button */}
      <button
        id="location-debug-btn"
        data-current-country={countryCode}
        data-current-currency={currencyCode}
        onClick={() => setIsOpen(!isOpen)}
        className={`${chip} cursor-pointer transition-colors ${
          isMocked ? "border-beam-500/60 text-beam-400" : "border-rail text-gray-300 hover:text-white"
        }`}
        title="Mock user location for currency and pricing testing (local only)"
      >
        <span>{currencyCode} · {currencySymbol}</span>
        <span className="text-gray-500">{countryCode}</span>
        {isMocked && <span className="text-[9px] text-beam-400">Mocked</span>}
        <ChevronDown className={`w-3 h-3 text-gray-500 transition-transform duration-200 ${isOpen ? "rotate-180" : ""}`} />
      </button>

      {/* Dropdown Menu */}
      {isOpen && (
        <div
          id="mock-country-dropdown"
          className="absolute right-0 mt-2 w-64 rounded-2xl bg-seat border border-rail shadow-2xl p-2 z-50 animate-in fade-in zoom-in-95 duration-150 space-y-1 text-xs"
        >
          <div className="px-2.5 py-1.5 border-b border-white/5 flex items-center justify-between">
            <span className="font-bold text-gray-300 uppercase tracking-wider text-[10px] font-mono">
              Simulate Location
            </span>
            <span className="text-[10px] text-purple-300/80 font-mono">Debug Tool</span>
          </div>

          {/* Auto Detect Option */}
          <button
            id="mock-country-auto"
            onClick={() => {
              setMockCountry(null);
              setIsOpen(false);
            }}
            className={`w-full flex items-center justify-between px-2.5 py-2 rounded-xl transition-colors text-left cursor-pointer ${
              !isMocked
                ? "bg-purple-600/30 text-white font-semibold"
                : "text-gray-300 hover:bg-white/5 hover:text-white"
            }`}
          >
            <span className="flex items-center gap-2">
              <Globe className="w-3.5 h-3.5 text-purple-400" />
              <span>Auto-detect (IP / Timezone)</span>
            </span>
            {!isMocked && <Check className="w-3.5 h-3.5 text-purple-300" />}
          </button>

          <div className="pt-1 pb-1 border-t border-white/5">
            <span className="px-2 text-[10px] text-gray-500 font-mono uppercase">
              Preset Countries
            </span>
          </div>

          {/* Preset Country Options */}
          <div className="max-h-52 overflow-y-auto space-y-0.5 pr-1">
            {Object.values(COUNTRY_CURRENCY_MAP).map((c) => {
              const isSelected = isMocked && mockCountry === c.country;
              return (
                <button
                  key={c.country}
                  id={`mock-country-${c.country.toLowerCase()}`}
                  onClick={() => {
                    setMockCountry(c.country);
                    setIsOpen(false);
                  }}
                  className={`w-full flex items-center justify-between px-2.5 py-1.5 rounded-xl transition-colors text-left cursor-pointer ${
                    isSelected
                      ? "bg-amber-500/20 text-amber-200 font-semibold border border-amber-400/30"
                      : "text-gray-300 hover:bg-white/5 hover:text-white"
                  }`}
                >
                  <span className="flex items-center gap-2">
                    <span>{c.flag}</span>
                    <span>{c.name}</span>
                  </span>
                  <span className="font-mono text-[11px] text-gray-400">
                    {c.currency} ({c.symbol})
                  </span>
                </button>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
}
