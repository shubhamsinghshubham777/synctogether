/**
 * The hero scrub engine (design canvas boards 74-81). Plain TypeScript, no React:
 * it only changes attributes, `style.transform` and the text of nodes the
 * server already rendered, so React's tree is never disturbed.
 *
 * It does what the app does. While you drag, only the host screen and the
 * playhead move (nothing is "sent"); on release everyone lands on that frame
 * together. The seats are written in exactly one place, `commitSeats`, and
 * never while a drag is live. Every decision lives in `machine.ts`.
 */
import {
  FRAME_COUNT,
  KEY_COMMIT_MS,
  TOTAL_SECONDS,
  cancel,
  commit,
  formatTimecode,
  frameIndex,
  grab,
  hint,
  initialCtx,
  keyStep,
  mounted,
  moveHost,
  seatFrame,
  spokenTime,
  type ScrubCtx,
} from "./machine";

export type ScrubEventName = "hero_scrub_start" | "hero_scrub_synced";

export interface MountOptions {
  reducedMotion: boolean;
  onEvent(name: ScrubEventName): void;
  /** A press that landed before the engine loaded; handed over if still down. */
  pending?: PointerEvent | null;
}

const NUDGE_FIRST_MS = 1200;
const NUDGE_LEN_MS = 760;
// The gap after a nudge ends, so one starts every 2 s (760 ms lean + 1240 ms rest)
// for as long as the chip is idle.
const NUDGE_GAP_MS = 2000 - NUDGE_LEN_MS;
const REVERT_MS = 160;
const ANNOUNCE_GAP_MS = 1500;

const HEADER = { idle: "IN SYNC · 4 SEATS", drag: "SCRUBBING · 4 SEATS WAIT" } as const;

export function mount(root: HTMLElement, opts: MountOptions): () => void {
  const q = <T extends HTMLElement>(selector: string) => root.querySelector<T>(selector);
  const zone = q("[data-zone]");
  const carriage = q("[data-carriage]");
  const fill = q("[data-fill]");
  const tick = q("[data-tick]");
  const handle = q("[data-handle]");
  const nudgeEl = q(".scrub-nudge");
  const timeEl = q("[data-time]");
  const chipTime = q("[data-chip-time]");
  const stateEl = q("[data-scrub-state]");
  const live = q("[data-live]");
  const stripEl = q("[data-copy]");
  const strips = Array.from(root.querySelectorAll<HTMLElement>("[data-strip]")); // 0 host, 1..3 seats
  const tiles = Array.from(root.querySelectorAll<HTMLElement>("[data-seat]"));
  if (!zone || !carriage || !fill || !tick || !handle || !nudgeEl || strips.length !== 4 || tiles.length !== 3) {
    return () => {};
  }

  const html = document.documentElement;
  let reduced = opts.reducedMotion;
  let c: ScrubCtx = initialCtx();
  const frames = [-1, -1, -1, -1];

  let rect = zone.getBoundingClientRect();
  let pointerId: number | null = null;
  let pendingX: number | null = null;
  let via: "pointer" | "key" = "pointer";
  let raf = 0;
  let keyTimer = 0;
  let nudgesPlayed = 0;
  let nudgeTimer = 0;
  let nudgeEndTimer = 0;
  let activeTimer = 0;
  let revertTimer = 0;
  let landed = false; // alternates a/b so a new commit restarts the flash, never stacks
  let lastAnnounceAt = 0;
  let started = false;
  let syncedSent = false;
  let announcedScrub = false;
  let onScreen = true;
  let hidden = document.visibilityState === "hidden";

  const setState = (next: ScrubCtx) => {
    c = next;
    root.dataset.state = c.state;
  };

  // ---- text and attributes ------------------------------------------------

  const announce = (text: string) => {
    if (live) live.textContent = text;
  };
  const setCopy = (kind: "idle" | "drag" | "synced") => {
    if (stripEl) stripEl.dataset.copy = kind;
  };
  const setSeats = (status: "sync" | "wait") => {
    for (const tile of tiles) {
      if (tile.dataset.seat === status) continue;
      tile.dataset.seat = status;
      const name = tile.dataset.name ?? "";
      tile.setAttribute(
        "aria-label",
        `${name}, simulated, ${status === "wait" ? "waiting for you to let go" : "in sync"}`,
      );
    }
  };
  const updateAria = (p: number) => {
    const s = Math.round(p * TOTAL_SECONDS);
    handle.setAttribute("aria-valuenow", String(s));
    handle.setAttribute(
      "aria-valuetext",
      `${spokenTime(s)} of 2 hours 49 minutes. Maya, Dev and Kai catch up when you let go.`,
    );
  };
  /** Header, strip line and seat chips for the state the visitor is looking at. */
  const settleText = () => {
    if (stateEl) stateEl.textContent = HEADER.idle;
    setCopy(c.paid ? "synced" : "idle");
    setSeats("sync");
  };

  // ---- rendering (transform and text only, no layout reads) ---------------

  const writeFrame = (i: number, idx: number) => {
    if (frames[i] === idx) return;
    frames[i] = idx;
    strips[i].style.transform = `translate3d(${(-idx * 100) / FRAME_COUNT}%,0,0)`;
  };
  const renderHost = () => {
    const p = c.hostP;
    carriage.style.transform = `translateX(${p * 100}%)`;
    fill.style.transform = `scaleX(${p})`;
    writeFrame(0, frameIndex(p));
    const t = formatTimecode(p * TOTAL_SECONDS);
    if (timeEl && timeEl.textContent !== t) timeEl.textContent = t;
    if (chipTime && chipTime.textContent !== t) chipTime.textContent = t;
  };
  /** The one place the seats are written: all three, in the same frame. */
  const commitSeats = () => {
    const idx = seatFrame(c);
    writeFrame(1, idx);
    writeFrame(2, idx);
    writeFrame(3, idx);
    tick.style.transform = `translateX(${c.committedP * 100}%)`;
  };

  // ---- one write per frame while a pointer moves ---------------------------

  const flush = () => {
    raf = 0;
    if (pendingX === null) return;
    setState(moveHost(c, (pendingX - rect.left) / rect.width));
    pendingX = null;
    renderHost();
  };
  const queueMove = (clientX: number) => {
    pendingX = clientX;
    if (!raf) raf = requestAnimationFrame(flush);
  };
  const stopFrame = () => {
    if (raf) cancelAnimationFrame(raf);
    raf = 0;
  };

  // ---- hint nudges: a lean-and-back every 2 s while the chip is idle ------
  // Before the first drag and again after every release; never while dragging,
  // never under reduced motion, paused when the hero is off screen or the tab is hidden.

  const clearNudge = () => {
    window.clearTimeout(nudgeTimer);
    window.clearTimeout(nudgeEndTimer);
    nudgeTimer = nudgeEndTimer = 0;
    delete nudgeEl.dataset.nudge;
  };
  const nudgeable = () => (c.state === "hinting" || c.state === "settled") && !reduced && !hidden && onScreen;
  const armNudge = (delay = nudgesPlayed === 0 ? NUDGE_FIRST_MS : NUDGE_GAP_MS) => {
    window.clearTimeout(nudgeTimer);
    if (!nudgeable()) return;
    nudgeTimer = window.setTimeout(
      () => {
        if (!nudgeable()) return;
        nudgesPlayed++;
        nudgeEl.dataset.nudge = "1";
        nudgeEndTimer = window.setTimeout(() => {
          delete nudgeEl.dataset.nudge;
          armNudge();
        }, NUDGE_LEN_MS);
      },
      delay,
    );
  };

  // ---- the drag: local only, then commit or cancel --------------------------

  const markActive = () => {
    window.clearTimeout(activeTimer);
    root.dataset.active = "1";
  };
  const releaseActive = () => {
    window.clearTimeout(activeTimer);
    activeTimer = window.setTimeout(() => delete root.dataset.active, 300);
  };

  const begin = (how: "pointer" | "key", trusted: boolean) => {
    via = how;
    clearNudge(); // a drag in progress is never nudged; it resumes after the release
    window.clearTimeout(keyTimer);
    window.clearTimeout(revertTimer);
    delete root.dataset.reverting;
    setState(grab(c));
    markActive();
    if (stateEl) stateEl.textContent = HEADER.drag;
    setCopy("drag");
    setSeats("wait"); // the seats hold their frame and say so
    if (!started && trusted) {
      started = true;
      opts.onEvent("hero_scrub_start");
    }
    if (!announcedScrub) {
      announcedScrub = true;
      announce("Scrubbing. Maya, Dev and Kai wait until you let go.");
    }
  };

  /** A release, or the end of a key burst. */
  const release = () => {
    window.clearTimeout(keyTimer);
    if (c.state !== "dragging") return;
    const result = commit(c, rect.width, via);
    setState(result.ctx);
    if (result.kind === "commit") {
      commitSeats();
      // A new commit restarts the flash and pop (two keyframe sets, alternated).
      landed = !landed;
      if (!reduced) root.dataset.landed = landed ? "a" : "b";
      updateAria(c.committedP);
      const now = performance.now();
      if (now - lastAnnounceAt >= ANNOUNCE_GAP_MS) {
        lastAnnounceAt = now;
        announce(`Let go. All four screens are on ${formatTimecode(c.committedP * TOTAL_SECONDS)}.`);
      }
      if (!syncedSent) {
        syncedSent = true;
        opts.onEvent("hero_scrub_synced");
      }
      if (result.payoff) {
        html.dataset.scrubPaid = "1"; // drives the CTA ring, once
        announce("Everyone landed on your frame. This was a demo room; the real one is free.");
      }
    } else {
      renderHost(); // a no-op press: the host is back on the committed position
    }
    settleText();
    releaseActive();
    armNudge(NUDGE_GAP_MS);
  };

  /** pointercancel, blur, a hidden tab, scrolling away: the host goes back, nothing is sent. */
  const abort = () => {
    window.clearTimeout(keyTimer);
    pointerId = null;
    pendingX = null;
    stopFrame();
    if (c.state !== "dragging") return;
    setState(cancel(c));
    if (!reduced) {
      root.dataset.reverting = "1"; // a 160 ms CSS ease for the revert only
      window.clearTimeout(revertTimer);
      revertTimer = window.setTimeout(() => delete root.dataset.reverting, REVERT_MS + 20);
    }
    renderHost();
    updateAria(c.committedP);
    settleText();
    releaseActive();
    armNudge(NUDGE_GAP_MS);
  };

  // ---- pointer ---------------------------------------------------------------

  const onPointerDown = (e: PointerEvent) => {
    if (pointerId !== null) return; // multi-touch: only the first pointer
    if (e.pointerType === "mouse" && e.button !== 0) return;
    rect = zone.getBoundingClientRect();
    try {
      zone.setPointerCapture(e.pointerId);
    } catch {
      return; // already up (a press handed over late): not a drag
    }
    pointerId = e.pointerId;
    if (e.pointerType === "mouse") e.preventDefault(); // no text selection
    if (c.state === "dragging" && via === "key") release(); // keep the key burst's move
    begin("pointer", e.isTrusted);
    queueMove(e.clientX); // click-to-seek: the host jumps to the pointer
  };
  const onPointerMove = (e: PointerEvent) => {
    if (e.pointerId === pointerId) queueMove(e.clientX);
  };
  const onPointerUp = (e: PointerEvent) => {
    if (e.pointerId !== pointerId) return;
    // The final position counts even if no frame ran after the last move.
    stopFrame();
    setState(moveHost(c, (e.clientX - rect.left) / rect.width));
    pendingX = null;
    pointerId = null;
    renderHost();
    release();
  };
  const onPointerEnd = (e: PointerEvent) => {
    if (e.pointerId === pointerId) abort();
  };

  // ---- keyboard --------------------------------------------------------------

  const onKeyDown = (e: KeyboardEvent) => {
    if (e.ctrlKey || e.metaKey || e.altKey) return;
    const next = keyStep(e.key, e.shiftKey, c.state === "dragging" ? c.hostP : c.committedP);
    if (next === null) return;
    e.preventDefault();
    if (c.state !== "dragging") begin("key", e.isTrusted);
    else via = "key";
    setState(moveHost(c, next));
    renderHost();
    updateAria(c.hostP); // keys update the slider's value on every press
    window.clearTimeout(keyTimer);
    keyTimer = window.setTimeout(release, KEY_COMMIT_MS); // seats jump once, at the end of the burst
  };
  const onBlur = () => {
    if (via === "key" && c.state === "dragging") abort();
  };

  // ---- the page around it ------------------------------------------------------

  const onVisibility = () => {
    hidden = document.visibilityState === "hidden";
    if (hidden) {
      abort(); // mid-drag a hidden tab is a cancel
      clearNudge();
    } else {
      armNudge();
    }
  };
  const onWindowBlur = () => abort();
  const onPageShow = (e: PageTransitionEvent) => {
    if (!e.persisted) return;
    abort();
    setState({ ...c, hostP: c.committedP });
    renderHost();
    commitSeats();
  };

  const io = new IntersectionObserver(
    (entries) => {
      onScreen = entries[entries.length - 1].isIntersecting;
      if (!onScreen) {
        abort(); // scrolled away mid-drag is a cancel
        clearNudge();
      } else {
        armNudge();
      }
    },
    { threshold: 0.1 },
  );
  const ro = new ResizeObserver(() => {
    rect = zone.getBoundingClientRect(); // the playhead keeps its fraction
  });
  const mq = window.matchMedia("(prefers-reduced-motion: reduce)");
  const onMotion = (e: MediaQueryListEvent) => {
    reduced = e.matches;
    root.dataset.reduced = String(reduced);
    if (reduced) clearNudge();
    else armNudge();
  };

  // ---- go ----------------------------------------------------------------------

  root.dataset.enhanced = "1";
  root.dataset.reduced = String(reduced);
  renderHost();
  commitSeats();
  updateAria(c.committedP);
  setSeats("sync");
  setState(mounted(c));

  zone.addEventListener("pointerdown", onPointerDown);
  zone.addEventListener("pointermove", onPointerMove);
  zone.addEventListener("pointerup", onPointerUp);
  zone.addEventListener("pointercancel", onPointerEnd);
  zone.addEventListener("lostpointercapture", onPointerEnd);
  handle.addEventListener("keydown", onKeyDown);
  handle.addEventListener("blur", onBlur);
  document.addEventListener("visibilitychange", onVisibility);
  window.addEventListener("blur", onWindowBlur);
  window.addEventListener("pageshow", onPageShow);
  mq.addEventListener("change", onMotion);
  io.observe(root);
  ro.observe(zone);

  setState(hint(c));
  armNudge();

  // A press that beat the engine: hand it over if the pointer is still down.
  if (opts.pending && opts.pending.isTrusted) onPointerDown(opts.pending);

  return () => {
    clearNudge();
    stopFrame();
    window.clearTimeout(keyTimer);
    window.clearTimeout(activeTimer);
    window.clearTimeout(revertTimer);
    zone.removeEventListener("pointerdown", onPointerDown);
    zone.removeEventListener("pointermove", onPointerMove);
    zone.removeEventListener("pointerup", onPointerUp);
    zone.removeEventListener("pointercancel", onPointerEnd);
    zone.removeEventListener("lostpointercapture", onPointerEnd);
    handle.removeEventListener("keydown", onKeyDown);
    handle.removeEventListener("blur", onBlur);
    document.removeEventListener("visibilitychange", onVisibility);
    window.removeEventListener("blur", onWindowBlur);
    window.removeEventListener("pageshow", onPageShow);
    mq.removeEventListener("change", onMotion);
    io.disconnect();
    ro.disconnect();
    delete html.dataset.scrubPaid; // the CTA ring must not replay on another page
    delete root.dataset.active;
    delete root.dataset.landed;
    delete root.dataset.reverting;
  };
}
