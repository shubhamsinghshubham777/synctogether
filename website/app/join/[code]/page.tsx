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
    <div className="relative py-16 md:py-24 px-4 sm:px-6 lg:px-8 max-w-xl mx-auto space-y-8">
      <div className="glow-blob-purple top-10 left-1/2 -translate-x-1/2 opacity-30" />
      <div className="text-center space-y-3">
        <h1 className="text-3xl sm:text-4xl font-extrabold text-white tracking-tight font-[family-name:var(--font-space-grotesk)]">
          You&apos;re <span className="text-gradient-brand">invited</span>.
        </h1>
        <p className="text-gray-300">
          Someone wants to watch something with you, in sync.
        </p>
      </div>

      <JoinLauncher code={normalized} />

      <p className="text-center text-xs text-gray-500">
        New here?{" "}
        <Link href="/" className="text-[var(--pt-text-accent)] underline underline-offset-4">
          What is {SITE_CONFIG.name}?
        </Link>
      </p>
    </div>
  );
}
