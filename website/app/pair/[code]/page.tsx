import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { normalizeRoomCode } from "@/lib/rewards";
import { SITE_CONFIG } from "@/lib/constants";
import { JoinLauncher } from "../../join/[code]/JoinLauncher";

/**
 * What a pairing invite carries.
 *
 * `synctogether://pair/<code>` does not linkify in a chat and is a dead end for
 * the person it is for - who, for a long-distance couple, very often has not
 * installed the app yet. This https route hands off to the app when there is one
 * and sells it when there is not, exactly as /join does for a room.
 *
 * It says nothing about who sent it. A code is a capability: confirming publicly
 * that one is live, or naming its sender, would turn a shared link into a way to
 * look people up. The app shows the sender once the code is opened inside it.
 */
export async function generateMetadata({
  params,
}: {
  params: Promise<{ code: string }>;
}): Promise<Metadata> {
  const { code } = await params;
  const normalized = normalizeRoomCode(code);
  const title = "Someone wants to pair with you";
  const description =
    "A private room that is always yours, date nights across time zones, and a shared watchlist. Open the invite in SyncTogether.";
  return {
    title,
    description,
    robots: { index: false, follow: false },
    openGraph: {
      title,
      description,
      url: `${SITE_CONFIG.url}/pair/${normalized ?? ""}`,
      type: "website",
      images: [{ url: "/og-image.png", width: 1200, height: 630, alt: "SyncTogether" }],
    },
    twitter: {
      card: "summary_large_image",
      title,
      description,
      images: ["/og-image.png"],
    },
  };
}

export default async function PairPage({
  params,
}: {
  params: Promise<{ code: string }>;
}) {
  const { code } = await params;
  const normalized = normalizeRoomCode(code);
  if (!normalized) notFound();

  return (
    <div className="relative px-4 sm:px-6 lg:px-8 max-w-[1152px] min-[2000px]:max-w-[1600px] mx-auto min-h-[calc(100svh-76px)] flex flex-col">
      <div className="flex-1 flex items-center py-10 md:py-16">
        <JoinLauncher
          code={normalized}
          kind="pair"
          heading={
            <div className="flex flex-col gap-8">
              <p className="font-[family-name:var(--font-jetbrains-mono)] text-xs tracking-[0.16em] uppercase text-beam-500">
                <span className="text-gray-500">Box office · </span>
                For two
              </p>
              <h1 className="font-[family-name:var(--font-space-grotesk)] font-extrabold text-[clamp(56px,7.4vw,5.6rem)] leading-[0.9] tracking-[-0.045em] text-white">
                Someone
                <br />
                wants you
                <br />
                in their room.
              </h1>
            </div>
          }
        />
      </div>

      <p className="h-[72px] shrink-0 flex items-center gap-1.5 border-t border-aisle text-sm text-gray-500">
        New here?
        <Link href="/" className="text-white font-semibold underline underline-offset-[6px] decoration-[#5A4F44] hover:decoration-beam-500 transition-colors">
          What is {SITE_CONFIG.name}?
        </Link>
      </p>
    </div>
  );
}
