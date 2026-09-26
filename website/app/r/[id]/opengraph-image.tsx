import { ImageResponse } from "next/og";
import { OgTicket } from "@/lib/og-ticket";
import { displayNameFor, formatWatchTime, getRecap } from "@/lib/rewards";

export const size = { width: 1200, height: 630 };
export const contentType = "image/png";
export const alt = "SyncTogether watch party recap";

/**
 * The card a shared recap shows in a feed.
 *
 * Rendered server-side rather than captured from the app: a `RepaintBoundary`
 * grab would come out at whatever DPI the sharer's monitor happens to be, and
 * `Clipboard.setData` on desktop Flutter is text-only anyway. Doing it here also
 * means every share looks identical wherever it lands.
 */
export default async function Image({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const recap = await getRecap(id);
  const others = recap ? recap.peak_members - 1 : 0;

  const facts = recap
    ? [
        `${recap.reactions} reactions`,
        `${recap.messages} messages`,
        ...(recap.superlatives[0]
          ? [`${displayNameFor(recap.superlatives[0].person)} took the crown`]
          : []),
      ]
    : undefined;

  return new ImageResponse(
    (
      <OgTicket
        eyebrow="Admit all · last night"
        title={recap?.room_name ?? "A watch party"}
        detail={
          recap
            ? `${formatWatchTime(recap.seconds)} in sync with ${others} ${others === 1 ? "other" : "others"}`
            : "Watch together, in sync"
        }
        facts={facts}
        stub="RECAP"
      />
    ),
    size,
  );
}
