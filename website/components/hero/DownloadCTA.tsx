"use client";

import Link from "next/link";
import { Download } from "lucide-react";
import { PTButton } from "@/components/PTButton";
import { useDesktopOS } from "./useDesktopOS";

export function DownloadCTA() {
  const os = useDesktopOS();
  const isWindows = os === "windows";

  const primaryLabel = isWindows ? "Download for Windows" : "Download for macOS - Apple silicon & Intel";
  const primaryHref = isWindows ? "/api/download?platform=windows" : "/api/download?platform=macos";
  const secondaryLabel = isWindows ? "Also on macOS" : "Also on Windows";

  return (
    <div className="flex flex-col items-center gap-3 pt-2">
      <div className="flex flex-col sm:flex-row items-center justify-center gap-4">
        <PTButton
          href={primaryHref}
          variant="primary"
          size="lg"
          leftIcon={<Download className="w-5 h-5" />}
          className="min-w-[19rem] sm:min-w-[21rem]"
        >
          {primaryLabel}
        </PTButton>
        <Link
          href="/download"
          className="text-sm text-gray-400 hover:text-white transition-colors underline underline-offset-4"
        >
          {secondaryLabel}
        </Link>
      </div>
      <p className="text-xs text-gray-400 font-mono">
        Free to use · No sign-up to join · Signed &amp; notarized installer
      </p>
    </div>
  );
}
