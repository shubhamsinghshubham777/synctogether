import type { Metadata } from "next";
import Link from "next/link";
import { PageHead, display, mono } from "@/components/PageHead";

export const metadata: Metadata = {
  title: "Guides · Watching together, from wherever you are",
  description:
    "Practical guides for watching films together at a distance: date night ideas, time zones, and keeping everyone on the same frame.",
  alternates: { canonical: "/guides" },
};

const GUIDES = [
  {
    href: "/guides/long-distance-date-night-ideas",
    tag: "24 ideas",
    title: "Long-distance date night ideas that work over video",
    body: "Cooking, games, films, walks and more, with what you need for each one.",
  },
  {
    href: "/guides/watch-a-movie-together-across-time-zones",
    tag: "How to",
    title: "How to watch a movie together across time zones",
    body: "Pick a time, match the file, keep play and pause aligned, and talk during the film.",
  },
];

export default function GuidesPage() {
  return (
    <div className="relative pt-8 md:pt-14 pb-16 px-4 sm:px-6 lg:px-8 max-w-7xl min-[2000px]:max-w-[1920px] mx-auto space-y-10">
      <PageHead
        gridClassName="lg:grid-cols-[1.4fr_1fr] items-end"
        titleClassName="text-[clamp(2.5rem,6vw,5rem)]"
        eyebrow="Field notes"
        title={
          <>
            Movie night,
            <br />
            at a distance.
          </>
        }
        aside={
          <p className="text-base sm:text-[17px] leading-[1.55] text-gray-400 max-w-[360px] lg:ml-auto">
            Short, practical reads on watching together when you are not in the same room.
          </p>
        }
      />

      <ul className="grid md:grid-cols-2 gap-4">
        {GUIDES.map((g) => (
          <li key={g.href}>
            <Link
              href={g.href}
              className="group flex h-full flex-col gap-4 rounded-md border border-rail bg-seat p-7 transition-colors hover:border-beam-500/60"
            >
              <p className={`${mono} text-[11px] tracking-[0.16em] uppercase text-beam-500`}>{g.tag}</p>
              <h2 className={`${display} text-2xl sm:text-[32px] font-extrabold tracking-[-0.03em] leading-[1.02] text-white`}>
                {g.title}
              </h2>
              <p className="text-[16px] leading-[1.6] text-gray-400">{g.body}</p>
              <span className={`${mono} mt-auto text-xs tracking-[0.12em] uppercase text-gray-400 group-hover:text-white`}>
                Read the guide →
              </span>
            </Link>
          </li>
        ))}
      </ul>
    </div>
  );
}
