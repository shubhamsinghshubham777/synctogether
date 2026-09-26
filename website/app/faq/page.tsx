import type { Metadata } from "next";
import { FAQ_ITEMS, SITE_CONFIG } from "@/lib/constants";
import { PageHead } from "@/components/PageHead";
import { FaqBrowser, FaqSearch, type FaqCategory } from "@/components/FaqBrowser";

export const metadata: Metadata = {
  title: "Frequently Asked Questions (FAQ)",
  description: "Find answers to all questions about SyncTogether rooms, media synchronization, facecams, and premium subscriptions.",
};

/** Marketing copy calls the paid tier "Patron"; the JSON-LD reads the same text. */
const patron = (t: string) => t.replace(/\bPremium\b/g, "Patron");

export default function FAQPage() {
  let n = 0;
  const categories: FaqCategory[] = FAQ_ITEMS.map((cat) => ({
    category: patron(cat.category),
    questions: cat.questions.map((q) => ({ q: patron(q.q), a: patron(q.a), n: ++n })),
  }));

  // Generate FAQPage JSON-LD schema
  const allQuestions = categories.flatMap((cat) => cat.questions);
  const faqSchema = {
    "@context": "https://schema.org",
    "@type": "FAQPage",
    mainEntity: allQuestions.map((q) => ({
      "@type": "Question",
      name: q.q,
      acceptedAnswer: {
        "@type": "Answer",
        text: q.a,
      },
    })),
  };

  return (
    <div className="relative pt-8 md:pt-14 pb-12 px-4 sm:px-6 lg:px-8 max-w-7xl mx-auto space-y-11">
      {/* JSON-LD Schema */}
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(faqSchema) }}
      />

      <PageHead
        gridClassName="lg:grid-cols-[1.4fr_1fr] items-end"
        titleClassName="text-[clamp(2.5rem,6vw,5rem)]"
        eyebrow="Front of house"
        title={
          <>
            Asked at the door.
            <br />
            <span className="text-gray-500">Answered here.</span>
          </>
        }
        aside={<FaqSearch />}
      />

      <FaqBrowser categories={categories} supportEmail={SITE_CONFIG.supportEmail} />
    </div>
  );
}
