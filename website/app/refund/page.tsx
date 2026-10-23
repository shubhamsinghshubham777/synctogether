import type { Metadata } from "next";
import { LegalShell, LegalNum, LegalPledge } from "@/components/LegalShell";
import { SITE_CONFIG } from "@/lib/constants";

const TOC = [
  { id: "s-1", n: "01", label: "Requesting a Refund" },
  { id: "s-2", n: "02", label: "Cancelling" },
  { id: "s-3", n: "03", label: "If Premium Does Not Unlock" },
];

export const metadata: Metadata = {
  title: "Refund Policy",
  description: "How refunds for SyncTogether Premium work: the store you bought from handles them.",
};

export default function RefundPage() {
  const lastUpdated = "October 15, 2026";

  return (
    <LegalShell
      current="/refund"
      kicker="Guarantee"
      title="Refund Policy"
      dek="Premium is sold by the App Store and the Microsoft Store, so the store decides and pays out refunds."
      toc={TOC}
      dates={[{ label: "Updated", value: lastUpdated }]}
    >
        <section className="space-y-3">
          <LegalPledge title="Refunds Are Handled by the Store">
            <p>
              SyncTogether Premium is bought inside the app through the store on your device. The store takes the payment, so the store also decides and issues any refund, under its own rules.
            </p>
          </LegalPledge>
        </section>

        <section id="s-1" className="space-y-3">
          <h2>
            <LegalNum n="1" />
            Requesting a Refund
          </h2>
          <ul className="space-y-2 text-gray-300 list-disc list-inside">
            <li>Apple purchases: request a refund at <a href="https://reportaproblem.apple.com" className="text-purple-300 hover:text-white underline">reportaproblem.apple.com</a>, or through the receipt email from Apple.</li>
            <li>Microsoft Store purchases: request a refund from your Microsoft account&apos;s order history.</li>
            <li>When a store refunds a purchase, Premium on your SyncTogether account ends automatically.</li>
          </ul>
        </section>

        <section id="s-2" className="space-y-3">
          <h2>
            <LegalNum n="2" />
            Cancelling
          </h2>
          <p>
            You can cancel at any time in your store&apos;s subscription settings. Your Premium perks remain available until the end of the period you already paid for, and you will not be billed again.
          </p>
        </section>

        <section id="s-3" className="space-y-3">
          <h2>
            <LegalNum n="3" />
            If Premium Does Not Unlock
          </h2>
          <p>
            If you paid but Premium is not showing on your account, email <a href={`mailto:${SITE_CONFIG.supportEmail}`} className="text-purple-300 hover:text-white underline">{SITE_CONFIG.supportEmail}</a> with your account email and we will fix it or point you to the right store refund.
          </p>
        </section>
    </LegalShell>
  );
}
