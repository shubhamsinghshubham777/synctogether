"use client";

import { useState } from "react";
import { Check, Copy } from "lucide-react";

/**
 * "Copy code" + "Open the room" under the carried-over invite ticket. The
 * copy is the point: the code will not survive the installer, so it has to
 * leave with the visitor. "Open the room" is the scheme link for somebody
 * who turns out to have the app already.
 */
export function DownloadInviteActions({ code }: { code: string }) {
  const [copied, setCopied] = useState(false);

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(code);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 2000);
    } catch {
      // Clipboard blocked (insecure context, permissions). The code is on the
      // ticket in large type; copying it by hand is the fallback.
    }
  };

  return (
    <div className="flex flex-wrap items-center gap-x-4 gap-y-3">
      <button
        type="button"
        onClick={copy}
        className="inline-flex items-center gap-2 rounded-md border border-rail px-5 py-2.5 text-sm font-semibold text-white hover:border-gray-600 hover:bg-white/5 transition-colors cursor-pointer"
      >
        {copied ? <Check className="w-4 h-4 text-cue" /> : <Copy className="w-4 h-4" />}
        <span aria-live="polite">{copied ? "Copied" : "Copy code"}</span>
      </button>
      <p className="text-sm text-gray-400">
        Already installed?{" "}
        <a
          href={`synctogether://join/${code}`}
          className="font-semibold text-white underline underline-offset-4 decoration-rail hover:decoration-beam-500"
        >
          Open the room
        </a>
      </p>
    </div>
  );
}
