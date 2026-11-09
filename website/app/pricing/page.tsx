import type { Metadata } from "next";
import { PricingTable } from "@/components/PricingTable";
import { TierConfigurator } from "@/components/pricing/TierConfigurator";
import { Reveal } from "@/components/motion/Reveal";
import { PageHead, display, mono } from "@/components/PageHead";
import { getPatronPrices } from "@/lib/store-prices";

export const metadata: Metadata = {
  title: "Pricing & Plans · SyncTogether Premium",
  description:
    "Upgrade to SyncTogether Premium for 20 persistent rooms, 16 members, 24-hour sessions, video facecams, and extended emoji reactions. Pairing and Our Room for two are free.",
};

export default async function PricingPage() {
  const { prices } = await getPatronPrices();
  return (
    <div className="relative pt-8 pb-12 md:pt-12 md:pb-12 px-4 sm:px-6 lg:px-8 max-w-7xl min-[2000px]:max-w-[1920px] mx-auto space-y-10">

      <PageHead
        eyebrow="Box office"
        titleClassName="text-[clamp(46px,6vw,4.5rem)]"
        title={
          <span className="block">
            Free for most nights.
            <br />
            <span className="text-brass">Patron seats</span> for the big ones.
          </span>
        }
        lede="Free rooms hold 8 people for 4 hours. Patron, our Premium plan, is for the whole group, the all-day marathon, and the room you can keep and reopen. Two of you? Pairing and Our Room are free."
        aside={
          <dl className={`${mono} grid grid-cols-3 border border-rail rounded-md divide-x divide-rail text-center`}>
            {[
              ["8", "seats free", "text-white"],
              ["16", "on Patron", "text-brass"],
              ["24h", "longest show", "text-brass"],
            ].map(([v, l, tone]) => (
              <div key={l} className="px-2 py-4 sm:p-[22px]">
                <dt className="sr-only">{l}</dt>
                <dd className={`${display} text-3xl sm:text-[40px] leading-none font-extrabold ${tone}`}>{v}</dd>
                <dd className="mt-1.5 text-[10px] tracking-[0.14em] uppercase text-gray-500">{l}</dd>
              </div>
            ))}
          </dl>
        }
      />

      {/* The phone board leads with the tickets; the configurator is a wide-screen tool. */}
      <div className="hidden md:block">
        <TierConfigurator prices={prices} />
      </div>

      <Reveal>
        <PricingTable prices={prices} />
      </Reveal>

      <Reveal>
        <section className="border border-rail rounded-md p-6 sm:p-8 space-y-3 max-w-3xl">
          <p className={`${mono} text-[11px] tracking-[0.16em] text-signal uppercase`}>For two</p>
          <h2 className={`${display} text-2xl sm:text-3xl font-extrabold tracking-[-0.03em]`}>
            Pairing and Our Room are free.
          </h2>
          <p className="text-[15px] leading-relaxed text-gray-400">
            Any two signed-in accounts can pair and share Our Room, a private room that is always yours. It
            never uses one of your room slots, and the chat carries over between nights. Guests can&apos;t pair.
            If either of you is a Patron, you both get video facecams, can plan date nights, and can see your
            whole history. On Free, you see the last 7 days, and you can export all of it any time.
          </p>
        </section>
      </Reveal>

    </div>
  );
}
