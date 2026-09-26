"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { useRoomSim } from "@/components/room-sim/useRoomSim";
import { RoomFrame } from "@/components/room-sim/RoomFrame";
import { useMediaQuery } from "@/lib/useMediaQuery";
import { useReducedMotion } from "@/lib/useReducedMotion";
import { useSaveData } from "@/lib/useSaveData";
import { SyncToggle } from "./SyncToggle";

type SyncPhase = "desynced" | "syncing" | "synced";

/**
 * Two different offsets, deliberately never unified. DESYNCED_OFFSETS is what the
 * HUD reports - a plausible desync of the *room* clock, which useRoomSim already
 * simulates as a 02:24:33 runtime. DESYNCED_VIDEO_OFFSETS is what the film actually
 * does, and has to stay well inside the 9s loop or the wrap becomes the visual.
 */
const DESYNCED_OFFSETS: [number, number, number] = [0, -14.2, 6.8];
const DESYNCED_VIDEO_OFFSETS: [number, number, number] = [0, -3.4, 1.8];
const SYNCED_OFFSETS: [number, number, number] = [0, 0, 0];
const TWEEN_MS = 600;
/** Mirrors the app's own position_sync: correct on a timer, not every frame. */
const DRIFT_CHECK_MS = 2000;
const DRIFT_TOLERANCE_SEC = 0.15;

/** Where a secondary should sit, wrapped into the loop. */
function targetTime(masterTime: number, offsetSec: number, durationSec: number) {
  return (((masterTime + offsetSec) % durationSec) + durationSec) % durationSec;
}

/** Shortest signed distance across the loop seam, so a wrap doesn't read as drift. */
function loopDelta(to: number, from: number, durationSec: number) {
  const d = (((to - from) % durationSec) + durationSec) % durationSec;
  return d > durationSec / 2 ? d - durationSec : d;
}

/** Mono strip above a screen: whose screen it is and what it is doing right now. */
function ScreenLabel({ who, state, tone }: { who: string; state: string; tone: "beam" | "cue" | "signal" }) {
  const color = tone === "beam" ? "text-beam-500" : tone === "cue" ? "text-cue" : "text-signal";
  return (
    <div className="flex items-center justify-between px-1 pb-2 font-[family-name:var(--font-jetbrains-mono)] text-[11px] tracking-[0.14em] uppercase">
      <span className="text-gray-500">{who}</span>
      <span className={`${color} transition-colors duration-300`} aria-live="polite">
        {state}
      </span>
    </div>
  );
}

export function HeroStage({ header }: { header?: React.ReactNode } = {}) {
  const reducedMotion = useReducedMotion();
  const isDesktop = useMediaQuery("(min-width: 1024px)");
  const containerRef = useRef<HTMLDivElement>(null);
  const [active, setActive] = useState(false);
  const hasRunAutoDemo = useRef(false);

  const sim = useRoomSim({ active });

  const [phase, setPhase] = useState<SyncPhase>("synced");
  const [offsets, setOffsets] = useState<[number, number, number]>(SYNCED_OFFSETS);
  const [pulse, setPulse] = useState(false);
  const rafRef = useRef<number | null>(null);
  const tweenRef = useRef<{
    start: number;
    from: [number, number, number];
    fromVideo: [number, number, number];
  } | null>(null);
  const timersRef = useRef<Set<ReturnType<typeof setTimeout>>>(new Set());

  // Frame A is the clock master; B and C are seeked against it.
  const videoA = useRef<HTMLVideoElement>(null);
  const videoB = useRef<HTMLVideoElement>(null);
  const videoC = useRef<HTMLVideoElement>(null);
  const videoOffsetsRef = useRef<[number, number, number]>(SYNCED_OFFSETS);

  const saveData = useSaveData();
  const [videoBlocked, setVideoBlocked] = useState(false);
  const posterOnly = reducedMotion || saveData || videoBlocked;

  /**
   * Seeks the secondaries onto their offsets. `force` skips the tolerance check and is
   * for the two moments the offset itself moved (the desync jump, and each tween tick);
   * the periodic check passes false so an in-tolerance frame is left alone - seeking is
   * expensive, and doing it per frame is what this exists to avoid.
   */
  const alignSecondaries = useCallback((force: boolean) => {
    const master = videoA.current;
    if (!master) return;
    const dur = master.duration;
    if (!Number.isFinite(dur) || dur <= 0) return; // metadata not in yet; the timer retries
    const offs = videoOffsetsRef.current;
    for (const [i, ref] of [videoB, videoC].entries()) {
      const el = ref.current;
      if (!el) continue;
      const target = targetTime(master.currentTime, offs[i + 1], dur);
      if (force || Math.abs(loopDelta(target, el.currentTime, dur)) > DRIFT_TOLERANCE_SEC) {
        el.currentTime = target;
      }
    }
  }, []);

  /**
   * Where the guests' films actually are relative to the host's. With sync
   * off they run free, so the offset they were given at the desync is stale
   * by the time sync comes back on - the catch-up has to start from here.
   */
  const measuredVideoOffsets = (): [number, number, number] => {
    const master = videoA.current;
    const dur = master?.duration ?? 0;
    if (!master || !Number.isFinite(dur) || dur <= 0) return videoOffsetsRef.current;
    const at = (el: HTMLVideoElement | null, fallback: number) =>
      el ? loopDelta(el.currentTime, master.currentTime, dur) : fallback;
    return [0, at(videoB.current, videoOffsetsRef.current[1]), at(videoC.current, videoOffsetsRef.current[2])];
  };

  // The page's one rAF loop - only scheduled while a sync tween is running, and the one
  // place a per-frame seek is allowed.
  const startSyncTween = () => {
    if (rafRef.current !== null) return;
    setPhase("syncing");
    tweenRef.current = {
      start: performance.now(),
      from: offsets,
      fromVideo: measuredVideoOffsets(),
    };
    const tick = (now: number) => {
      const { start, from, fromVideo } = tweenRef.current!;
      const t = Math.min(1, (now - start) / TWEEN_MS);
      setOffsets([
        from[0] + (0 - from[0]) * t,
        from[1] + (0 - from[1]) * t,
        from[2] + (0 - from[2]) * t,
      ]);
      videoOffsetsRef.current = [0, fromVideo[1] * (1 - t), fromVideo[2] * (1 - t)];
      alignSecondaries(true);
      if (t < 1) {
        rafRef.current = requestAnimationFrame(tick);
      } else {
        rafRef.current = null;
        setOffsets(SYNCED_OFFSETS);
        videoOffsetsRef.current = SYNCED_OFFSETS;
        alignSecondaries(true);
        setPhase("synced");
        setPulse(true);
        const timer = setTimeout(() => setPulse(false), 550);
        timersRef.current.add(timer);
      }
    };
    rafRef.current = requestAnimationFrame(tick);
  };

  const goDesynced = () => {
    if (rafRef.current !== null) {
      cancelAnimationFrame(rafRef.current);
      rafRef.current = null;
    }
    setPulse(false);
    setOffsets(DESYNCED_OFFSETS);
    videoOffsetsRef.current = DESYNCED_VIDEO_OFFSETS;
    alignSecondaries(true);
    setPhase("desynced");
  };

  const toggleSync = () => {
    if (phase === "synced") goDesynced();
    else if (phase === "desynced") startSyncTween();
  };

  // Without sync nothing links the screens, so the host's play/pause reaches
  // the host's screen alone - the guests carry on as if nobody had touched
  // anything. That is the whole point of the flip.
  const linked = phase !== "desynced";
  const guestsPlaying = linked ? sim.playing : true;

  // Playback follows visibility (and each screen's transport), never autoplays offscreen.
  useEffect(() => {
    if (posterOnly) return;
    const plan: [HTMLVideoElement | null, boolean][] = [
      [videoA.current, sim.playing],
      [videoB.current, guestsPlaying],
      [videoC.current, guestsPlaying],
    ];
    const toPlay: HTMLVideoElement[] = [];
    for (const [el, playing] of plan) {
      if (!el) continue;
      if (active && playing) toPlay.push(el);
      else el.pause();
    }
    let cancelled = false;
    // Low-power mode rejects inline autoplay. This is decoration: no error, no play
    // button, just the poster.
    Promise.all(toPlay.map((el) => el.play())).catch(() => {
      if (!cancelled) setVideoBlocked(true);
    });
    return () => {
      cancelled = true;
    };
  }, [active, sim.playing, guestsPlaying, posterOnly]);

  // Independent decoders drift apart within seconds; a sync demo cannot afford that -
  // but only while sync is on. With it off, drifting is exactly what they should do.
  useEffect(() => {
    if (posterOnly || !active || !linked) return;
    alignSecondaries(false);
    const id = setInterval(() => alignSecondaries(false), DRIFT_CHECK_MS);
    return () => clearInterval(id);
  }, [active, posterOnly, linked, alignSecondaries]);

  // The HUD clocks come from the host's sim, which stops when the host pauses. Guests
  // who never heard about the pause keep counting: a second a tick, only while that is
  // actually the situation on screen.
  useEffect(() => {
    if (linked || sim.playing || !active) return;
    const id = setInterval(() => setOffsets((o) => [o[0], o[1] + 1, o[2] + 1]), 1000);
    return () => clearInterval(id);
  }, [linked, sim.playing, active]);

  // Gate every timer on visibility, and run the auto-demo exactly once.
  useEffect(() => {
    const el = containerRef.current;
    if (!el || typeof IntersectionObserver === "undefined") return;
    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          setActive(entry.isIntersecting);
          if (!hasRunAutoDemo.current && entry.intersectionRatio >= 0.5) {
            hasRunAutoDemo.current = true;
            if (reducedMotion) {
              setOffsets(SYNCED_OFFSETS);
              setPhase("synced");
              continue;
            }
            const t1 = setTimeout(() => {
              goDesynced();
              const t2 = setTimeout(() => startSyncTween(), 1600);
              timersRef.current.add(t2);
            }, 900);
            timersRef.current.add(t1);
          }
        }
      },
      { threshold: [0.05, 0.5] },
    );
    observer.observe(el);
    return () => observer.disconnect();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [reducedMotion]);

  useEffect(() => {
    const timers = timersRef.current;
    return () => {
      timers.forEach(clearTimeout);
      timers.clear();
      if (rafRef.current !== null) cancelAnimationFrame(rafRef.current);
    };
  }, []);

  const caption =
    phase === "desynced" ? "wait what just happened??" : phase === "synced" ? "in sync" : undefined;

  const hostState = phase === "synced" ? "In sync" : phase === "syncing" ? "Syncing" : "Out of sync";
  const drifting = phase === "desynced" && !sim.playing ? "Still playing" : null;
  const secState = phase === "synced" ? "In sync" : phase === "syncing" ? "Catching up" : drifting ?? "Behind";
  const secStateC = phase === "synced" ? "Caught up" : phase === "syncing" ? "Catching up" : drifting ?? "Ahead";
  // What the guests' own transports show: their own playback, not the host's.
  const guestSim = linked ? sim : { ...sim, playing: guestsPlaying };
  const secTone = phase === "synced" ? ("cue" as const) : ("signal" as const);

  const identity = { roomName: "movie night", roomCode: "WZ2CWX", osChrome: "macos" as const };
  // Only the primary frame, and only on desktop, is ever worth the 960 encode.
  const frameVideo = { posterOnly, lowResVideo: !isDesktop };

  return (
    <div className="w-full space-y-7">
      <div className="flex flex-col md:flex-row md:items-end justify-between gap-6">
        {header}
        <div className="shrink-0">
          <SyncToggle synced={phase === "synced"} onToggle={toggleSync} disabled={phase === "syncing"} />
        </div>
      </div>
      <div
        ref={containerRef}
        className="flex flex-col sm:flex-row items-center justify-center gap-3 sm:gap-5 lg:gap-6"
      >
        {/* Frame B - secondary, flanks left on tablet+, stacks below on mobile */}
        <div
          className="hidden sm:block order-2 sm:order-1 sm:w-[38%] lg:w-[27%] shrink-0"
          style={{ zIndex: 0 }}
        >
          <ScreenLabel who="Guest · Windows" state={secState} tone={secTone} />
          <RoomFrame
            state={guestSim}
            offsetSec={offsets[1]}
            fidelity="reduced"
            identity={identity}
            videoRef={videoB}
            {...frameVideo}
            showHud={!reducedMotion}
            showBuffering={phase !== "synced"}
          />
        </div>

        {/* Frame A - primary, interactive, and the clock every other frame is seeked against */}
        <div className="order-1 sm:order-2 w-full sm:w-[56%] lg:w-[42%] shrink-0 relative z-10">
          <ScreenLabel who="Host · Mac" state={hostState} tone="beam" />
          <RoomFrame
            state={sim}
            actions={sim.actions}
            offsetSec={offsets[0]}
            fidelity="full"
            identity={identity}
            videoRef={videoA}
            {...frameVideo}
            showHud={!reducedMotion}
            caption={caption}
            pulseLock={pulse}
            priority
          />
        </div>

        {/* Frame C - secondary, desktop only */}
        <div
          className="hidden lg:block order-3 lg:w-[27%] shrink-0"
          style={{ zIndex: 0 }}
        >
          <ScreenLabel who="Guest · Mac" state={secStateC} tone={secTone} />
          <RoomFrame
            state={guestSim}
            offsetSec={offsets[2]}
            fidelity="reduced"
            identity={identity}
            videoRef={videoC}
            {...frameVideo}
            showHud={!reducedMotion}
          />
        </div>
      </div>

    </div>
  );
}
