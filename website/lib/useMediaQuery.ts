"use client";
import { useCallback, useSyncExternalStore } from "react";

/**
 * Subscribes to a CSS media query. The server snapshot is always `false`, so a
 * query must be written so that `false` is the safe pre-hydration answer - e.g.
 * ask for `min-width`, never `max-width`, or the first paint commits to the
 * heavier branch and has to walk it back.
 */
export function useMediaQuery(query: string): boolean {
  const subscribe = useCallback(
    (cb: () => void) => {
      if (typeof window === "undefined") return () => {};
      const mq = window.matchMedia(query);
      mq.addEventListener("change", cb);
      return () => mq.removeEventListener("change", cb);
    },
    [query],
  );
  return useSyncExternalStore(
    subscribe,
    () => window.matchMedia(query).matches,
    () => false,
  );
}
