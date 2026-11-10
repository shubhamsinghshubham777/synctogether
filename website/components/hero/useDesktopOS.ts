"use client";

import { useSyncExternalStore } from "react";

/**
 * Where the visitor is. The four with a store listing each get their own
 * door; "android" is a phone we cannot serve yet and "other" is anything else
 * (Linux, ChromeOS, a bot).
 */
export type DesktopOS = "macos" | "windows" | "ios" | "android" | "other";

function detect(): DesktopOS {
  if (typeof navigator === "undefined") return "macos";
  const uaData = (navigator as Navigator & { userAgentData?: { platform?: string } })
    .userAgentData;
  // All three sources, since each is missing somewhere: Safari has no
  // userAgentData, and Chromium on iOS reports the host Mac-like platform.
  const p = `${uaData?.platform ?? ""} ${navigator.platform ?? ""} ${navigator.userAgent}`.toLowerCase();
  if (/iphone|ipad|ipod/.test(p)) return "ios";
  if (p.includes("android")) return "android";
  // iPadOS 13+ asks for the desktop site and reports itself as a Mac; a Mac
  // has no touch screen, so touch points tell the two apart.
  if (p.includes("mac") && navigator.maxTouchPoints > 1) return "ios";
  if (p.includes("mac")) return "macos";
  if (p.includes("win")) return "windows";
  return "other";
}

function subscribe() {
  // Platform never changes mid-session; nothing to subscribe to.
  return () => {};
}

// Do not detect server-side: app/page.tsx is ISR (revalidate = 3600); reading the
// user-agent header would make the route dynamic and destroy the cache.
export function useDesktopOS(): DesktopOS {
  return useSyncExternalStore(subscribe, detect, () => "macos");
}
