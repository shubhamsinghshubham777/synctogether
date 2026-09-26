import type { Metadata } from "next";
import { ChangelogNotes, cleanReleaseBody } from "@/components/ChangelogNotes";
import { getAllReleases, type GitHubAsset } from "@/lib/github";
import { PageHead, display, mono } from "@/components/PageHead";

export const metadata: Metadata = {
  title: "Changelog & Release Notes",
  description: "Explore the latest updates, features, improvements, and fixes in SyncTogether releases.",
};

export const revalidate = 3600; // ISR hourly

export default async function ChangelogPage() {
  const releases = await getAllReleases();

  const fallbackReleases = [
    {
      id: 1,
      tag_name: "v0.11.0",
      name: "SyncTogether 0.11.0: Facecams & Persistent Rooms",
      published_at: "2026-08-11T12:00:00Z",
      body: `### New Features
- **Video & Voice Facecams**: Real-time Video and low-latency Voice facecams integrated directly into rooms.
- **Persistent Rooms**: Premium hosts can now create named, permanent rooms that never expire.
- **Animated Lottie Reactions**: 24 expressive Google Noto animated emoji reactions floating dynamically over video.
- **Extended Sessions**: Free rooms support continuous 4-hour watch sessions, resuming local file timestamps seamlessly.

### Performance & Engine
- Upgraded video playback engine with improved hardware decoding on macOS & Windows.
- Clock-skew resistant server time synchronization for synchronized, drift-corrected play/pause events.`,
      html_url: "https://github.com/shubhamsinghshubham777/synctogether/releases",
    },
    {
      id: 2,
      tag_name: "v0.10.0",
      name: "SyncTogether 0.10.0: Redesigned Violet Glass Interface",
      published_at: "2026-08-04T10:00:00Z",
      body: `### Highlights
- Complete design overhaul featuring violet glassmorphism aesthetics and custom typography (Space Grotesk, Outfit, JetBrains Mono).
- YouTube playback integration with shared seekbar synchronization.
- Real-time room chat with typing presence and per-user avatar styling.`,
      html_url: "https://github.com/shubhamsinghshubham777/synctogether/releases",
    },
  ];

  const displayReleases = releases.length > 0 ? releases : fallbackReleases;

  return (
    <div className="relative pt-8 md:pt-14 pb-12 px-4 sm:px-6 lg:px-8 max-w-7xl mx-auto">
      <PageHead
        titleClassName="text-[clamp(2.5rem,6vw,5rem)]"
        gridClassName="lg:grid-cols-[1.4fr_1fr] items-end"
        eyebrow="Reel log"
        title={
          <>
            What changed
            <br />
            in the booth.
          </>
        }
        aside={
          <p className="text-base sm:text-[17px] leading-[1.55] text-gray-400 max-w-[360px] lg:ml-auto">
            Every release, newest first. The app updates itself. This is just the receipt.
          </p>
        }
      />

      <ol className="space-y-0">
        {displayReleases.map((rel, idx) => {
          const releaseDate = new Date(rel.published_at).toLocaleDateString(
            "en-GB",
            { year: "numeric", month: "short", day: "numeric" }
          );
          const title = (rel.name || rel.tag_name).replace(/_\d+$/, "");
          const latest = idx === 0;
          const tag = rel.tag_name.replace(/_\d+$/, "");
          const assets: GitHubAsset[] = "assets" in rel ? (rel.assets as GitHubAsset[]) : [];
          const mac = latest ? assets.find((a) => /\.dmg$/i.test(a.name)) : undefined;
          const win = latest ? assets.find((a) => /\.exe$/i.test(a.name)) : undefined;

          return (
            <li
              key={rel.id}
              className="grid md:grid-cols-[13rem_1fr] lg:grid-cols-[260px_1fr] gap-6 md:gap-12 lg:gap-[72px] py-9 border-b border-aisle"
            >
              {/* The slate: tag, date, source */}
              <div className="md:sticky md:top-28 self-start space-y-3">
                {latest && (
                  <p className={`${mono} flex items-center gap-2 text-[11px] tracking-[0.16em] uppercase text-beam-500`}>
                    <span className="sync-dot" aria-hidden="true" />
                    Now showing
                  </p>
                )}
                <p
                  className={`${display} text-4xl lg:text-5xl font-extrabold tracking-[-0.045em] leading-none break-words ${
                    latest ? "text-white" : "text-gray-500"
                  }`}
                >
                  {tag}
                </p>
                <p className={`${mono} text-xs tracking-[0.1em] uppercase text-gray-500`}>
                  <time dateTime={rel.published_at}>{releaseDate}</time>
                </p>
                <a
                  href={rel.html_url}
                  target="_blank"
                  rel="noopener noreferrer"
                  className={`${mono} inline-block text-[11px] tracking-[0.12em] uppercase text-gray-400 hover:text-white underline underline-offset-4 decoration-rail hover:decoration-beam-500 transition-colors`}
                >
                  On GitHub ↗
                </a>
              </div>

              <div className="min-w-0 space-y-6">
                <h2 className={title === tag ? "sr-only" : `${display} text-2xl sm:text-3xl font-extrabold tracking-[-0.03em] leading-tight ${latest ? "text-white" : "text-gray-400"}`}>
                  {title}
                </h2>
                <ChangelogNotes content={cleanReleaseBody(rel.body)} muted={!latest} />
                {(mac || win) && (
                  <div className="flex flex-wrap gap-3">
                    {[mac && { a: mac, label: "macOS .dmg" }, win && { a: win, label: "Windows .exe" }]
                      .filter((d): d is { a: NonNullable<typeof mac>; label: string } => !!d)
                      .map(({ a, label }) => (
                        <a
                          key={a.id}
                          href={a.browser_download_url}
                          className="inline-flex items-center gap-2 rounded-[4px] border border-rail px-4 py-2 text-sm font-semibold text-white hover:border-beam-500 transition-colors"
                        >
                          <svg aria-hidden="true" viewBox="0 0 16 16" className="w-3.5 h-3.5" fill="none" stroke="currentColor" strokeWidth="1.6">
                            <path d="M8 2v8m0 0L4.5 6.5M8 10l3.5-3.5M3 13h10" />
                          </svg>
                          {label}
                        </a>
                      ))}
                  </div>
                )}
              </div>
            </li>
          );
        })}
      </ol>
    </div>
  );
}
