import { gradientForSeed } from "@/lib/rewards";

const FRAME_GRADIENTS: Record<string, [string, string]> = {
  ember: ["#FBBF24", "#F97316"],
  halo: ["#38BDF8", "#818CF8"],
  pulse: ["#C084FC", "#8B5CF6"],
  aurora: ["#4ADE80", "#A855F7"],
  laurel: ["#E9D5A1", "#B08D57"],
  aurum: ["#FBBF24", "#D97706"],
};

/**
 * An avatar for a public page.
 *
 * Takes a hashed `seed` rather than a user id, because these pages are indexed,
 * cached and reshared - an account identifier on one would outlive any later
 * change of mind. Someone who never opted into a public profile has no name to
 * show, so they are a gradient and nothing else.
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
  const [from, to] = gradientForSeed(seed);
  const letter = name ? name.trim().charAt(0).toUpperCase() : "";
  const frameColors = frame ? FRAME_GRADIENTS[frame] : undefined;

  const inner = (
    <div
      className="rounded-full flex items-center justify-center bg-cover bg-center shrink-0"
      style={{
        width: size,
        height: size,
        background: avatar
          ? `url(${avatar}) center/cover`
          : `linear-gradient(135deg, ${from}, ${to})`,
        fontSize: size * 0.38,
      }}
      aria-hidden={!name}
    >
      {!avatar && <span className="font-semibold text-white">{letter}</span>}
    </div>
  );

  if (!frameColors) return inner;

  return (
    <div
      className="rounded-full shrink-0"
      style={{
        padding: Math.max(2, size * 0.055),
        background: `linear-gradient(135deg, ${frameColors[0]}, ${frameColors[1]})`,
        boxShadow: `0 0 ${size * 0.22}px ${frameColors[1]}59`,
      }}
    >
      <div className="rounded-full" style={{ padding: Math.max(1, size * 0.035), background: "#14101F" }}>
        {inner}
      </div>
    </div>
  );
}
