import { mono } from "@/components/booth/Booth";

/** Grade hairlines in Booth colours: bronze, Screen-ish silver, Brass gold, Beam for secrets. */
const GRADE_RING: Record<string, string> = {
  bronze: "ring-signal/50",
  silver: "ring-screen/40",
  gold: "ring-brass/70",
  secret: "ring-beam-500/70",
};

/**
 * A badge as a tile with a caption under it, like the app's `BadgeTile`.
 * The site does not ship the badge renders, so the tile carries the badge's
 * initial on a Seat square; the grade reads from the hairline.
 */
export function BadgeTile({ title, grade }: { title: string; grade: string }) {
  const ring = GRADE_RING[grade] ?? GRADE_RING.bronze;
  return (
    <figure className="w-[76px] flex flex-col items-center gap-2" title={`${title} · ${grade}`}>
      <div
        className={`h-14 w-14 rounded-md bg-seat ring-1 ring-inset ${ring} flex items-center justify-center`}
        aria-hidden
      >
        <span className={`${mono} text-lg font-semibold text-gray-300`}>
          {title.trim().charAt(0).toUpperCase()}
        </span>
      </div>
      <figcaption className="text-xs text-gray-300 text-center leading-tight">{title}</figcaption>
    </figure>
  );
}
