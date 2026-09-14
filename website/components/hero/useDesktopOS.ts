"use client";

import { useSyncExternalStore } from "react";

export type DesktopOS = "macos" | "windows" | "other";

function detect(): DesktopOS {
  if (typeof navigator === "undefined") return "macos";
  const uaData = (navigator as Navigator & { userAgentData?: { platform?: string } })
    .userAgentData;
  const platform = uaData?.platform ?? navigator.platform ?? navigator.userAgent;
  const p = platform.toLowerCase();
  if (p.includes("mac") || p.includes("iphone") || p.includes("ipad")) return "macos";
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
