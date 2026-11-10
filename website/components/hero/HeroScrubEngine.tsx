"use client";

import { useEffect } from "react";
import { trackWebEvent } from "@/components/AnalyticsBeacon";

/**
 * Mounts the hero scrub engine (components/hero/scrub/engine.ts) on the
 * server-rendered cluster and renders nothing. Holds no state. The engine is a
 * separate chunk, imported only after hydration, the page `load` and an idle
 * callback, so it can never delay first paint or the headline entrance. A press
 * that lands before it arrives is buffered and handed over. Without JS,
 * with Save-Data, or without IntersectionObserver/ResizeObserver the static
 * render simply stands (and the DRAG chip, which needs the engine, stays dark).
 */
export function HeroScrubEngine({ rootId }: { rootId: string }) {
  useEffect(() => {
    const root = document.getElementById(rootId);
    const zone = root?.querySelector<HTMLElement>("[data-zone]");
    if (!root || !zone) return;
    const conn = (navigator as Navigator & { connection?: { saveData?: boolean } }).connection;
    if (conn?.saveData) return;
    if (!("IntersectionObserver" in window) || !("ResizeObserver" in window)) return;

    let cancelled = false;
    let started = false;
    let cleanup: (() => void) | undefined;
    let buffered: PointerEvent | null = null;
    let idleHandle = 0;
    let usedIdle = false;

    const drop = () => {
      buffered = null;
    };
    const onEarlyDown = (e: PointerEvent) => {
      buffered = e;
      start();
    };

    const start = () => {
      if (started || cancelled) return;
      started = true;
      zone.removeEventListener("pointerdown", onEarlyDown);
      import("./scrub/engine")
        .then((m) => {
          if (cancelled) return;
          cleanup = m.mount(root, {
            reducedMotion: window.matchMedia("(prefers-reduced-motion: reduce)").matches,
            onEvent: trackWebEvent,
            pending: buffered,
          });
          buffered = null;
        })
        .catch((err) => {
          // The static render stands; never retry in a loop.
          console.warn("Hero scrub failed to load:", err);
        });
    };

    zone.addEventListener("pointerdown", onEarlyDown);
    window.addEventListener("pointerup", drop);
    window.addEventListener("pointercancel", drop);

    const whenIdle = () => {
      if (cancelled) return;
      if ("requestIdleCallback" in window) {
        usedIdle = true;
        idleHandle = window.requestIdleCallback(start, { timeout: 1200 });
      } else {
        idleHandle = setTimeout(start, 200) as unknown as number; // Safari
      }
    };
    if (document.readyState === "complete") whenIdle();
    else window.addEventListener("load", whenIdle, { once: true });

    return () => {
      cancelled = true;
      zone.removeEventListener("pointerdown", onEarlyDown);
      window.removeEventListener("pointerup", drop);
      window.removeEventListener("pointercancel", drop);
      window.removeEventListener("load", whenIdle);
      if (idleHandle) {
        if (usedIdle) window.cancelIdleCallback(idleHandle);
        else clearTimeout(idleHandle);
      }
      cleanup?.();
    };
  }, [rootId]);

  return null;
}
