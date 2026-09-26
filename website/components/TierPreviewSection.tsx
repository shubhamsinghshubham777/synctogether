"use client";

import Link from "next/link";
import { Loader2 } from "lucide-react";
import { usePricing } from "@/lib/usePricing";
import { PRICING_TIERS } from "@/lib/constants";

const mono = "font-[family-name:var(--font-jetbrains-mono)]";
const display = "font-[family-name:var(--font-space-grotesk)]";

function hours(min: number) {
  return min <= 60 ? `${min} min` : `${min / 60} h`;
}

function avLabel(av: string) {
  if (/video/i.test(av)) return "Voice + video";
  if (/voice/i.test(av)) return "Voice";
  return "×";
}

type Seat = {
  key: "guest" | "free" | "premium";
  name: string;
  note: string;
  price: React.ReactNode;
  tone: "plain" | "beam" | "brass";
};

function SeatCard({ seat }: { seat: Seat }) {
  const t = PRICING_TIERS[seat.key].limits;
  const border =
    seat.tone === "beam"
      ? "border-beam-500 border-t-beam-500"
      : seat.tone === "brass"
        ? "border-[#6B5A2E] border-t-brass"
        : "border-rail border-t-rail";
  const accent = seat.tone === "beam" ? "text-beam-500" : seat.tone === "brass" ? "text-brass" : "text-gray-500";
  const rows: [string, string][] = [
    ["People", String(t.members)],
    ["Show", seat.key === "premium" ? `up to ${hours(t.totalSessionMinutes)}` : hours(t.sessionMinutes)],
    ["Voice", avLabel(t.av)],
  ];
  return (
    <div className={`rounded-md border border-t-[3px] bg-seat p-[26px] flex flex-col gap-4 ${border}`}>
      <div className="flex items-baseline justify-between gap-3">
        <span
          className={`${display} text-[30px] font-extrabold tracking-[-0.03em] leading-none ${
            seat.tone === "brass" ? "text-brass" : "text-screen"
          }`}
        >
          {seat.name}
        </span>
        <span className={`${mono} text-[11px] tracking-[0.14em] uppercase ${accent}`}>{seat.note}</span>
      </div>
      <p className={`${display} text-[40px] font-extrabold tracking-[-0.04em] leading-none text-screen`}>{seat.price}</p>
      <dl>
        {rows.map(([k, v]) => (
          <div key={k} className={`${mono} flex items-center justify-between py-[9px] border-t border-aisle text-[13px] leading-tight`}>
            <dt className="uppercase text-gray-500">{k}</dt>
            <dd className="text-screen">{v}</dd>
          </div>
        ))}
      </dl>
    </div>
  );
}

export function TierPreviewSection() {
  const { monthlyFormatted, currencySymbol, isLoading } = usePricing();
  const zero = `${currencySymbol || "$"}0`;

  const seats: Seat[] = [
    { key: "guest", name: "Guest", note: "No account", price: zero, tone: "plain" },
    { key: "free", name: "Free", note: "Sign in", price: zero, tone: "beam" },
    {
      key: "premium",
      name: "Patron",
      note: "Per month",
      tone: "brass",
      price: isLoading ? (
        <Loader2 className="w-6 h-6 my-1.5 animate-spin text-brass" aria-label="Loading price" />
      ) : (
        <span id="features-premium-price">{monthlyFormatted}</span>
      ),
    },
  ];

  return (
    <section id="tiers" className="relative pt-4 pb-12">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 grid lg:grid-cols-[1fr_2.2fr] gap-10 lg:gap-14 items-start">
        <div className="flex flex-col gap-[18px]">
          <p className={`${mono} text-xs tracking-[0.16em] text-beam-500 uppercase`}>
            <span className="text-[#5A4F44]">05 · </span>Seats
          </p>
          <h2 className={`${display} text-4xl sm:text-[44px] font-extrabold tracking-[-0.04em] leading-[0.92] text-screen`}>
            Free for most nights. Patron for the big ones.
          </h2>
          <Link
            href="/pricing"
            className="inline-block text-[15px] font-semibold text-screen underline underline-offset-[6px] decoration-[#5A4F44] hover:decoration-beam-500 transition-colors"
          >
            Compare every seat
          </Link>
        </div>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          {seats.map((s) => (
            <SeatCard key={s.key} seat={s} />
          ))}
        </div>
      </div>
    </section>
  );
}
