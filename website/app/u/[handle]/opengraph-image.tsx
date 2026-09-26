import { ImageResponse } from "next/og";
import { OgTicket } from "@/lib/og-ticket";
import { getProfileCard } from "@/lib/rewards";

export const size = { width: 1200, height: 630 };
export const contentType = "image/png";
export const alt = "SyncTogether profile";

export default async function Image({ params }: { params: Promise<{ handle: string }> }) {
  const { handle } = await params;
  const card = await getProfileCard(handle);

  return new ImageResponse(
    (
      <OgTicket
        eyebrow="Season pass"
        title={card?.name ?? "A watcher"}
        detail={card ? `@${card.handle}` : "Watching together on SyncTogether"}
        facts={
          card
            ? [`${card.streak}-night run`, `${card.hours}h together`, `${card.badges.length} stamps`]
            : undefined
        }
        stub={card ? "PATRON" : "ADMIT 1"}
      />
    ),
    size,
  );
}
