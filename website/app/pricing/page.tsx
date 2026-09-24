import type { Metadata } from "next";
import { PricingTable } from "@/components/PricingTable";
import { TierConfigurator } from "@/components/pricing/TierConfigurator";
import { PersistentRoomsBand } from "@/components/pricing/PersistentRoomsBand";
import { Reveal } from "@/components/motion/Reveal";
import { FAQAccordion } from "@/components/FAQAccordion";
import { PaddleTransactionCheckout } from "@/components/PaddleTransactionCheckout";

export const metadata: Metadata = {
  title: "Pricing & Plans - SyncTogether Premium",
  description:
    "Upgrade to SyncTogether Premium for 20 persistent rooms, 16 members, 24-hour sessions, video facecams, and extended emoji reactions.",
};

export default function PricingPage() {
  const pricingFaqs = [
    {
      q: "Can I try SyncTogether before paying?",
      a: "Yes! Both our Guest and Free tiers are 100% free and fully functional. Free tier includes 4-hour sessions, 8 members, voice chat, and 2.5 GB weekly media streaming."
    },
    {
      q: "What payment methods do you accept?",
      a: "We process payments securely (Credit/Debit Cards, PayPal, Apple Pay, Google Pay, and UPI in India)."
    },
    {
      q: "Can I cancel my subscription anytime?",
      a: "Yes, you can cancel anytime from your Account page. Your premium benefits will remain active until the end of your prepaid billing period without any unexpected charges."
    },
    {
      q: "Do I need an account to subscribe?",
      a: "Yes, you must sign in to an account (Google, Apple, or Email) on the website to purchase Premium. This ensures your purchase links directly to your SyncTogether desktop app identity."
    },
    {
      q: "Does Premium work in the Mac App Store version?",
      a: "Yes. The Mac App Store edition sells Premium through the App Store, and a subscription bought here on the website unlocks it there too. A subscription bought through the App Store is managed and cancelled in your Apple account settings. The Windows app, from this site or the Microsoft Store, supports Premium normally."
    },
    {
      q: "What happens to my rooms if my subscription expires?",
      a: "Nothing is deleted. You keep Premium until the end of the period you paid for. After that, your rooms follow Free tier limits: the next time one is opened it holds 8 people and runs 4-hour sessions, and rooms beyond the Free limits stop staying open indefinitely. Resubscribe and new sessions get Premium limits again."
    }
  ];

  return (
    <div className="relative py-10 md:py-14 px-4 sm:px-6 lg:px-8 max-w-7xl mx-auto space-y-12 md:space-y-14">
      {/* Resumes payment when Paddle's default payment link sends a customer
          here with ?_ptxn=txn_... Renders nothing otherwise. */}
      <PaddleTransactionCheckout />

      {/* Background Ambient Glow */}
      <div className="glow-blob-purple top-0 left-1/2 -translate-x-1/2 opacity-30" />

      {/* Header */}
      <div className="text-center max-w-3xl mx-auto space-y-4">
        <h1 className="text-4xl sm:text-6xl font-extrabold text-white tracking-tight font-[family-name:var(--font-space-grotesk)]">
          Free for most nights. <span className="text-gradient-brand">Premium for the big ones.</span>
        </h1>
        <p className="text-lg text-gray-300">
          Free rooms hold 8 people for 4 hours. Premium is for the whole group, the all-day marathon, and the room that never closes.
        </p>
      </div>

      {/* Tier Configurator */}
      <TierConfigurator />

      {/* Persistent rooms - the pair-coded beat, above the table it sells */}
      <Reveal><PersistentRoomsBand /></Reveal>

      {/* Pricing Table (Interactive Component) */}
      <Reveal><PricingTable /></Reveal>

      {/* Pricing FAQ Section */}
      <div className="max-w-4xl mx-auto pt-6 space-y-8">
        <div className="text-center space-y-2">
          <h2 className="text-2xl sm:text-3xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
            Frequently Asked Questions
          </h2>
          <p className="text-sm text-gray-400">
            Have questions about billing or subscriptions? We&apos;ve got answers.
          </p>
        </div>

        <FAQAccordion items={pricingFaqs} />
      </div>
    </div>
  );
}
