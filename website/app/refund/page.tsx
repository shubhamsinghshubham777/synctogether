import type { Metadata } from "next";
import { LegalShell, LegalNum, LegalPledge } from "@/components/LegalShell";
import { SITE_CONFIG } from "@/lib/constants";

const TOC = [
  { id: "s-1", n: "01", label: "Requesting a Refund" },
  { id: "s-2", n: "02", label: "After 14 Days" },
  { id: "s-3", n: "03", label: "Abuse Protection" },
];

export const metadata: Metadata = {
  title: "Refund Policy (14-Day Money-Back Guarantee)",
  description: "SyncTogether 14-day no-questions-asked refund policy for Premium subscriptions.",
};

export default function RefundPage() {
  const lastUpdated = "August 30, 2026";

  return (
    <LegalShell
      current="/refund"
      kicker="Guarantee"
      title="Refund Policy"
      dek="Fourteen days to change your mind about a Premium subscription. No questions, no forms."
      toc={TOC}
      dates={[{ label: "Updated", value: lastUpdated }]}
    >
        <section className="space-y-3">
          <LegalPledge title="14-Day Money-Back Guarantee">
            <p>
              We want you to love SyncTogether. If you are not completely satisfied with your first purchase of SyncTogether Premium, you can request a full refund within 14 days of your initial payment, no questions asked.
            </p>
          </LegalPledge>
        </section>

        <section id="s-1" className="space-y-3">
          <h2>
            <LegalNum n="1" />
            Requesting a Refund
          </h2>
          <p>
            All subscriptions are processed securely through our authorized Merchant of Record, Paddle Payments Ltd.
          </p>
          <ul className="space-y-2 text-gray-300 list-disc list-inside">
            <li>To request a refund, email <a href={`mailto:${SITE_CONFIG.supportEmail}`} className="text-purple-300 hover:text-white underline">{SITE_CONFIG.supportEmail}</a> with your account email address.</li>
            <li>Refunds are processed directly back to your original payment method (Credit/Debit Card, PayPal, Apple Pay, Google Pay, UPI, etc.) within 5 to 7 business days.</li>
          </ul>
        </section>

        <section id="s-2" className="space-y-3">
          <h2>
            <LegalNum n="2" />
            After 14 Days
          </h2>
          <p>
            Payments made after the 14-day initial guarantee window are non-refundable. However, you can cancel your subscription at any time; your Premium perks will remain available until the conclusion of your current billing period.
          </p>
        </section>

        <section id="s-3" className="space-y-3">
          <h2>
            <LegalNum n="3" />
            Abuse Protection
          </h2>
          <p>
            We reserve the right to decline refund requests in cases of suspected fraudulent behavior or repeated subscribe-and-refund cycles.
          </p>
        </section>
    </LegalShell>
  );
}
