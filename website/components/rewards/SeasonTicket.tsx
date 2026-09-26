import { seasonRankLabel } from "@/lib/rewards";
import { display, mono } from "@/components/booth/Booth";

const MONTHS = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];
const ORDINAL: Record<number, string> = { 1: "1st place", 2: "2nd place", 3: "3rd place" };

/** 'YYYY-MM' -> { eyebrow: "AUG 2026", closed: "Closed 1 Sept 2026" }, or nulls on a bad id. */
function seasonParts(season: string) {
  const [y, m] = season.split("-").map((s) => Number.parseInt(s, 10));
  if (!Number.isFinite(y) || !Number.isFinite(m) || m < 1 || m > 12) return { eyebrow: season, closed: null };
  const next = new Date(Date.UTC(y, m, 1));
  const closed = next.toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric", timeZone: "UTC" });
  return { eyebrow: `${MONTHS[m - 1]} ${y}`, closed: `Closed ${closed}` };
}

/**
 * A season placing as a small paper ticket. Hand-built rather than `Ticket`
 * because that one's stub and padding are sized for a hero, not a keepsake row.
 */
export function SeasonTicket({ season, rank }: { season: string; rank: number }) {
  const { eyebrow, closed } = seasonParts(season);
  return (
    <div className="ticket flex bg-screen text-booth w-[270px] max-w-full" title={seasonRankLabel(rank)}>
      <div className="flex-1 min-w-0 px-6 py-4">
        <p className={`${mono} text-[9px] tracking-[0.16em] text-gray-600`}>{eyebrow} · GLOBAL</p>
        <p className={`${display} mt-0.5 text-xl font-extrabold tracking-[-0.03em] leading-tight`}>
          {ORDINAL[rank] ?? `No. ${rank}`}
        </p>
        {closed && <p className="text-xs text-[#5A4F44]">{closed}</p>}
      </div>
      <div className="flex w-[72px] shrink-0 items-center justify-center border-l-2 border-dashed border-[#B8AB98]">
        <span className={`${mono} text-sm font-semibold`}>No. {rank}</span>
      </div>
    </div>
  );
}
