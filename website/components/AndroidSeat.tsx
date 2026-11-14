"use client";

import { useEffect, useId, useRef, useState } from "react";
import { Check, ExternalLink, Share2, Smartphone } from "lucide-react";
import { Turnstile, type TurnstileHandle } from "@/components/Turnstile";
import { display, mono } from "@/components/PageHead";
import {
  counterVisible,
  parseSource,
  seatLabel,
  normalizeEmail,
  seatsLeft,
  type AndroidSignupResult,
  type AndroidSource,
} from "@/lib/android-testers";

type Counts = { taken: number; target: number };
type Saved = { email: string; seat: number; state: "saved" | "already" };

const STORAGE_KEY = "st_android_seat";

// A seat survives a reload: the card opens on the ticket instead of asking again.
// Storage can be blocked (private window, cleared site data), so every touch is guarded.
function readSaved(): Saved | null {
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    const v = JSON.parse(raw) as Saved;
    return typeof v.email === "string" && typeof v.seat === "number" ? v : null;
  } catch {
    return null;
  }
}
function writeSaved(v: Saved) {
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(v));
  } catch {
    // Blocked storage: the card still shows the ticket this visit.
  }
}
function forgetSaved() {
  try {
    window.localStorage.removeItem(STORAGE_KEY);
  } catch {
    // Nothing stored, nothing to forget.
  }
}

const kicker = `${mono} text-[11px] tracking-[0.14em] uppercase`;

/** The seat strip: filled seats in Beam because they are live. */
function SeatStrip({ taken, target, compact }: Counts & { compact: boolean }) {
  const shown = Math.min(taken, target);
  return (
    <div className="flex flex-col gap-2.5">
      <div className="flex items-baseline justify-between gap-3">
        <p className={`${kicker} text-gray-500`}>
          <span className="text-white">{taken}</span> of {target} seats taken
        </p>
        <p className={`${mono} text-[11px] tracking-[0.08em] uppercase text-gray-500`}>
          {seatsLeft(taken, target)} to go
        </p>
      </div>
      <div
        className={`flex flex-wrap ${compact ? "gap-[2px]" : "gap-1"}`}
        role="img"
        aria-label={`${shown} of ${target} seats taken`}
      >
        {Array.from({ length: target }, (_, i) => (
          <span
            key={i}
            className={`${compact ? "h-2.5 w-2.5" : "h-3.5 w-3.5"} rounded-[2px] box-border ${
              i < shown ? "bg-beam-500" : "border border-[#5A4F44]"
            }`}
          />
        ))}
      </div>
    </div>
  );
}

function SeatTicket({ seat, title, sub }: { seat: number; title: string; sub: string }) {
  return (
    <div className="ticket ticket-print flex h-32 bg-screen text-booth rounded-md">
      <div className="flex-1 min-w-0 flex flex-col justify-between py-[18px] pl-6 pr-3">
        <p className={`${mono} text-[10px] tracking-[0.14em] uppercase text-[#A33A22]`}>Admit one</p>
        <p className={`${display} text-[21px] font-extrabold tracking-[-0.035em] leading-[0.98]`}>{title}</p>
        <p className="text-[13px] leading-snug text-[#5A4F44]">{sub}</p>
      </div>
      <div className="w-[84px] shrink-0 border-l-2 border-dashed border-[#B8AB98] flex flex-col items-center justify-center gap-0.5">
        <span className={`${mono} text-[10px] tracking-[0.14em] uppercase text-[#5A4F44]`}>Seat</span>
        <span className={`${mono} text-[28px] font-semibold tracking-[0.04em]`}>{seatLabel(seat)}</span>
      </div>
    </div>
  );
}

const outlineBtn =
  "inline-flex items-center justify-center gap-2.5 h-12 px-5 rounded-[4px] text-[15px] font-semibold text-white border border-[#5A4F44] hover:border-gray-500 transition-colors cursor-pointer";

/**
 * The Android early-access card. Google Play opens a new app only after a closed
 * group has tested it for 14 days, so this is the list those testers come from.
 *
 * `counts` is passed by server pages that already read it; a client-rendered
 * parent (the /join launcher) omits it and the card fetches the same numbers.
 * `playUrl` is set once the test exists, and turns the card into the opt-in steps.
 */
export function AndroidSeat({
  source = "android",
  counts: initial,
  playUrl = null,
  compact = false,
}: {
  source?: AndroidSource;
  counts?: Counts;
  playUrl?: string | null;
  compact?: boolean;
}) {
  const uid = useId();
  const [counts, setCounts] = useState<Counts | null>(initial ?? null);
  const [saved, setSaved] = useState<Saved | null>(null);
  const [email, setEmail] = useState("");
  const [consent, setConsent] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [shared, setShared] = useState(false);
  const turnstile = useRef<TurnstileHandle | null>(null);

  useEffect(() => {
    // Reading localStorage is a post-hydration step: the server HTML is the form.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setSaved(readSaved());
  }, []);

  useEffect(() => {
    if (initial) return;
    let live = true;
    fetch("/api/android")
      .then((r) => (r.ok ? (r.json() as Promise<Counts>) : null))
      .then((c) => live && c && setCounts(c))
      .catch(() => {
        // No count is fine: the strip just stays hidden.
      });
    return () => {
      live = false;
    };
  }, [initial]);

  const emailOk = normalizeEmail(email) !== null;

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (busy) return;
    setError(null);
    if (!emailOk) {
      setError("Hmm, that doesn't look like a full email address.");
      return;
    }
    if (!consent) {
      setError("Tick the box so we know you'll keep it installed.");
      return;
    }
    setBusy(true);
    try {
      const token = await turnstile.current?.execute().catch(() => "");
      // The app's link carries ?from=app; the page itself is cached, so read it here.
      const from = new URLSearchParams(window.location.search).get("from");
      const res = await fetch("/api/android", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          email,
          consent: true,
          token,
          source: from === "app" ? "app" : parseSource(source),
        }),
      });
      const out = (await res.json().catch(() => null)) as AndroidSignupResult | null;
      if (out?.ok) {
        const next: Saved = { email: email.trim().toLowerCase(), seat: out.seat, state: out.state };
        writeSaved(next);
        setSaved(next);
        setCounts({ taken: out.taken, target: out.target });
      } else if (out && !out.ok && out.error === "email") {
        setError("Hmm, that doesn't look like a full email address.");
      } else if (out && !out.ok && out.error === "captcha") {
        setError("The security check didn't go through. Give it another try.");
      } else {
        setError("Hmm, that didn't save. Try again in a moment.");
      }
    } catch {
      setError("Hmm, we couldn't reach the box office. Check your connection and try again.");
    } finally {
      setBusy(false);
      turnstile.current?.reset();
    }
  };

  const share = async () => {
    const url = `${window.location.origin}/android`;
    try {
      if (navigator.share) {
        await navigator.share({ title: "SyncTogether on Android", url });
        return;
      }
      await navigator.clipboard.writeText(url);
      setShared(true);
      window.setTimeout(() => setShared(false), 2000);
    } catch {
      // A dismissed share sheet rejects; the card stays as it was.
    }
  };

  const pad = compact ? "p-5" : "p-6 sm:p-8";
  const shell = `flex flex-col gap-5 rounded-md border border-rail bg-seat ${pad}`;

  // The test exists: opt in on Google Play.
  if (playUrl) {
    return (
      <div className={shell}>
        <p className={`${kicker} flex items-center gap-2.5 text-beam-500`}>
          <span className="h-2 w-2 rounded-full bg-beam-500 shadow-[0_0_10px_var(--color-beam-500)]" aria-hidden="true" />
          Test is open
        </p>
        <div className="flex flex-col gap-2.5">
          <h2 className={`${display} text-[32px] font-extrabold tracking-[-0.035em] leading-[0.96] text-white`}>
            Your seat is ready.
          </h2>
          <p className="text-[15px] leading-[1.55] text-gray-400">
            On your Android phone, signed in as the address you gave us: opt in, then install from Google Play.
          </p>
        </div>
        <ol className="border-t border-aisle">
          {["Tap Become a tester", "Install from Google Play", "Keep it for 14 days, then it's public"].map((t, i) => (
            <li key={t} className="flex gap-4 border-b border-aisle py-3 text-[15px] text-white">
              <span className={`${mono} text-gray-500`}>0{i + 1}</span>
              <span>{t}</span>
            </li>
          ))}
        </ol>
        <a
          href={playUrl}
          className="btn-primary-gradient inline-flex items-center justify-center gap-2.5 h-[52px] px-6 rounded-[4px] text-base font-semibold cursor-pointer"
        >
          <ExternalLink className="h-[18px] w-[18px]" aria-hidden="true" />
          Opt in on Google Play
        </a>
        <p className="text-xs leading-normal text-gray-500">
          Seats are full for this round. New sign-ups wait for the public launch.
        </p>
      </div>
    );
  }

  // A seat is held: the ticket.
  if (saved) {
    const already = saved.state === "already";
    return (
      <div className={shell}>
        <p className={`${kicker} flex items-center gap-2.5 text-cue`}>
          <Check className="h-[18px] w-[18px]" strokeWidth={2.2} aria-hidden="true" />
          {already ? "Already on the list" : "Seat saved"}
        </p>
        <SeatTicket
          seat={saved.seat}
          title={already ? "Good news, you're in." : "You're on the list."}
          sub={already ? `Already holds seat ${seatLabel(saved.seat)}.` : `Link goes to ${saved.email}.`}
        />
        <p className="text-[15px] leading-[1.55] text-gray-400">
          {already
            ? "No need to sign up twice. Your seat stays yours until the test opens."
            : "When the last seat fills we open the test and send you the link. It usually takes a few weeks. Until then, nothing to do."}
        </p>
        {counts && counterVisible(counts.taken) && <SeatStrip {...counts} compact={compact} />}
        {already ? (
          <button
            type="button"
            onClick={() => {
              forgetSaved();
              setSaved(null);
              setEmail("");
              setConsent(false);
            }}
            className="self-start text-sm font-medium text-beam-400 hover:text-beam-300 cursor-pointer"
          >
            Use a different address
          </button>
        ) : (
          <button type="button" onClick={share} className={outlineBtn}>
            {shared ? <Check className="h-[18px] w-[18px]" aria-hidden="true" /> : <Share2 className="h-[18px] w-[18px]" aria-hidden="true" />}
            <span aria-live="polite">{shared ? "Link copied" : "Share with someone on Android"}</span>
          </button>
        )}
      </div>
    );
  }

  // The form.
  const emailId = `${uid}-email`;
  const tickId = `${uid}-tick`;
  return (
    <form onSubmit={submit} noValidate className={shell}>
      <div className="flex items-center justify-between">
        <p className={`${kicker} text-beam-500`}>Android test · Free</p>
        <Smartphone className="h-[22px] w-[22px] text-gray-500" strokeWidth={1.5} aria-hidden="true" />
      </div>
      <div className="flex flex-col gap-2.5">
        <h2
          className={`${display} font-extrabold tracking-[-0.035em] leading-[0.96] text-white ${
            compact ? "text-2xl" : "text-[32px]"
          }`}
        >
          {compact ? "Android is in testing" : "Save your seat"}
        </h2>
        <p className={`leading-[1.55] text-gray-400 ${compact ? "text-sm" : "text-[15px]"}`}>
          {compact
            ? "Save a seat and we'll email you the Google Play link when the test opens."
            : "Google opens the Play Store to a new app only after real people test it for 14 days. Put your name down and you're one of them, free."}
        </p>
      </div>
      {counts && counterVisible(counts.taken) && <SeatStrip {...counts} compact={compact} />}
      <div className="flex flex-col gap-2">
        <label htmlFor={emailId} className="text-sm font-semibold text-white">
          Gmail on your Android phone
        </label>
        <input
          id={emailId}
          type="email"
          inputMode="email"
          autoComplete="email"
          autoCapitalize="none"
          spellCheck={false}
          placeholder="you@gmail.com"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          aria-invalid={error ? true : undefined}
          aria-describedby={error ? `${uid}-err` : undefined}
          className={`h-12 w-full rounded-[4px] bg-booth px-3.5 text-base text-white placeholder:text-gray-500 border ${
            error ? "border-signal" : "border-rail"
          } focus:outline-none focus:border-beam-500`}
        />
        {error && (
          <p id={`${uid}-err`} role="alert" className="text-[13px] text-[#FF8A70]">
            {error}
          </p>
        )}
      </div>
      <label htmlFor={tickId} className="flex cursor-pointer items-start gap-3 text-sm leading-[1.45] text-gray-300">
        <input
          id={tickId}
          type="checkbox"
          checked={consent}
          onChange={(e) => setConsent(e.target.checked)}
          className="peer sr-only"
        />
        <span
          aria-hidden="true"
          className="mt-px flex h-5 w-5 shrink-0 items-center justify-center rounded-[4px] border border-[#5A4F44] text-booth peer-checked:border-beam-500 peer-checked:bg-beam-500 peer-focus-visible:ring-2 peer-focus-visible:ring-beam-500/60 [&>svg]:opacity-0 peer-checked:[&>svg]:opacity-100"
        >
          <Check className="h-3.5 w-3.5" strokeWidth={2.5} />
        </span>
        <span>I&apos;ll keep it installed for the 14-day test.</span>
      </label>
      <button
        type="submit"
        disabled={busy || !emailOk}
        className="btn-primary-gradient inline-flex h-[52px] items-center justify-center rounded-[4px] px-6 text-base font-semibold cursor-pointer disabled:opacity-60"
      >
        <span aria-live="polite">{busy ? "Saving your seat…" : "Save my seat"}</span>
      </button>
      <p className="text-xs leading-normal text-gray-500">
        Only used to invite you on Google Play. No newsletter, and you can drop out any time.
      </p>
      <Turnstile ref={turnstile} />
    </form>
  );
}
