"use client";

import { useState } from "react";
import { Check, Mail } from "lucide-react";

/**
 * Shown to Android visitors only (the one phone with no app yet; iPhone and
 * iPad have the App Store door). The lit action there is a seat in the Android
 * test (AndroidSeat); this is the quiet fallback, carrying the page to a
 * device that can install it. The page decides from the request's user-agent (it is
 * dynamic anyway), so the block is in the server HTML instead of popping in above
 * the doors after hydration. The page URL is
 * shared as-is, so an invite code in `?code=` travels with it. The share sheet
 * (messages, mail, AirDrop) is the point; a browser without one falls back to
 * copying the link.
 */
export function SendToComputer({ android }: { android: boolean }) {
  const [copied, setCopied] = useState(false);

  if (!android) return null;

  const send = async () => {
    const url = window.location.href;
    try {
      if (navigator.share) {
        await navigator.share({ title: "SyncTogether for iPhone, iPad, Mac and Windows", url });
        return;
      }
      await navigator.clipboard.writeText(url);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 2000);
    } catch {
      // A dismissed share sheet rejects, and a blocked clipboard throws: both
      // leave the visitor where they were, and the page stays open to retry.
    }
  };

  return (
    <div className="flex flex-col items-start gap-1.5">
      <button
        type="button"
        onClick={send}
        className="inline-flex items-center gap-2 h-11 text-sm font-medium text-beam-400 hover:text-beam-300 cursor-pointer"
      >
        {copied ? <Check className="w-4 h-4" /> : <Mail className="w-4 h-4" />}
        <span aria-live="polite">{copied ? "Link copied. Send it to your computer or iPhone" : "Or send this page to a computer"}</span>
      </button>
    </div>
  );
}
