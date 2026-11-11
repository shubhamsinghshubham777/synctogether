"use client";

import { useState } from "react";
import { Check, Mail } from "lucide-react";

/**
 * Shown to Android visitors only (the one phone with no app yet; iPhone and
 * iPad have the App Store door). The lit action is carrying this page to a
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
    <div className="rounded-md border border-rail bg-seat p-5 flex flex-col gap-3">
      <p className="text-[15px] text-gray-300 leading-[1.55]">
        SyncTogether runs on iPhone, iPad, Mac and Windows. Send this page to one of those and install it
        there.
      </p>
      <button
        type="button"
        onClick={send}
        className="btn-primary-gradient inline-flex items-center justify-center gap-2.5 h-[52px] px-6 rounded-[4px] text-base font-semibold cursor-pointer"
      >
        {copied ? <Check className="w-4 h-4" /> : <Mail className="w-4 h-4" />}
        <span aria-live="polite">{copied ? "Link copied. Send it to your computer or iPhone" : "Send this to another device"}</span>
      </button>
    </div>
  );
}
