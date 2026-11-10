import type { Metadata } from "next";
import { normalizeRoomCode } from "@/lib/rewards";
import { Ticket } from "@/components/Ticket";
import { PageHead, display, mono } from "@/components/PageHead";
import { JoinStamp } from "@/components/JoinStamp";
import { DownloadDoors } from "@/components/DownloadDoors";
import { DownloadInviteActions } from "@/components/DownloadInviteActions";
import { SendToComputer } from "@/components/SendToComputer";

export const metadata: Metadata = {
  title: "Get SyncTogether for iPhone, iPad, Mac and Windows",
  description:
    "Get SyncTogether from the App Store (iPhone, iPad and Mac) or the Microsoft Store (Windows). Both keep it up to date for you.",
};

export const revalidate = 3600; // ISR hourly

export default async function DownloadPage({
  searchParams,
}: {
  searchParams: Promise<{ code?: string }>;
}) {
  const { code } = await searchParams;
  // Carried over from /join/<code> when the invite found nothing installed.
  // No store hands an install-referrer back to the app, so the code cannot survive
  // the install - showing it here is what lets somebody write it down before they leave.
  const inviteCode = normalizeRoomCode(code ?? "");

  return (
    <div className="relative pt-8 md:pt-14 pb-12 px-4 sm:px-6 lg:px-8 max-w-7xl min-[2000px]:max-w-[1920px] mx-auto space-y-10">
      <PageHead
        titleClassName="text-[clamp(2.75rem,7vw,5.5rem)]"
        gridClassName="lg:grid-cols-[1fr_480px] items-center"
        eyebrow={"Take your seat"}
        title={
          <>
            One tap.
            <br />
            Then you&apos;re in.
          </>
        }
        lede="Straight from the store: hardware-accelerated playback, no bloat, and the store keeps it up to date between shows."
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
                    It won&apos;t follow you through the store.
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
          ) : undefined
        }
      />

      <div className="space-y-10 min-[2000px]:space-y-0 min-[2000px]:grid min-[2000px]:grid-cols-[1.6fr_1fr] min-[2000px]:grid-rows-[auto_1fr] min-[2000px]:gap-x-16 min-[2000px]:items-start">
      <div className="min-[2000px]:col-start-2 min-[2000px]:row-start-1">
        <SendToComputer />
      </div>

      <div className="min-[2000px]:col-start-1 min-[2000px]:row-start-1 min-[2000px]:row-span-2 min-w-0">
        <DownloadDoors code={inviteCode ?? undefined} />
      </div>

      <section className="grid md:grid-cols-3 min-[2000px]:grid-cols-1! gap-8 md:gap-10 min-[2000px]:col-start-2 min-[2000px]:row-start-2 min-[2000px]:pt-10">
        {[
          {
            label: "Store-verified",
            body: "Reviewed and signed by the store. No scary warnings, no installer to hunt down.",
          },
          {
            label: "Updates itself",
            body: "The store installs new versions in the background, never mid-film.",
          },
          {
            label: "Every screen you own",
            body: "iPhone, iPad, Mac and Windows, with one account across all of them.",
          },
        ].map(({ label, body }) => (
          <div key={label} className="border-t border-rail pt-[18px] space-y-2.5">
            <p
              className={`${mono} text-[11px] tracking-[0.14em] uppercase text-gray-500`}
            >
              {label}
            </p>
            <p className="text-[15px] text-gray-400 leading-[1.55]">{body}</p>
          </div>
        ))}
      </section>
      </div>
    </div>
  );
}
