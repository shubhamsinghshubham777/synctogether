import type { Metadata } from "next";
import Link from "next/link";
import { SITE_CONFIG } from "@/lib/constants";
import { display, mono } from "@/components/booth/Booth";
import { COMPARISONS, FACTS, GUIDES } from "./facts";

export const metadata: Metadata = {
  title: "SyncTogether Facts: Platforms, Price and Limits",
  description:
    "The plain facts about SyncTogether: what it plays, which platforms it runs on, what it costs and what each plan allows.",
  alternates: { canonical: "/facts" },
};

export default function FactsPage() {
  return (
    <div className="px-4 sm:px-6 lg:px-8 max-w-3xl min-[2000px]:max-w-[1920px] mx-auto pt-8 md:pt-12 pb-16 min-[2000px]:grid min-[2000px]:grid-cols-[1fr_1.7fr] min-[2000px]:grid-rows-[auto_1fr] min-[2000px]:gap-x-24 min-[2000px]:items-start">
      <div className="min-[2000px]:col-start-1 min-[2000px]:row-start-1">
      <p className={`${mono} text-xs tracking-[0.14em] uppercase text-gray-500`}>
        <span className="text-beam-500">Facts</span> · {SITE_CONFIG.name}
      </p>
      <h1 className={`${display} mt-4 text-[clamp(2.25rem,5vw,3.5rem)] font-extrabold leading-[0.95] tracking-[-0.04em] text-white`}>
        SyncTogether, in plain facts.
      </h1>
      </div>
      <dl className="mt-10 border-t border-rail min-[2000px]:mt-0 min-[2000px]:col-start-2 min-[2000px]:row-start-1 min-[2000px]:row-span-2">
        {FACTS.map(({ label, value }) => (
          <div key={label} className="grid grid-cols-1 sm:grid-cols-[11rem_1fr] gap-1 sm:gap-6 py-4 border-b border-aisle">
            <dt className={`${mono} text-xs uppercase tracking-[0.12em] text-gray-500`}>{label}</dt>
            <dd className="min-w-0 [overflow-wrap:anywhere] text-gray-200 leading-[1.55]">{value}</dd>
          </div>
        ))}
      </dl>
      <div className="min-[2000px]:col-start-1 min-[2000px]:row-start-2">
      <h2 className={`${display} mt-12 text-2xl font-extrabold tracking-[-0.03em] text-white`}>How it differs</h2>
      <ul className="mt-4 space-y-2 text-gray-300">
        {COMPARISONS.map(({ name, path }) => (
          <li key={path}>
            <Link href={path} className="underline underline-offset-4 decoration-rail hover:decoration-beam-500">
              SyncTogether vs {name}
            </Link>
          </li>
        ))}
      </ul>
      <h2 className={`${display} mt-10 text-2xl font-extrabold tracking-[-0.03em] text-white`}>Guides</h2>
      <ul className="mt-4 space-y-2 text-gray-300">
        {GUIDES.map(({ name, path }) => (
          <li key={path}>
            <Link href={path} className="underline underline-offset-4 decoration-rail hover:decoration-beam-500">
              {name}
            </Link>
          </li>
        ))}
      </ul>
      <p className="mt-10 text-sm text-gray-500">
        Questions? See the <Link href="/faq" className="underline underline-offset-4">FAQ</Link> or the{" "}
        <Link href="/privacy" className="underline underline-offset-4">privacy policy</Link>.
      </p>
      </div>
    </div>
  );
}
