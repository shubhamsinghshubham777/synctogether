"use client";

import { useCallback, useEffect, useId, useRef, useState } from "react";
import Link from "next/link";
import { Lock } from "lucide-react";
import { kReactions, kExtendedReactions, PTReaction } from "@/lib/reactions";
import { useReducedMotion } from "@/lib/useReducedMotion";

interface Particle {
  id: number;
  codepoint: string;
  src: string;
  x: number;
  rotation: number;
}

const PARTICLE_CAP = 14;
const PARTICLE_LIFETIME_MS = 2200;
// Pointer has to cross the gap between the +16 button and the panel below it;
// closing on the first mouseleave makes the panel impossible to reach.
const PANEL_CLOSE_GRACE_MS = 140;

// In-memory only - no disk cache, no path_provider equivalent. A blocked or
// offline CDN degrades silently to the static frame already on screen.
const animatedCache = new Map<string, string>();

function cdnUrl(codepoint: string) {
  return `https://fonts.gstatic.com/s/e/notoemoji/latest/${codepoint}/512.webp`;
}

async function loadAnimated(codepoint: string): Promise<string | null> {
  const cached = animatedCache.get(codepoint);
  if (cached) return cached;
  try {
    const res = await fetch(cdnUrl(codepoint));
    if (!res.ok) return null;
    const blob = await res.blob();
    const url = URL.createObjectURL(blob);
    animatedCache.set(codepoint, url);
    return url;
  } catch {
    // Offline/blocked CDN is a normal path here, exactly as the Flutter app
    // treats it - silently keep the static image, no console noise.
    return null;
  }
}

export function ReactionPlayground() {
  const reducedMotion = useReducedMotion();
  const containerRef = useRef<HTMLDivElement>(null);
  const expandRef = useRef<HTMLButtonElement>(null);
  const panelId = useId();
  const [active, setActive] = useState(false);
  const [particles, setParticles] = useState<Particle[]>([]);
  const [panelOpen, setPanelOpen] = useState(false);
  const particleCounter = useRef(0);
  const timersRef = useRef<Set<ReturnType<typeof setTimeout>>>(new Set());
  const panelCloseTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  // The panel is always mounted and always out of flow (absolute, under the
  // strip), so opening it is pure opacity/translate/scale on a promoted layer -
  // nothing below it reflows, and there is no mount cost on first open.
  // `visibility` is in the transition list on purpose: it interpolates
  // discretely to hidden only at the *end* of the transition, which is what
  // takes the closed panel out of the hit-testing/AT tree without a JS timer.
  const cancelClose = () => {
    if (panelCloseTimer.current) {
      clearTimeout(panelCloseTimer.current);
      panelCloseTimer.current = null;
    }
  };

  const openPanel = useCallback(() => {
    cancelClose();
    setPanelOpen(true);
  }, []);

  const closePanel = useCallback((immediate = false) => {
    cancelClose();
    if (immediate) {
      setPanelOpen(false);
      return;
    }
    panelCloseTimer.current = setTimeout(() => {
      panelCloseTimer.current = null;
      setPanelOpen(false);
    }, PANEL_CLOSE_GRACE_MS);
  }, []);

  // Hover-to-open is a mouse affordance only: on touch the synthesized
  // pointerenter fires just before the tap, which would open and then
  // immediately toggle shut.
  const hoverOpen = (e: React.PointerEvent) => {
    if (e.pointerType === "mouse") openPanel();
  };
  const hoverClose = (e: React.PointerEvent) => {
    if (e.pointerType === "mouse") closePanel();
  };

  useEffect(() => {
    const el = containerRef.current;
    if (!el || typeof IntersectionObserver === "undefined") return;
    const observer = new IntersectionObserver(([entry]) => setActive(entry.isIntersecting), {
      threshold: 0.1,
    });
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  // Tap-anywhere-else and Esc are the only ways out on touch, where there is no
  // pointerleave to close on.
  useEffect(() => {
    if (!panelOpen) return;
    const onPointerDown = (e: PointerEvent) => {
      if (!containerRef.current?.contains(e.target as Node)) closePanel(true);
    };
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key !== "Escape") return;
      closePanel(true);
      expandRef.current?.focus();
    };
    document.addEventListener("pointerdown", onPointerDown);
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.removeEventListener("pointerdown", onPointerDown);
      document.removeEventListener("keydown", onKeyDown);
    };
  }, [panelOpen, closePanel]);

  useEffect(() => {
    const timers = timersRef.current;
    return () => {
      timers.forEach(clearTimeout);
      timers.clear();
      if (panelCloseTimer.current) clearTimeout(panelCloseTimer.current);
    };
  }, []);

  const pop = (reaction: PTReaction) => {
    if (!active) return;
    particleCounter.current += 1;
    const id = particleCounter.current;
    const staticSrc = `/emoji/${reaction.codepoint}.webp`;
    const particle: Particle = {
      id,
      codepoint: reaction.codepoint,
      src: staticSrc,
      x: 10 + ((id * 17) % 80),
      rotation: ((id * 13) % 24) - 12,
    };
    setParticles((prev) => [...prev.slice(-(PARTICLE_CAP - 1)), particle]);
    const timer = setTimeout(() => {
      setParticles((prev) => prev.filter((p) => p.id !== id));
      timersRef.current.delete(timer);
    }, PARTICLE_LIFETIME_MS);
    timersRef.current.add(timer);

    if (!reducedMotion) {
      loadAnimated(reaction.codepoint).then((animatedSrc) => {
        if (!animatedSrc) return;
        setParticles((prev) => prev.map((p) => (p.id === id ? { ...p, src: animatedSrc } : p)));
      });
    }
  };

  return (
    <div ref={containerRef} className="relative">
      {/* This strip scrolls horizontally on narrow screens (never shrinks below 8
          cells), which clips any absolutely-positioned overflow - so the +16
          expand panel below lives outside this container, not inside it. */}
      <div className="relative overflow-x-auto pb-2 -mx-2 px-2">
        <div className="relative flex items-center gap-2 w-max mx-auto">
          {kReactions.map((r) => (
            <button
              key={r.codepoint}
              onClick={() => pop(r)}
              title={r.label}
              className="w-12 h-12 sm:w-14 sm:h-14 shrink-0 rounded-2xl glass-panel flex items-center justify-center hover:border-purple-400/40 transition-colors cursor-pointer"
            >
              {/* eslint-disable-next-line @next/next/no-img-element -- tiny fixed-size static frame, not an LCP candidate */}
              <img src={`/emoji/${r.codepoint}.webp`} alt={r.label} width={32} height={32} loading="lazy" />
            </button>
          ))}

          <button
            ref={expandRef}
            onClick={() => (panelOpen ? closePanel(true) : openPanel())}
            onPointerEnter={hoverOpen}
            onPointerLeave={hoverClose}
            title="16 more with Premium"
            aria-expanded={panelOpen}
            aria-controls={panelId}
            className="w-12 h-12 sm:w-14 sm:h-14 shrink-0 rounded-2xl glass-panel border-[color:var(--pt-premium-border)]/40 flex flex-col items-center justify-center gap-0.5 text-[color:var(--pt-premium)] cursor-pointer"
          >
            <Lock className="w-3.5 h-3.5" />
            <span className="text-[10px] font-mono font-bold">+16</span>
          </button>
        </div>
      </div>

      {/* Out of flow, so the sections below never move. The wrapper is inert to
          the pointer; only the panel itself takes hits. */}
      <div className="pointer-events-none absolute inset-x-0 top-full z-30 flex justify-center">
        <div
          id={panelId}
          inert={!panelOpen}
          onPointerEnter={hoverOpen}
          onPointerLeave={hoverClose}
          className={`pointer-events-auto mt-2 w-full max-w-xs sm:max-w-sm bg-[#141022] border border-[color:var(--pt-premium-border)]/40 rounded-2xl p-3 shadow-2xl space-y-2.5 origin-top transform-gpu transition-[opacity,translate,scale,visibility] duration-200 ease-out motion-reduce:transition-none ${
            panelOpen
              ? "visible opacity-100 scale-100 translate-y-0"
              : "invisible opacity-0 scale-95 -translate-y-1"
          }`}
        >
          <div className="grid grid-cols-8 gap-1.5">
            {kExtendedReactions.map((r, i) => (
              <div
                key={r.codepoint}
                title={r.label}
                className={`w-7 h-7 rounded-lg bg-white/5 flex items-center justify-center transform-gpu transition-[opacity,scale] duration-200 ease-out motion-reduce:transition-none ${
                  panelOpen ? "opacity-80 scale-100" : "opacity-0 scale-75"
                }`}
                style={{ transitionDelay: panelOpen && !reducedMotion ? `${i * 12}ms` : "0ms" }}
              >
                {/* eslint-disable-next-line @next/next/no-img-element -- tiny fixed-size static frame, not an LCP candidate */}
                <img src={`/emoji/${r.codepoint}.webp`} alt={r.label} width={20} height={20} loading="lazy" />
              </div>
            ))}
          </div>
          <Link
            href="/pricing"
            className="block text-center text-xs text-[color:var(--pt-premium)] hover:underline underline-offset-2"
          >
            16 more with Premium
          </Link>
        </div>
      </div>

      <div className="pointer-events-none absolute inset-x-0 -top-2 h-0 z-40 overflow-visible">
        {particles.map((p) => (
          // eslint-disable-next-line @next/next/no-img-element -- ephemeral particle, may be a foreign CDN blob: URL
          <img
            key={p.id}
            src={p.src}
            alt=""
            width={40}
            height={40}
            className={
              reducedMotion
                ? "absolute animate-reaction-appear"
                : "absolute animate-reaction-float"
            }
            // `rotate`, not a transform - the float keyframes own `transform`,
            // and an animation overrides an inline transform outright.
            style={{ left: `${p.x}%`, rotate: `${p.rotation}deg` }}
          />
        ))}
      </div>
    </div>
  );
}
