import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { normalizeRoomCode } from "@/lib/rewards";
import { SITE_CONFIG } from "@/lib/constants";
import { JoinLauncher } from "./JoinLauncher";

/**
 * The page that makes an invite shareable.
 *
 * `synctogether://join/<code>` does not linkify on X, Instagram, WhatsApp or
 * Discord, shows no preview card, and is a dead end for anybody who has not
 * installed the app - which is almost everybody receiving a first invite. This
 * https route is what a share actually carries; it hands off to the app when
 * one is installed, and to the download page when one is not.
 *
 * Deliberately says nothing about the room itself. A code is a capability, and
 * confirming publicly that one is live would turn a shared link into a way to
 * enumerate rooms.
 */
export async function generateMetadata({
  params,
}: {
  params: Promise<{ code: string }>;
}): Promise<Metadata> {
  const { code } = await params;
  const normalized = normalizeRoomCode(code);
  const title = normalized
    ? `Join watch party ${normalized}`
    : "Join a watch party";
  const description =
    "Someone wants to watch something with you, in sync. Open the invite in SyncTogether.";
  return {
    title,
    description,
    robots: { index: false, follow: false },
    openGraph: {
      title,
      description,
      url: `${SITE_CONFIG.url}/join/${normalized ?? ""}`,
      type: "website",
    },
    twitter: { card: "summary_large_image", title, description },
  };
}

export default async function JoinPage({
  params,
}: {
  params: Promise<{ code: string }>;
}) {
  const { code } = await params;
  const normalized = normalizeRoomCode(code);
  if (!normalized) notFound();

  return (
    <div className="relative px-4 sm:px-6 lg:px-8 max-w-[1152px] mx-auto min-h-[calc(100svh-76px)] flex flex-col">
      <div className="flex-1 flex items-center py-10 md:py-16">
      <JoinLauncher
        code={normalized}
        heading={
          <div className="flex flex-col gap-8">
            <p className="font-[family-name:var(--font-jetbrains-mono)] text-xs tracking-[0.16em] uppercase text-beam-500">
              <span className="text-gray-500">Box office · </span>
              Will call
            </p>
            <h1 className="font-[family-name:var(--font-space-grotesk)] font-extrabold text-[clamp(64px,8vw,6rem)] leading-[0.9] tracking-[-0.045em] text-white">
              You&apos;re
              <br />
              invited.
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
