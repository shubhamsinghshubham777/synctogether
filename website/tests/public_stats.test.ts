import test from "node:test";
import assert from "node:assert/strict";
import { FLOORS, roundDown } from "../lib/public-metrics.ts";

function publishableFor(roomsAllTime: number, messagesSent: number, downloadsAllTime: number): boolean {
  return (
    roomsAllTime >= FLOORS.roomsAllTime &&
    messagesSent >= FLOORS.messagesSent &&
    downloadsAllTime >= FLOORS.downloadsAllTime
  );
}

test("rounding produces friendly, never-exact magnitudes", () => {
  assert.equal(roundDown(12437), "12,000+");
  assert.equal(roundDown(2000), "2,000+");
  assert.equal(roundDown(1999), "1,000+");
  assert.equal(roundDown(437), "400+");
  assert.equal(roundDown(0), "0+");
});

test("floor guard suppresses output when any single figure is short", () => {
  assert.equal(publishableFor(FLOORS.roomsAllTime, FLOORS.messagesSent, FLOORS.downloadsAllTime), true);
  assert.equal(publishableFor(FLOORS.roomsAllTime - 1, FLOORS.messagesSent, FLOORS.downloadsAllTime), false);
  assert.equal(publishableFor(FLOORS.roomsAllTime, FLOORS.messagesSent - 1, FLOORS.downloadsAllTime), false);
  assert.equal(publishableFor(FLOORS.roomsAllTime, FLOORS.messagesSent, FLOORS.downloadsAllTime - 1), false);
});

test("floor guard passes only when every figure clears its floor", () => {
  assert.equal(publishableFor(50000, 100000, 20000), true);
});
