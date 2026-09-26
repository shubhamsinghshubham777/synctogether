import Image from "next/image";
import { Ticket } from "@/components/Ticket";

/** A real 1280x720 capture of the app's theatre room (lib/mock/store_capture.dart). */
const SHOT = "/shots/room-theater.jpg";

/**
 * The hero's right side, from the Booth Light canvas: the app itself on a
 * screen tilted on the booth wall, an invite ticket tucked against it and a
 * "no ads" stamp pressed onto the corner. The screenshot already carries the
 * room's own transport, so nothing is drawn under it and nothing animates
 * beyond the entrance.
 */
export function HeroPoster() {
  // Geometry is the board's, as fractions of its 580x440 frame: a 580x337
  // screen, a 400x140 ticket at (200, 300), a 110px stamp 10px in and 30px up.
  return (
    <div className="relative mx-auto w-full max-w-[580px] aspect-[580/440] [container-type:inline-size] [transform-style:preserve-3d]">
      {/* The screen */}
      <div className="hero-screen absolute left-0 top-0 w-full rounded-md bg-seat border border-rail p-[2.07%]">
        <div className="relative w-full aspect-video overflow-hidden rounded-[2px] bg-[#050404] border border-aisle">
          <Image
            src={SHOT}
            alt="A SyncTogether room: the film in the middle, chat and who's in the room beside it, the controls under it."
            fill
            priority
            sizes="(min-width: 1024px) 580px, 92vw"
            className="object-cover"
          />
        </div>
      </div>

      {/* The invite, tucked against the screen */}
      {/* Phones follow WebMobile: the ticket spans the width so its clamped type still fits. */}
      <div className="hero-ticket-lift absolute left-[6.5%] w-[93.5%] sm:left-[34.5%] sm:w-[69%] top-[68.2%]">
      <div className="hero-ticket">
        <Ticket
          stubClassName="w-[30%]"
          stub={
            <span className="font-[family-name:var(--font-jetbrains-mono)] text-[clamp(13px,3.1cqw,18px)] font-semibold tracking-[0.08em]">
              K7Q2ZP
            </span>
          }
        >
          <p className="font-[family-name:var(--font-jetbrains-mono)] text-[clamp(9px,1.9cqw,11px)] tracking-[0.14em] text-gray-600">
            ADMIT 8 · TONIGHT
          </p>
          <p className="mt-1.5 font-[family-name:var(--font-space-grotesk)] text-[clamp(18px,4.83cqw,28px)] font-extrabold tracking-[-0.035em] leading-[0.98]">
            Friday Horror Club
          </p>
          <p className="mt-2 text-[clamp(11px,2.41cqw,14px)] text-[#5A4F44] truncate">synctogether.app/join/K7Q2ZP</p>
        </Ticket>
      </div>
      </div>

      {/* The stamp. Deliberately not "no tracking": product analytics are on by
          default with an opt-out (see /privacy), so the claim is about ads. */}
      <div className="hero-stamp-lift absolute right-[1.7%] -top-[6.8%] w-[19%] aspect-square">
      <div
        className="hero-stamp absolute inset-0 rounded-full border-[3px] border-signal text-signal flex flex-col items-center justify-center gap-0.5 leading-none"
        aria-label="Free. No ads, no ad trackers."
      >
        <span className="font-[family-name:var(--font-jetbrains-mono)] text-[clamp(7px,1.72cqw,10px)] tracking-[0.14em]">FREE</span>
        <span className="font-[family-name:var(--font-space-grotesk)] font-extrabold text-[clamp(13px,4.14cqw,24px)] whitespace-nowrap">NO ADS</span>
        <span className="font-[family-name:var(--font-jetbrains-mono)] text-[clamp(6px,1.4cqw,8px)] tracking-[0.1em] whitespace-nowrap">NO AD TRACKERS</span>
      </div>
      </div>
    </div>
  );
}
