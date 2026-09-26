"use client";

import { Download } from "lucide-react";
import { PTButton } from "@/components/PTButton";
import { AppleLogo, WindowsLogo } from "@/components/Icons";
import { MicrosoftStoreBadge } from "@/components/MicrosoftStoreBadge";
import { useDesktopOS } from "@/components/hero/useDesktopOS";
import { display, mono } from "@/components/PageHead";

interface DownloadDoorsProps {
  version: string;
  macSizeMb: string | number;
  winSizeMb: string | number;
}

/**
 * The two doors. The visitor's own machine (client-detected - the page is ISR,
 * so the user-agent is never read server-side) gets the Seat surface, the
 * "Your machine" tag and the only lit button; the other door is outline. An
 * undetectable platform falls back to macOS, same as the home hero.
 */
export function DownloadDoors({ version, macSizeMb, winSizeMb }: DownloadDoorsProps) {
  const os = useDesktopOS();
  const winLit = os === "windows";
  const macLit = !winLit;

  const tag = (
    <span className={`${mono} ml-3 rounded-[2px] bg-beam-500 px-[7px] py-[3px] text-[10px] tracking-[0.14em] text-booth`}>
      YOUR MACHINE
    </span>
  );

  const specs = (rows: [string, string][]) => (
    <dl className={`${mono} text-xs sm:text-[13px] border-y border-rail py-2.5`}>
      {rows.map(([k, v]) => (
        <div key={k} className="grid grid-cols-[6rem_1fr] sm:grid-cols-[110px_1fr] gap-4 py-[9px]">
          <dt className="text-gray-500 uppercase tracking-[0.12em]">{k}</dt>
          <dd className="text-white">{v}</dd>
        </div>
      ))}
    </dl>
  );

  return (
    <div className="grid md:grid-cols-2 border border-rail rounded-md divide-y md:divide-y-0 md:divide-x divide-rail overflow-hidden">
      <section className={`flex flex-col p-6 sm:p-10 gap-[26px] ${macLit ? "bg-seat" : ""}`}>
        <div className="flex items-center justify-between gap-4">
          <p className={`${mono} flex items-center text-[11px] tracking-[0.14em] uppercase text-gray-500`}>
            Door A{macLit && tag}
          </p>
          <AppleLogo className="w-5 h-5 text-gray-500 shrink-0" />
        </div>
        <h2 className={`${display} text-5xl sm:text-[64px] font-extrabold tracking-[-0.04em] leading-[0.92] text-white`}>macOS</h2>
        {specs([
          ["Build", "Universal · Apple Silicon & Intel"],
          ["Version", version],
          ["Size", `~${macSizeMb} MB`],
          ["Needs", "macOS 12 Monterey or later"],
        ])}
        <div className="mt-auto">
          <PTButton
            href="/api/download?platform=macos"
            variant={macLit ? "primary" : "secondary"}
            className="w-full !h-[54px] !rounded-[4px] !text-base !font-semibold !gap-2.5"
            leftIcon={<Download strokeWidth={1.8} className="w-[18px] h-[18px]" />}
          >
            Download for macOS (.dmg)
          </PTButton>
        </div>
      </section>

      <section className={`flex flex-col p-6 sm:p-10 gap-[26px] ${winLit ? "bg-seat" : ""}`}>
        <div className="flex items-center justify-between gap-4">
          <p className={`${mono} flex items-center text-[11px] tracking-[0.14em] uppercase text-gray-500`}>
            Door B{winLit && tag}
          </p>
          <WindowsLogo className="w-5 h-5 text-gray-500 shrink-0" />
        </div>
        <h2 className={`${display} text-5xl sm:text-[64px] font-extrabold tracking-[-0.04em] leading-[0.92] text-white`}>Windows</h2>
        {specs([
          ["Build", "64-bit installer"],
          ["Version", version],
          ["Size", `~${winSizeMb} MB`],
          ["Needs", "Windows 10 / 11 · WebView2"],
        ])}
        <div className="mt-auto grid grid-cols-1 sm:grid-cols-2 gap-3">
          <PTButton
            href="/api/download?platform=windows"
            variant={winLit ? "primary" : "secondary"}
            className="w-full !h-[54px] !rounded-[4px] !text-base !font-semibold !gap-2.5"
            leftIcon={<Download strokeWidth={1.8} className="w-[18px] h-[18px]" />}
          >
            Download .exe
          </PTButton>
          <MicrosoftStoreBadge className="w-full" />
        </div>
      </section>
    </div>
  );
}
