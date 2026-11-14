import type { Metadata } from "next";
import Link from "next/link";
import { PageHead, mono, display } from "@/components/PageHead";
import { AndroidSeat } from "@/components/AndroidSeat";
import { androidTestUrl, getSeatCounts } from "@/lib/android-testers-server";

// The count moves slowly; a minute of staleness is invisible and keeps the page static-fast.
export const revalidate = 60;

export const metadata: Metadata = {
  title: "SyncTogether on Android: save a seat in the test",
  description:
    "SyncTogether is on iPhone, iPad, Mac and Windows. Android is in testing: put your name down and you'll get the Google Play link when it opens.",
};

const STEPS = [
  { k: "01 · Now", t: "Put your name down", b: "The Gmail address on your Android phone. That's the whole form." },
  { k: "02 · When the seats fill", t: "We open the test", b: "You get one email with a Google Play link. Expect a few weeks." },
  {
    k: "03 · For 14 days",
    t: "Keep it installed",
    b: "Watch something with someone, tell us what breaks. Then Google lets it out for everyone.",
  },
];

export default async function AndroidPage() {
  const counts = await getSeatCounts();
  const playUrl = androidTestUrl();

  return (
    <div className="relative pt-8 md:pt-14 pb-12 px-4 sm:px-6 lg:px-8 max-w-7xl min-[2000px]:max-w-[1920px] mx-auto space-y-10">
      <PageHead
        titleClassName="text-[clamp(2.75rem,7vw,5.5rem)]"
        gridClassName="lg:grid-cols-[1fr_520px] items-start"
        eyebrow="Android · Early access"
        title={
          <>
            Android is next.
            <br />
            <span className="text-[#5A4F44]">Save a seat.</span>
          </>
        }
        lede="SyncTogether is live on iPhone, iPad, Mac and Windows. Before Google Play lists a new app, a small group has to test it for two weeks. Be in that group and you're watching first."
        aside={<AndroidSeat counts={counts} playUrl={playUrl} />}
      />
      <p className="text-sm text-gray-500">
        On a computer or iPhone now?{" "}
        <Link href="/download" className="font-semibold text-white underline underline-offset-[6px] decoration-[#5A4F44] hover:decoration-beam-500">
          Get it from the store
        </Link>
      </p>
      <section className="grid md:grid-cols-3 gap-8 md:gap-10">
        {STEPS.map(({ k, t, b }) => (
          <div key={k} className="border-t border-rail pt-[18px] space-y-2.5">
            <p className={`${mono} text-[11px] tracking-[0.14em] uppercase text-gray-500`}>{k}</p>
            <p className={`${display} text-2xl font-extrabold tracking-[-0.03em] leading-[1.05] text-white`}>{t}</p>
            <p className="text-[15px] text-gray-400 leading-[1.55]">{b}</p>
          </div>
        ))}
      </section>
    </div>
  );
}
