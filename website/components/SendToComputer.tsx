"use client";

import { useState, useSyncExternalStore } from "react";
import { Check, Mail } from "lucide-react";

const subscribe = () => () => {};

/** Phones cannot install a desktop app. Server snapshot is desktop, as on /join. */
function isPhone(): boolean {
  return /android|iphone|ipod|mobile/i.test(navigator.userAgent);
}

/**
 * Shown to phone visitors only: the lit action is carrying this page to a
 * computer, since nothing on a phone can install the app. The page URL is
 * shared as-is, so an invite code in `?code=` travels with it. The share sheet
 * (messages, mail, AirDrop) is the point; a browser without one falls back to
 * copying the link.
 */
export function SendToComputer() {
  const phone = useSyncExternalStore(subscribe, isPhone, () => false);
  const [copied, setCopied] = useState(false);

  if (!phone) return null;

  const send = async () => {
    const url = window.location.href;
    try {
      if (navigator.share) {
        await navigator.share({ title: "SyncTogether for Mac and Windows", url });
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
        SyncTogether is a desktop app, so it can&apos;t be installed on this phone. Send this page to your
        Mac or Windows computer and install it there.
      </p>
      <button
        type="button"
        onClick={send}
        className="btn-primary-gradient inline-flex items-center justify-center gap-2.5 h-[52px] px-6 rounded-[4px] text-base font-semibold cursor-pointer"
      >
        {copied ? <Check className="w-4 h-4" /> : <Mail className="w-4 h-4" />}
        <span aria-live="polite">{copied ? "Link copied. Send it to your computer" : "Send this to my computer"}</span>
      </button>
    </div>
  );
}
