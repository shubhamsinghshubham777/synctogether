import { ImageResponse } from "next/og";
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

  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "center",
          padding: "72px 80px",
          background: "linear-gradient(135deg, #0B0A14 0%, #1A1030 55%, #2A1358 100%)",
          color: "white",
        }}
      >
        <div
          style={{
            display: "flex",
            fontSize: 24,
            letterSpacing: 6,
            textTransform: "uppercase",
            color: "#C9B8FF",
          }}
        >
          SyncTogether
        </div>
        <div
          style={{
            display: "flex",
            marginTop: 22,
            fontSize: recap?.room_name ? 66 : 74,
            fontWeight: 800,
            lineHeight: 1.05,
          }}
        >
          {recap?.room_name ?? "A watch party"}
        </div>
        <div style={{ display: "flex", marginTop: 26, fontSize: 38, color: "#D7CDF5" }}>
          {recap
            ? `${formatWatchTime(recap.seconds)} in sync with ${others} ${
                others === 1 ? "other" : "others"
              }`
            : "Watch together, in sync"}
        </div>
        {recap && (
          <div style={{ display: "flex", gap: 44, marginTop: 52, fontSize: 30 }}>
            <div style={{ display: "flex", color: "#A78BFA" }}>
              {recap.reactions} reactions
            </div>
            <div style={{ display: "flex", color: "#A78BFA" }}>
              {recap.messages} messages
            </div>
            {recap.superlatives[0] && (
              <div style={{ display: "flex", color: "#FBBF24" }}>
                {displayNameFor(recap.superlatives[0].person)} took the crown
              </div>
            )}
          </div>
        )}
      </div>
    ),
    size,
  );
}
