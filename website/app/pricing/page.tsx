import type { Metadata } from "next";
import { PricingTable } from "@/components/PricingTable";
import { TierConfigurator } from "@/components/pricing/TierConfigurator";
import { Reveal } from "@/components/motion/Reveal";
import { PaddleTransactionCheckout } from "@/components/PaddleTransactionCheckout";
import { PageHead, display, mono } from "@/components/PageHead";

export const metadata: Metadata = {
  title: "Pricing & Plans · SyncTogether Premium",
  description:
    "Upgrade to SyncTogether Premium for 20 persistent rooms, 16 members, 24-hour sessions, video facecams, and extended emoji reactions.",
};

export default function PricingPage() {
  return (
    <div className="relative pt-8 pb-12 md:pt-12 md:pb-12 px-4 sm:px-6 lg:px-8 max-w-7xl mx-auto space-y-10">
      {/* Resumes payment when Paddle's default payment link sends a customer
          here with ?_ptxn=txn_... Renders nothing otherwise. */}
      <PaddleTransactionCheckout />

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
        lede="Free rooms hold 8 people for 4 hours. Patron, our Premium plan, is for the whole group, the all-day marathon, and the room that never closes."
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
        <TierConfigurator />
      </div>

      <Reveal>
        <PricingTable />
      </Reveal>

    </div>
  );
}
