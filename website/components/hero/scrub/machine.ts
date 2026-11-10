/**
 * The pure half of the hero scrub (docs/hero-scrub-spec.md). No DOM, no
 * timers: the engine feeds it plain numbers and the unit tests drive it the
 * same way. Positions are fractions of the film, 0..1.
 *
 * It mirrors the app: while you scrub, only your own screen moves (the app
 * keeps a local `_dragValue` and `PTSlider` only calls `onChanged`); on
 * release one seek goes out and everyone lands on that frame together. So the
 * seats here are only ever written by `commit`, never while dragging.
 */

/** The film's length in seconds (the "2:49:03" the boards show). */
export const TOTAL_SECONDS = 10143;
/** Frames in the filmstrip. */
export const FRAME_COUNT = 11;
/** Where the playhead rests before anyone touches it: 1:24:21. */
export const START_SECONDS = 5061;

/** A pointer drag must move the playhead this many px for the extra payoff. */
export const PAYOFF_PX = 24;
/** A keyboard burst must move it this fraction of the film. */
export const PAYOFF_KEY_FRACTION = 0.03;
/** A release within this many px of the committed position commits nothing. */
export const NOOP_PX = 1;
/** Keyboard: the burst commits this long after the last key. */
export const KEY_COMMIT_MS = 250;

export type ScrubState = "static" | "ready" | "hinting" | "dragging" | "settled";

export const clamp01 = (n: number) => (n < 0 ? 0 : n > 1 ? 1 : n);

/** `5061` -> `1:24:21`. Whole seconds; clamps to the film. */
export function formatTimecode(seconds: number): string {
  const s = Math.max(0, Math.min(TOTAL_SECONDS, Math.round(seconds)));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  return `${h}:${String(m).padStart(2, "0")}:${String(sec).padStart(2, "0")}`;
}

/** Spoken form for `aria-valuetext`. */
export function spokenTime(seconds: number): string {
  const s = Math.max(0, Math.min(TOTAL_SECONDS, Math.round(seconds)));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const part = (n: number, unit: string) => `${n} ${unit}${n === 1 ? "" : "s"}`;
  return `${part(h, "hour")} ${part(m, "minute")}`;
}

/** Which of the 11 frames a position shows. */
export function frameIndex(p: number): number {
  return Math.max(0, Math.min(FRAME_COUNT - 1, Math.round(clamp01(p) * (FRAME_COUNT - 1))));
}

/**
 * The slider's keys (ARIA slider pattern). Returns the new position, or null
 * when the key is not ours. Arrow = 60 s, Shift+arrow = 10 min, PageUp/Down =
 * 15 min, Home/End = the ends.
 */
export function keyStep(key: string, shift: boolean, p: number): number | null {
  const unit = 1 / TOTAL_SECONDS;
  let delta: number;
  switch (key) {
    case "ArrowLeft":
    case "ArrowDown":
      delta = -(shift ? 600 : 60) * unit;
      break;
    case "ArrowRight":
    case "ArrowUp":
      delta = (shift ? 600 : 60) * unit;
      break;
    case "PageDown":
      delta = -900 * unit;
      break;
    case "PageUp":
      delta = 900 * unit;
      break;
    case "Home":
      return 0;
    case "End":
      return 1;
    default:
      return null;
  }
  return clamp01(p + delta);
}

/**
 * Did this release earn the one-shot payoff (the strip line and the CTA ring)?
 * A pointer drag counts when the playhead moved at least 24 px from where the
 * drag began (a far tap counts, a short tap or a jiggle does not); a keyboard
 * burst counts at 3% of the film. Never once it has been paid.
 */
export function reachedPayoff(
  dragStartP: number,
  hostP: number,
  trackPx: number,
  via: "pointer" | "key",
  paid = false,
): boolean {
  if (paid) return false;
  const moved = Math.abs(hostP - dragStartP);
  return via === "key" ? moved >= PAYOFF_KEY_FRACTION : moved * trackPx >= PAYOFF_PX;
}

// ---- the machine: a context and the transitions between states -----------

export interface ScrubCtx {
  state: ScrubState;
  /** Last committed position. This is where the seats are. */
  committedP: number;
  /** The host's position (moves live while dragging). */
  hostP: number;
  /** `committedP` when the current drag began (the 24 px test measures from it). */
  dragStartP: number;
  /** The state held before the drag, which a cancel returns to. */
  prevState: ScrubState;
  /** The strip line and ring have fired this page view. */
  paid: boolean;
}

export function initialCtx(): ScrubCtx {
  const p = START_SECONDS / TOTAL_SECONDS;
  return { state: "static", committedP: p, hostP: p, dragStartP: p, prevState: "static", paid: false };
}

/** The frame every seat shows. Seats only ever show the committed position. */
export const seatFrame = (c: ScrubCtx) => frameIndex(c.committedP);

export function mounted(c: ScrubCtx): ScrubCtx {
  return c.state === "static" ? { ...c, state: "ready" } : c;
}

export function hint(c: ScrubCtx): ScrubCtx {
  return c.state === "ready" ? { ...c, state: "hinting" } : c;
}

/** A pointerdown or a handled key: a local scrub begins. The seats do not move. */
export function grab(c: ScrubCtx): ScrubCtx {
  if (c.state === "static" || c.state === "dragging") return c;
  return { ...c, state: "dragging", prevState: c.state, dragStartP: c.committedP, hostP: c.committedP };
}

/** The pointer or a key moved the host. Only the host; never the seats. */
export function moveHost(c: ScrubCtx, p: number): ScrubCtx {
  return c.state === "dragging" ? { ...c, hostP: clamp01(p) } : c;
}

export interface CommitResult {
  ctx: ScrubCtx;
  /** `commit`: seats jump and flash. `noop`: nothing to show, nothing flashes. */
  kind: "commit" | "noop";
  /** The one-shot strip line and ring. */
  payoff: boolean;
}

/**
 * A release (or the end of a key burst). Always commits, even a short tap,
 * because that is what the app does; the exception is a release within 1 px of
 * the committed position, which the app would send as an identical seek and
 * which has nothing to show.
 */
export function commit(c: ScrubCtx, trackPx: number, via: "pointer" | "key"): CommitResult {
  if (c.state !== "dragging") return { ctx: c, kind: "noop", payoff: false };
  if (Math.abs(c.hostP - c.committedP) * trackPx < NOOP_PX) {
    return { ctx: { ...c, state: c.prevState, hostP: c.committedP }, kind: "noop", payoff: false };
  }
  const payoff = reachedPayoff(c.dragStartP, c.hostP, trackPx, via, c.paid);
  return {
    ctx: { ...c, state: "settled", committedP: c.hostP, paid: c.paid || payoff },
    kind: "commit",
    payoff,
  };
}

/**
 * pointercancel, window blur, a hidden tab or a blur before a key commit:
 * the host returns to the committed position and nothing is sent. The seats
 * never moved, so there is nothing to undo there.
 */
export function cancel(c: ScrubCtx): ScrubCtx {
  return c.state === "dragging" ? { ...c, state: c.prevState, hostP: c.committedP } : c;
}
