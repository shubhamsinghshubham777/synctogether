"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { useRoomSim } from "@/components/room-sim/useRoomSim";
import { RoomFrame } from "@/components/room-sim/RoomFrame";
import { useMediaQuery } from "@/lib/useMediaQuery";
import { useReducedMotion } from "@/lib/useReducedMotion";
import { useSaveData } from "@/lib/useSaveData";
import { SyncToggle } from "./SyncToggle";
import { DownloadCTA } from "./DownloadCTA";

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

export function HeroStage() {
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

  // The page's one rAF loop - only scheduled while a sync tween is running, and the one
  // place a per-frame seek is allowed.
  const startSyncTween = () => {
    if (rafRef.current !== null) return;
    setPhase("syncing");
    tweenRef.current = {
      start: performance.now(),
      from: offsets,
      fromVideo: videoOffsetsRef.current,
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

  // Playback follows visibility (and the frame's own transport), never autoplays offscreen.
  useEffect(() => {
    if (posterOnly) return;
    const els = [videoA.current, videoB.current, videoC.current].filter(
      (el): el is HTMLVideoElement => el !== null,
    );
    if (els.length === 0) return;
    if (!active || !sim.playing) {
      els.forEach((el) => el.pause());
      return;
    }
    let cancelled = false;
    // Low-power mode rejects inline autoplay. This is decoration: no error, no play
    // button, just the poster.
    Promise.all(els.map((el) => el.play())).catch(() => {
      if (!cancelled) setVideoBlocked(true);
    });
    return () => {
      cancelled = true;
    };
  }, [active, sim.playing, posterOnly]);

  // Independent decoders drift apart within seconds; a sync demo cannot afford that.
  useEffect(() => {
    if (posterOnly || !active) return;
    alignSecondaries(false);
    const id = setInterval(() => alignSecondaries(false), DRIFT_CHECK_MS);
    return () => clearInterval(id);
  }, [active, posterOnly, alignSecondaries]);

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
    phase === "desynced" ? "wait what just happened??" : phase === "synced" ? "🔒 in sync" : undefined;

  const identity = { roomName: "movie night", roomCode: "WZ2CWX", osChrome: "macos" as const };
  // Only the primary frame, and only on desktop, is ever worth the 960 encode.
  const frameVideo = { posterOnly, lowResVideo: !isDesktop };

  return (
    <div className="w-full max-w-6xl mx-auto space-y-6">
      <div
        ref={containerRef}
        className="flex flex-col sm:flex-row items-center justify-center gap-3 sm:gap-0 px-2"
      >
        {/* Frame B - secondary, flanks left on tablet+, stacks below on mobile */}
        <div
          className="order-2 sm:order-1 w-[78%] sm:w-[38%] lg:w-[34%] self-end sm:self-auto -mt-10 sm:mt-0 sm:-mr-10 lg:-mr-20 sm:scale-[0.62] sm:opacity-75 sm:[transform:perspective(1200px)_rotateY(6deg)] transition-none"
          style={{ zIndex: 0 }}
        >
          <RoomFrame
            state={sim}
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
        <div className="order-1 sm:order-2 w-full sm:w-[44%] lg:w-[38%] relative z-10">
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
          className="hidden lg:block order-3 lg:w-[34%] lg:-ml-20 lg:scale-[0.62] lg:opacity-75 lg:[transform:perspective(1200px)_rotateY(-6deg)]"
          style={{ zIndex: 0 }}
        >
          <RoomFrame
            state={sim}
            offsetSec={offsets[2]}
            fidelity="reduced"
            identity={identity}
            videoRef={videoC}
            {...frameVideo}
            showHud={!reducedMotion}
          />
        </div>
      </div>

      <div className="flex flex-col items-center gap-6">
        <div className="flex flex-col items-center gap-2">
          <SyncToggle synced={phase === "synced"} onToggle={toggleSync} disabled={phase === "syncing"} />
          <p className="text-xs text-gray-500">Flip it - see what movie night looks like without us.</p>
        </div>
        <DownloadCTA />
      </div>
    </div>
  );
}
