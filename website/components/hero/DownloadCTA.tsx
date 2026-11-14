"use client";

import { useState } from "react";
import Link from "next/link";
import { SITE_CONFIG } from "@/lib/constants";
import { Mail, Check } from "lucide-react";
import { PTButton } from "@/components/PTButton";
import { useDesktopOS } from "./useDesktopOS";

/**
 * The page's one lit button. `align="start"` for the hero column; centred
 * everywhere else. The lit button goes straight to the visitor's own store. An
 * iPhone or iPad visitor gets the App Store at every width; a phone with no app
 * yet (Android) gets "Copy the download link" so the link can reach a computer.
 */
export function DownloadCTA({ align = "center" }: { align?: "center" | "start" }) {
  const os = useDesktopOS();
  const isWindows = os === "windows";
  const isIOS = os === "ios";
  const [copied, setCopied] = useState(false);

  const primaryLabel = isWindows ? "Get a free seat · Microsoft Store" : "Get a free seat · App Store";
  const primaryHref = isWindows ? SITE_CONFIG.microsoftStoreUrl : SITE_CONFIG.appStoreUrl;
  const secondaryLabel = isWindows ? "Also on Mac and iPhone" : isIOS ? "Also on Mac and Windows" : "Also on Windows and iPhone";

  async function copyLink() {
    const url = `${window.location.origin}/download`;
    try {
      await navigator.clipboard.writeText(url);
    } catch {
      // Clipboard refused (insecure context, permissions): fall back to a hidden textarea.
      const ta = document.createElement("textarea");
      ta.value = url;
      ta.setAttribute("readonly", "");
      ta.style.position = "fixed";
      ta.style.opacity = "0";
      document.body.appendChild(ta);
      ta.select();
      try {
        document.execCommand("copy");
      } catch {}
      ta.remove();
    }
    setCopied(true);
    setTimeout(() => setCopied(false), 2400);
  }

  const start = align === "start";

  return (
    <div className={`w-full flex flex-col gap-3 ${start ? "items-start" : "items-center"}`}>
      {/* Phone with no app for it: carry the link to a computer instead. */}
      <div className={`${isIOS ? "hidden" : "sm:hidden"} w-full space-y-3`}>
        <div data-hero-cta className="w-full">
        <PTButton
          onClick={copyLink}
          variant="primary"
          size="lg"
          className="w-full"
          leftIcon={copied ? <Check className="w-5 h-5" /> : <Mail className="w-5 h-5" />}
        >
          {copied ? "Link copied" : "Copy the download link"}
        </PTButton>
        </div>
        <p className="text-[13px] leading-relaxed text-gray-400" aria-live="polite">
          {copied
            ? "Paste it anywhere you'll open on your computer."
            : "SyncTogether runs on Mac, Windows, iPhone and iPad. Open the link on your computer."}
        </p>
      </div>

      {/* Tablet and up */}
      <div
        className={`${isIOS ? "flex flex-col sm:flex-row" : "hidden sm:flex flex-row"} items-center gap-5 ${
          start ? "justify-start" : "justify-center"
        }`}
      >
        {/* data-hero-cta: the hero scrub rings this once at its payoff (globals.css). */}
        <div data-hero-cta className="rounded-[4px]">
          <PTButton
            href={primaryHref}
            variant="primary"
            className="!h-[54px] !px-6 !rounded-[4px] !text-[17px] !font-semibold"
          >
            {primaryLabel}
          </PTButton>
        </div>
        <Link
          href="/download"
          className="text-[15px] font-semibold text-screen underline underline-offset-[6px] decoration-[#5A4F44] hover:decoration-beam-500 transition-colors"
        >
          {secondaryLabel}
        </Link>
      </div>

      <Link
        href="/android"
        className="font-[family-name:var(--font-jetbrains-mono)] text-[12px] tracking-[0.08em] uppercase text-gray-400 hover:text-beam-500 transition-colors"
      >
        On Android? Save a test seat →
      </Link>
    </div>
  );
}
