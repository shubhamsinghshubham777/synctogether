import test from "node:test";
import assert from "node:assert/strict";
import {
  TOTAL_SECONDS,
  cancel,
  commit,
  formatTimecode,
  frameIndex,
  grab,
  hint,
  initialCtx,
  keyStep,
  moveHost,
  mounted,
  reachedPayoff,
  seatFrame,
  spokenTime,
  type ScrubCtx,
} from "../components/hero/scrub/machine.ts";

const TRACK = 500; // a typical rail width in px

/** A machine that has mounted and is hinting, as after the engine starts. */
const hinting = (): ScrubCtx => hint(mounted(initialCtx()));

test("timecodes match the boards", () => {
  assert.equal(formatTimecode(0), "0:00:00");
  assert.equal(formatTimecode(5061), "1:24:21");
  assert.equal(formatTimecode(7911), "2:11:51");
  assert.equal(formatTimecode(10143), "2:49:03");
  assert.equal(formatTimecode(-5), "0:00:00");
  assert.equal(formatTimecode(99999), "2:49:03");
  assert.equal(spokenTime(5061), "1 hour 24 minutes");
  assert.equal(spokenTime(3660), "1 hour 1 minute");
});

test("frameIndex picks one of the 11 frames", () => {
  assert.equal(frameIndex(0), 0);
  assert.equal(frameIndex(0.04), 0);
  assert.equal(frameIndex(0.06), 1);
  assert.equal(frameIndex(0.499), 5);
  assert.equal(frameIndex(0.95), 10);
  assert.equal(frameIndex(1), 10);
  assert.equal(frameIndex(-1), 0);
  assert.equal(frameIndex(2), 10);
});

test("the slider keys do what the spec says, and clamp", () => {
  const u = 1 / TOTAL_SECONDS;
  const near = (a: number | null, b: number) => assert.ok(a !== null && Math.abs(a - b) < 1e-12);
  near(keyStep("ArrowRight", false, 0.5), 0.5 + 60 * u);
  near(keyStep("ArrowLeft", false, 0.5), 0.5 - 60 * u);
  near(keyStep("ArrowUp", false, 0.5), 0.5 + 60 * u);
  near(keyStep("ArrowDown", false, 0.5), 0.5 - 60 * u);
  near(keyStep("ArrowRight", true, 0.5), 0.5 + 600 * u);
  near(keyStep("PageUp", false, 0.5), 0.5 + 900 * u);
  near(keyStep("PageDown", false, 0.5), 0.5 - 900 * u);
  assert.equal(keyStep("Home", false, 0.5), 0);
  assert.equal(keyStep("End", false, 0.5), 1);
  assert.equal(keyStep("ArrowLeft", true, 0.01), 0);
  assert.equal(keyStep("ArrowRight", true, 0.99), 1);
  assert.equal(keyStep("Tab", false, 0.5), null);
  assert.equal(keyStep("a", false, 0.5), null);
});

test("the extra payoff needs a real drag, and only once", () => {
  assert.equal(reachedPayoff(0.5, 0.5, TRACK, "pointer"), false);
  assert.equal(reachedPayoff(0.5, 0.5 + 23 / TRACK, TRACK, "pointer"), false, "a short tap or jiggle");
  assert.equal(reachedPayoff(0.5, 0.5 + 24 / TRACK, TRACK, "pointer"), true);
  assert.equal(reachedPayoff(0.5, 0.2, TRACK, "pointer"), true, "backwards counts");
  assert.equal(reachedPayoff(0.1, 0.9, TRACK, "pointer"), true, "a far tap counts");
  assert.equal(reachedPayoff(0.5, 0.52, TRACK, "key"), false);
  assert.equal(reachedPayoff(0.5, 0.53, TRACK, "key"), true);
  assert.equal(reachedPayoff(0.1, 0.9, TRACK, "pointer", true), false, "never once paid");
});

test("seats are never written during a drag", () => {
  let c = grab(hinting());
  const at = seatFrame(c);
  for (const p of [0.1, 0.3, 0.77, 0.99, 0.2]) {
    c = moveHost(c, p);
    assert.equal(seatFrame(c), at, "the seat frame is the committed one while dragging");
    assert.equal(c.committedP, initialCtx().committedP);
  }
  assert.equal(c.state, "dragging");
});

test("release commits: the seats jump to the host frame together", () => {
  let c = grab(hinting());
  c = moveHost(c, 0.78);
  const r = commit(c, TRACK, "pointer");
  assert.equal(r.kind, "commit");
  assert.equal(r.ctx.state, "settled");
  assert.equal(r.ctx.committedP, 0.78);
  assert.equal(seatFrame(r.ctx), frameIndex(0.78));
});

test("a tap far from the handle commits, and so does a 5 px drag", () => {
  let c = moveHost(grab(hinting()), 0.9);
  assert.equal(commit(c, TRACK, "pointer").kind, "commit");
  c = moveHost(grab(hinting()), 0.499 + 5 / TRACK);
  const r = commit(c, TRACK, "pointer");
  assert.equal(r.kind, "commit");
  assert.equal(r.payoff, false, "a 5 px drag commits but earns no extra payoff");
});

test("a 24 px+ drag commits and pays off once; the same again does not", () => {
  const first = commit(moveHost(grab(hinting()), 0.78), TRACK, "pointer");
  assert.equal(first.kind, "commit");
  assert.equal(first.payoff, true);
  assert.equal(first.ctx.paid, true);
  const second = commit(moveHost(grab(first.ctx), 0.2), TRACK, "pointer");
  assert.equal(second.kind, "commit");
  assert.equal(second.payoff, false, "the strip line and the ring never repeat");
  assert.equal(second.ctx.committedP, 0.2, "but every release still commits");
});

test("a release at the same spot is a no-op", () => {
  const c = grab(hinting());
  const r = commit(c, TRACK, "pointer");
  assert.equal(r.kind, "noop");
  assert.equal(r.payoff, false);
  assert.equal(r.ctx.committedP, c.committedP);
  assert.equal(r.ctx.state, "hinting", "back to the state before the press");
  const within = commit(moveHost(c, c.committedP + 0.5 / TRACK), TRACK, "pointer");
  assert.equal(within.kind, "noop", "within 1 px");
});

test("cancel reverts the host and sends nothing, from hinting and from settled", () => {
  // From hinting.
  let c = moveHost(grab(hinting()), 0.8);
  let k = cancel(c);
  assert.equal(k.hostP, initialCtx().committedP);
  assert.equal(k.committedP, initialCtx().committedP, "the seats never moved");
  assert.equal(k.state, "hinting");
  // From settled.
  const settled = commit(moveHost(grab(hinting()), 0.78), TRACK, "pointer").ctx;
  c = moveHost(grab(settled), 0.1);
  k = cancel(c);
  assert.equal(k.state, "settled", "returns to the state held before the drag");
  assert.equal(k.hostP, 0.78);
  assert.equal(k.committedP, 0.78);
});

test("a later cancel keeps the earlier commit, not the abandoned drag", () => {
  const first = commit(moveHost(grab(hinting()), 0.62), TRACK, "pointer").ctx;
  const abandoned = cancel(moveHost(grab(first), 0.05));
  assert.equal(abandoned.committedP, 0.62);
  assert.equal(abandoned.hostP, 0.62);
  assert.equal(seatFrame(abandoned), frameIndex(0.62));
});

test("cancel outside a drag changes nothing", () => {
  const c = hinting();
  assert.deepEqual(cancel(c), c);
  assert.deepEqual(commit(c, TRACK, "pointer").ctx, c);
});

test("a key burst is one drag: it commits once, with the 3% payoff", () => {
  let c = grab(hinting());
  let p = c.hostP;
  for (let i = 0; i < 6; i++) {
    p = keyStep("ArrowRight", true, p)!; // six Shift+arrows = 60 min
    c = moveHost(c, p);
  }
  assert.equal(c.state, "dragging");
  assert.equal(c.committedP, initialCtx().committedP, "the seats wait for the burst to end");
  const r = commit(c, TRACK, "key");
  assert.equal(r.kind, "commit");
  assert.equal(r.payoff, true);
  assert.equal(r.ctx.committedP, p);
  // A single arrow key is under 3% of the film: commits, no extra payoff.
  const small = commit(moveHost(grab(hinting()), keyStep("ArrowRight", false, 0.499)!), TRACK, "key");
  assert.equal(small.kind, "commit");
  assert.equal(small.payoff, false);
});

test("the state machine follows the spec's diagram", () => {
  let c = initialCtx();
  assert.equal(c.state, "static");
  assert.equal(grab(c).state, "static", "no grab before the engine mounts");
  c = mounted(c);
  assert.equal(c.state, "ready");
  assert.equal(mounted(c).state, "ready");
  c = hint(c);
  assert.equal(c.state, "hinting");
  assert.equal(hint(c).state, "hinting");
  const d = grab(c);
  assert.equal(d.state, "dragging");
  assert.equal(d.prevState, "hinting");
  assert.equal(grab(d), d, "a second grab while dragging is ignored");
  assert.equal(moveHost(c, 0.9).hostP, c.hostP, "moves outside a drag are ignored");
  assert.equal(grab(commit(moveHost(d, 0.7), TRACK, "pointer").ctx).state, "dragging", "grab again from settled");
});
