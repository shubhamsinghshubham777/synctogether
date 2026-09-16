import { ImageResponse } from "next/og";
import { getProfileCard } from "@/lib/rewards";

export const size = { width: 1200, height: 630 };
export const contentType = "image/png";
export const alt = "SyncTogether profile";

export default async function Image({ params }: { params: Promise<{ handle: string }> }) {
  const { handle } = await params;
  const card = await getProfileCard(handle);

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
        <div style={{ display: "flex", marginTop: 24, fontSize: 72, fontWeight: 800 }}>
          {card?.name ?? "A watcher"}
        </div>
        {card && (
          <>
            <div style={{ display: "flex", marginTop: 12, fontSize: 32, color: "#8C86A8" }}>
              @{card.handle}
            </div>
            <div style={{ display: "flex", gap: 56, marginTop: 54, fontSize: 34 }}>
              <div style={{ display: "flex", color: "#FB923C" }}>
                {card.streak}-day streak
              </div>
              <div style={{ display: "flex", color: "#D7CDF5" }}>{card.hours}h together</div>
              <div style={{ display: "flex", color: "#D7CDF5" }}>
                {card.badges.length} badges
              </div>
            </div>
          </>
        )}
      </div>
    ),
    size,
  );
}
