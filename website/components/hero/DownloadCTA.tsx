"use client";

import { useState } from "react";
import Link from "next/link";
import { SITE_CONFIG } from "@/lib/constants";
import { Mail, Check } from "lucide-react";
import { PTButton } from "@/components/PTButton";
import { useDesktopOS } from "./useDesktopOS";

/**
 * The page's one lit button. `align="start"` for the hero column; centred
 * everywhere else. The lit button goes straight to the visitor's own store. On
 * phones it becomes "Copy the download link" so the link can reach a computer.
 */
export function DownloadCTA({ align = "center" }: { align?: "center" | "start" }) {
  const os = useDesktopOS();
  const isWindows = os === "windows";
  const [copied, setCopied] = useState(false);

  const primaryLabel = isWindows ? "Get a free seat · Microsoft Store" : "Get a free seat · App Store";
  const primaryHref = isWindows ? SITE_CONFIG.microsoftStoreUrl : SITE_CONFIG.appStoreUrl;
  const secondaryLabel = isWindows ? "Also on Mac" : "Also on Windows";

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
      {/* Phone */}
      <div className="sm:hidden w-full space-y-3">
        <PTButton
          onClick={copyLink}
          variant="primary"
          size="lg"
          className="w-full"
          leftIcon={copied ? <Check className="w-5 h-5" /> : <Mail className="w-5 h-5" />}
        >
          {copied ? "Link copied" : "Copy the download link"}
        </PTButton>
        <p className="text-[13px] leading-relaxed text-gray-400" aria-live="polite">
          {copied
            ? "Paste it anywhere you'll open on your computer."
            : "Open it on your computer, or grab the app straight from your phone's store."}
        </p>
      </div>

      {/* Tablet and up */}
      <div className={`hidden sm:flex flex-row items-center gap-5 ${start ? "justify-start" : "justify-center"}`}>
        <PTButton
          href={primaryHref}
          variant="primary"
          className="!h-[54px] !px-6 !rounded-[4px] !text-[17px] !font-semibold"
        >
          {primaryLabel}
        </PTButton>
        <Link
          href="/download"
          className="text-[15px] font-semibold text-screen underline underline-offset-[6px] decoration-[#5A4F44] hover:decoration-beam-500 transition-colors"
        >
          {secondaryLabel}
        </Link>
      </div>
    </div>
  );
}
