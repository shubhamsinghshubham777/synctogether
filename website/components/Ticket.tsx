import React from "react";

interface TicketProps {
  /** The ticket body: eyebrow, title, detail line. */
  children: React.ReactNode;
  /** The tear-off stub: the room code, usually. */
  stub: React.ReactNode;
  /** Paper is for what is live or shared; dark sits quietly on the booth. */
  paper?: boolean;
  /** Plays the one-shot "printed" entrance. */
  animate?: boolean;
  className?: string;
  /** Stub width; boards size it per use (120px on the hero, 150px on /join). */
  stubClassName?: string;
}

/**
 * The Booth Light signature object, mirroring the app's `PTTicket`
 * (lib/ui/booth.dart): a body and a stub split by a perforation, with a notch
 * bitten out of each short edge at mid-height. The notches are a CSS mask, so the ticket
 * sits on any background without painting fake holes.
 *
 * The entrance is CSS-only and runs once (`ticket-print` in globals.css);
 * reduced motion collapses it via the global rule.
 */
export function Ticket({
  children,
  stub,
  paper = true,
  animate = false,
  className = "",
  stubClassName = "w-28 sm:w-36",
}: TicketProps) {
  return (
    <div
      className={`ticket flex text-left ${
        paper ? "bg-screen text-booth" : "bg-seat text-white ring-1 ring-inset ring-rail"
      } ${animate ? "ticket-print" : ""} ${className}`}
    >
      <div className="flex-1 min-w-0 px-6 py-5 sm:px-[30px] sm:py-[22px]">{children}</div>
      <div
        className={`ticket-stub flex ${stubClassName} shrink-0 items-center justify-center border-l-2 border-dashed ${
          paper ? "border-[#B8AB98]" : "border-rail"
        }`}
      >
        {stub}
      </div>
    </div>
  );
}
