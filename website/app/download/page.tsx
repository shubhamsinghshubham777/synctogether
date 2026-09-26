import type { Metadata } from "next";
import Link from "next/link";
import { getLatestRelease } from "@/lib/github";
import { normalizeRoomCode } from "@/lib/rewards";
import { Ticket } from "@/components/Ticket";
import { PageHead, display, mono } from "@/components/PageHead";
import { JoinStamp } from "@/components/JoinStamp";
import { DownloadDoors } from "@/components/DownloadDoors";
import { DownloadInviteActions } from "@/components/DownloadInviteActions";

export const metadata: Metadata = {
  title: "Download SyncTogether for macOS and Windows",
  description:
    "Download the latest version of SyncTogether standalone desktop app for macOS (Apple Silicon & Intel) and Windows 10/11.",
};

export const revalidate = 3600; // ISR hourly

export default async function DownloadPage({
  searchParams,
}: {
  searchParams: Promise<{ code?: string }>;
}) {
  const [release, { code }] = await Promise.all([getLatestRelease(), searchParams]);
  const displayTag = release.name || `v${release.version || "0.11.0"}`;
  // Carried over from /join/<code> when the invite found nothing installed.
  // Desktop has no install-referrer, so the code cannot survive the installer -
  // showing it here is what lets somebody write it down before they leave.
  const inviteCode = normalizeRoomCode(code ?? "");

  return (
    <div className="relative pt-8 md:pt-14 pb-12 px-4 sm:px-6 lg:px-8 max-w-7xl mx-auto space-y-10">
      <PageHead
        titleClassName="text-[clamp(2.75rem,7vw,5.5rem)]"
        gridClassName="lg:grid-cols-[1fr_480px] items-center"
        eyebrow={<>Take your seat · v{release.version}</>}
        title={
          <>
            One install.
            <br />
            Then you&apos;re in.
          </>
        }
        lede="A native desktop app: hardware-accelerated playback, no bloat, and it updates itself quietly between shows."
        aside={
          inviteCode ? (
            <div className="space-y-4 pt-12 lg:pt-0">
              <div className="relative">
                <Ticket
                  animate
                  stubClassName="w-28 sm:w-[140px]"
                  stub={
                    <span className={`${mono} text-base sm:text-xl font-semibold tracking-[0.1em]`}>{inviteCode}</span>
                  }
                >
                  <p className={`${mono} text-[10px] sm:text-[11px] tracking-[0.16em] uppercase text-[#A33A22]`}>
                    Admit one
                  </p>
                  <p className={`${display} mt-1.5 text-xl sm:text-[26px] font-extrabold tracking-[-0.035em] leading-[0.98]`}>
                    Install, then join with this code.
                  </p>
                  <p className="mt-3 text-xs sm:text-sm text-[#5A4F44]">
                    It won&apos;t follow you through the installer.
                  </p>
                </Ticket>
                {/* Overhangs the top edge, left of the perforation, clear of the copy. */}
                <JoinStamp
                  top="Keep"
                  big="Code"
                  bottom="For later"
                  size="h-20 w-20 sm:h-[90px] sm:w-[90px]"
                  rotate="-rotate-[10deg]"
                  className="absolute -top-12 sm:-top-[46px] right-[6.5rem] sm:right-[150px]"
                />
              </div>
              <DownloadInviteActions code={inviteCode} />
            </div>
          ) : (
            <Link
              href="/changelog"
              className="group block border-l-2 border-beam-500 pl-5 py-1 space-y-1.5"
            >
              <span className={`${mono} block text-[11px] tracking-[0.16em] uppercase text-gray-500`}>Now showing</span>
              <span className={`${display} block text-xl font-extrabold tracking-[-0.02em] text-white`}>
                {displayTag.replace(/^SyncTogether\s+/, "")}
              </span>
              <span className="block text-sm text-gray-400 group-hover:text-white transition-colors">
                What&apos;s new in this release →
              </span>
            </Link>
          )
        }
      />

      <DownloadDoors version={release.version} macSizeMb={release.macSizeMb} winSizeMb={release.winSizeMb} />

      <section className="grid md:grid-cols-3 gap-8 md:gap-10">
        {[
          {
            label: "Signed & notarized",
            body: "Apple Developer ID on the Mac, a signed installer on Windows. No scary warnings.",
          },
          {
            label: "Updates itself",
            body: "New versions download in the background and install from the lobby, never mid-film.",
          },
          {
            label: "In rehearsal",
            body: "iPhone, iPad and Android are on the way. Big screens first.",
            live: true,
          },
        ].map(({ label, body, live }) => (
          <div key={label} className="border-t border-rail pt-[18px] space-y-2.5">
            <p
              className={`${mono} flex items-center gap-2 text-[11px] tracking-[0.14em] uppercase ${
                live ? "text-signal" : "text-gray-500"
              }`}
            >
              {live && <span className="w-1.5 h-1.5 rounded-full bg-signal" aria-hidden="true" />}
              {label}
            </p>
            <p className="text-[15px] text-gray-400 leading-[1.55]">{body}</p>
          </div>
        ))}
      </section>
    </div>
  );
}
