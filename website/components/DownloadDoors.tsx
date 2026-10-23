"use client";

import { AppStoreBadge } from "@/components/AppStoreBadge";
import { AppleLogo, WindowsLogo } from "@/components/Icons";
import { MicrosoftStoreBadge } from "@/components/MicrosoftStoreBadge";
import { useDesktopOS } from "@/components/hero/useDesktopOS";
import { display, mono } from "@/components/PageHead";

/**
 * The two store doors. The visitor's own machine (client-detected - the page is
 * ISR, so the user-agent is never read server-side) gets the Seat surface, the
 * "Your machine" tag and the only lit button; the other door is outline. An
 * undetectable platform falls back to macOS, same as the home hero.
 */
export function DownloadDoors({ code }: { code?: string }) {
  const os = useDesktopOS();
  const winLit = os === "windows";
  const macLit = !winLit;

  // The code does not survive the store install, so the click that leaves for
  // the store also puts the invite on the clipboard. The app's "Paste invite"
  // button picks it up. Capture phase: the badge is a link that navigates away.
  const carryInvite = code
    ? () => {
        navigator.clipboard?.writeText(`synctogether://join/${code}`).catch(() => {
          // Blocked clipboard: the code on the ticket is still the fallback.
        });
      }
    : undefined;

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
          ["From", "Mac App Store"],
          ["Needs", "macOS 12 Monterey or later"],
        ])}
        <div className="mt-auto" onClickCapture={carryInvite}>
          <AppStoreBadge lit={macLit} className="w-full" />
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
          ["Build", "64-bit · MSIX"],
          ["From", "Microsoft Store"],
          ["Needs", "Windows 10 / 11"],
        ])}
        <div className="mt-auto" onClickCapture={carryInvite}>
          <MicrosoftStoreBadge lit={winLit} className="w-full" />
        </div>
      </section>
    </div>
  );
}
