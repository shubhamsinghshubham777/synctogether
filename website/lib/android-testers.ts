/**
 * The Android early-access waitlist (/android), as plain decisions over plain
 * values so the route, the card and the tests share one source of truth.
 *
 * The database holds the same rules (`android_testers` check constraints); the
 * checks here are what turn a bad value into a friendly answer instead of a 500.
 */

/** Where a sign-up came from. An allow-list, like `WEB_EVENT_NAMES`: never free text. */
export const ANDROID_SOURCES = ["android", "download", "join", "pair", "app"] as const;
export type AndroidSource = (typeof ANDROID_SOURCES)[number];

export function parseSource(value: unknown): AndroidSource {
  return typeof value === "string" && (ANDROID_SOURCES as readonly string[]).includes(value)
    ? (value as AndroidSource)
    : "android";
}

// Same shape as the table's check: something@something.tld, no spaces.
const EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

/** The address as it is stored (trimmed, lower-cased), or null when it is not one. */
export function normalizeEmail(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const email = value.trim().toLowerCase();
  if (email.length < 5 || email.length > 254) return null;
  return EMAIL.test(email) ? email : null;
}

/** Seats the first round aims for. Google asks for 12 testers; people drop off, so about double. */
export const DEFAULT_SEAT_TARGET = 25;

/** The target from `ANDROID_SEAT_TARGET`, clamped so a typo cannot make it absurd. */
export function seatTarget(raw: string | undefined): number {
  const n = Number.parseInt((raw ?? "").trim(), 10);
  if (!Number.isFinite(n)) return DEFAULT_SEAT_TARGET;
  return Math.min(500, Math.max(5, n));
}

/** Below this the strip hides: an almost empty row of seats reads as nobody caring. */
export const MIN_COUNTER_SEATS = 5;

export function counterVisible(taken: number): boolean {
  return taken >= MIN_COUNTER_SEATS;
}

export function seatsLeft(taken: number, target: number): number {
  return Math.max(0, target - taken);
}

/** The seat number as printed on the ticket stub: 06, 15, 112. */
export function seatLabel(seat: number): string {
  return String(seat).padStart(2, "0");
}

/** What the sign-up route answers. */
export type AndroidSignupResult =
  | { ok: true; state: "saved" | "already"; seat: number; taken: number; target: number }
  | { ok: false; error: "email" | "consent" | "captcha" | "server" };
