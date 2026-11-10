"use client";

import { AppStoreBadge } from "@/components/AppStoreBadge";
import { trackWebEvent } from "@/components/AnalyticsBeacon";
import { AppleLogo, WindowsLogo } from "@/components/Icons";
import { MicrosoftStoreBadge } from "@/components/MicrosoftStoreBadge";
import { useDesktopOS } from "@/components/hero/useDesktopOS";
import { display, mono } from "@/components/PageHead";

/**
 * The three store doors. The visitor's own device (client-detected - the page is
 * ISR, so the user-agent is never read server-side) gets the Seat surface, the
 * "Your device" tag and the only lit button; the others are outline. An
 * undetectable platform falls back to macOS, same as the home hero.
 */
export function DownloadDoors({ code }: { code?: string }) {
  const os = useDesktopOS();
  const winLit = os === "windows";
  const iosLit = os === "ios";
  const macLit = !winLit && !iosLit;
  // Android and anything else undetected still get the lit Mac button (the
  // fallback), but no door is "your device", so no tag.
  const detected = os === "macos" || winLit || iosLit;

  // The code does not survive the store install, so the click that leaves for
  // the store also puts the invite on the clipboard. The app's "Paste invite"
  // button picks it up. Capture phase: the badge is a link that navigates away.
  // No event for the iPhone door: the website_events table only accepts the
  // names its constraint lists (null = the click is not counted).
  const storeClick = (name: "store_click_mac" | "store_click_windows" | null) => () => {
    if (name) trackWebEvent(name);
    if (!code) return;
    navigator.clipboard?.writeText(`synctogether://join/${code}`).catch(() => {
      // Blocked clipboard: the code on the ticket is still the fallback.
    });
  };

  const tag = (
    <span className={`${mono} ml-3 rounded-[2px] bg-beam-500 px-[7px] py-[3px] text-[10px] tracking-[0.14em] text-booth`}>
      YOUR DEVICE
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
    <div className="grid lg:grid-cols-3 border border-rail rounded-md divide-y lg:divide-y-0 lg:divide-x divide-rail overflow-hidden">
      <section className={`flex flex-col p-6 sm:p-10 gap-[26px] ${macLit ? "bg-seat" : ""}`}>
        <div className="flex items-center justify-between gap-4">
          <p className={`${mono} flex items-center text-[11px] tracking-[0.14em] uppercase text-gray-500`}>
            Door A{macLit && detected && tag}
          </p>
          <AppleLogo className="w-5 h-5 text-gray-500 shrink-0" />
        </div>
        <h2 className={`${display} text-5xl sm:text-[64px] lg:text-[44px] xl:text-[52px] font-extrabold tracking-[-0.04em] leading-[0.92] text-white`}>macOS</h2>
        {specs([
          ["Build", "Universal · Apple Silicon & Intel"],
          ["From", "Mac App Store"],
          ["Needs", "macOS 12 Monterey or later"],
        ])}
        <div className="mt-auto" onClickCapture={storeClick("store_click_mac")}>
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
        <h2 className={`${display} text-5xl sm:text-[64px] lg:text-[44px] xl:text-[52px] font-extrabold tracking-[-0.04em] leading-[0.92] text-white`}>Windows</h2>
        {specs([
          ["Build", "64-bit · MSIX"],
          ["From", "Microsoft Store"],
          ["Needs", "Windows 10 / 11"],
        ])}
        <div className="mt-auto" onClickCapture={storeClick("store_click_windows")}>
          <MicrosoftStoreBadge lit={winLit} className="w-full" />
        </div>
      </section>

      <section className={`flex flex-col p-6 sm:p-10 gap-[26px] ${iosLit ? "bg-seat" : ""}`}>
        <div className="flex items-center justify-between gap-4">
          <p className={`${mono} flex items-center text-[11px] tracking-[0.14em] uppercase text-gray-500`}>
            Door C{iosLit && tag}
          </p>
          <AppleLogo className="w-5 h-5 text-gray-500 shrink-0" />
        </div>
        <h2 className={`${display} text-5xl sm:text-[64px] lg:text-[44px] xl:text-[52px] font-extrabold tracking-[-0.04em] leading-[0.92] text-white`}>
          iPhone &amp; iPad
        </h2>
        {specs([
          ["Build", "Universal · iPhone & iPad"],
          ["From", "App Store"],
          ["Needs", "iOS 15.6 or later"],
        ])}
        <div className="mt-auto" onClickCapture={storeClick(null)}>
          <AppStoreBadge lit={iosLit} className="w-full" />
        </div>
      </section>
    </div>
  );
}
