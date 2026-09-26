import { gradientForSeed } from "@/lib/rewards";

/** Frames are a solid ring in a Booth colour - no gradients in the booth. */
const FRAME_COLORS: Record<string, string> = {
  ember: "#FF6A4D",
  halo: "#6FD6C4",
  pulse: "#FFB23F",
  aurora: "#6FD6C4",
  laurel: "#E8C877",
  aurum: "#E8C877",
};

/**
 * An avatar for a public page.
 *
 * Takes a hashed `seed` rather than a user id, because these pages are indexed,
 * cached and reshared - an account identifier on one would outlive any later
 * change of mind. Someone who never opted into a public profile has no name to
 * show, so they are a flat colour picked from the seed and nothing else.
 */
export function PublicAvatar({
  seed,
  name,
  avatar,
  frame,
  size = 48,
}: {
  seed: string;
  name?: string | null;
  avatar?: string | null;
  frame?: string | null;
  size?: number;
}) {
  const [from] = gradientForSeed(seed);
  const letter = name ? name.trim().charAt(0).toUpperCase() : "";
  const frameColor = frame ? FRAME_COLORS[frame] : undefined;

  const inner = (
    <div
      className="rounded-full flex items-center justify-center bg-cover bg-center shrink-0"
      style={{
        width: size,
        height: size,
        background: avatar
          ? `url(${avatar}) center/cover`
          : from,
        fontSize: size * 0.38,
      }}
      aria-hidden={!name}
    >
      {!avatar && (
        <span className="font-extrabold text-white font-[family-name:var(--font-space-grotesk)]">{letter}</span>
      )}
    </div>
  );

  if (!frameColor) return inner;

  return (
    <div
      className="rounded-full shrink-0"
      style={{
        padding: Math.max(2, size * 0.055),
        background: frameColor,
      }}
    >
      <div className="rounded-full" style={{ padding: Math.max(1, size * 0.035), background: "#121010" }}>
        {inner}
      </div>
    </div>
  );
}
