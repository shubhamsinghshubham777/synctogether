"use client";

import {
  useCallback,
  useEffect,
  useRef,
  useState,
  useSyncExternalStore,
} from "react";
import type React from "react";
import Link from "next/link";
import { Check, Download, Mail } from "lucide-react";
import { Ticket } from "@/components/Ticket";
import { JoinStamp } from "@/components/JoinStamp";

/**
 * Hands the invite to an installed app, or sells the app to somebody who has
 * never heard of it.
 *
 * Those are two different jobs and the page used to do only the first. It fired
 * `synctogether://` at every visitor on mount, which for a returning member is
 * exactly right and for a first-time recipient is the worst possible opening:
 * an unexplained OS permission dialog ("Open SyncTogether?") or, on a browser
 * with no handler, a bare failure - before a single word about what the thing
 * is. That recipient is the growth loop. The product needs two desktop installs
 * before it delivers any value at all, so this page converting or not
 * converting is the whole funnel.
 *
 * So the launch is now conditional on ever having been here before, remembered
 * in localStorage. A known visitor gets the old instant hand-off. An unknown
 * one gets the pitch, with "I already have it" as the secondary path - which
 * also sets the flag, so they only pay this cost once.
 *
 * The custom scheme still cannot be probed - a browser gives no callback either
 * way - so the only signal that an app took the URL is the page losing focus.
 * After the grace window with the page still visible, nothing took it.
 *
 * The visited flag is read through `useSyncExternalStore` rather than an effect
 * because localStorage is exactly the external store it exists for: the server
 * snapshot is a deliberate `false`, so the markup React hydrates against is the
 * pitch, and the real value arrives on the first client render without a
 * mismatch and without a cascading setState.
 */

const SEEN_KEY = "st.join.seen";

type Phase = "launching" | "handed-off" | "fallback";
type State = Phase | "first-time";

/** The flag only changes via `rememberVisit`, which always navigates away. */
const subscribe = () => () => {};

function hasVisitedBefore(): boolean {
  try {
    return window.localStorage.getItem(SEEN_KEY) === "1";
  } catch {
    // Private windows and blocked site data both throw. Treating that as "new
    // here" is the safe direction: the pitch is never the wrong thing to show.
    return false;
  }
}

function rememberVisit() {
  try {
    window.localStorage.setItem(SEEN_KEY, "1");
  } catch {
    // Non-fatal. They see the pitch again next time, which is survivable.
  }
}

/**
 * Phones cannot install a desktop app, so their lit action is carrying the
 * link to a computer instead. Read like the visited flag: the server snapshot
 * is desktop, the real answer lands on the first client render.
 */
function isPhone(): boolean {
  return /android|iphone|ipod|mobile/i.test(navigator.userAgent);
}

export function JoinLauncher({ code, heading }: { code: string; heading?: React.ReactNode }) {
  const phone = useSyncExternalStore(subscribe, isPhone, () => false);
  const [copied, setCopied] = useState(false);
  // Bumped per attempt so the progress bar restarts on "Try again".
  const [attempt, setAttempt] = useState(0);
  const visited = useSyncExternalStore(subscribe, hasVisitedBefore, () => false);
  const [phase, setPhase] = useState<Phase | null>(null);

  // Derived rather than stored, so the one-time decision never needs an effect
  // to write it down. Once the user acts, `phase` takes over.
  const state: State = phase ?? (visited ? "launching" : "first-time");

  const copyDownloadLink = async () => {
    try {
      await navigator.clipboard.writeText(`${window.location.origin}/download?code=${code}`);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 2000);
    } catch {
      // Clipboard blocked; the footnote still carries the code.
    }
  };

  const settled = useRef(false);

  const attemptHandoff = useCallback(() => {
    settled.current = false;
    setAttempt((n) => n + 1);
    setPhase("launching");
  }, []);

  useEffect(() => {
    if (state !== "launching") return;

    const settle = (next: "fallback" | "handed-off") => {
      if (settled.current) return;
      settled.current = true;
      setPhase(next);
    };

    const onHidden = () => {
      if (document.visibilityState === "hidden") settle("handed-off");
    };
    const onBlur = () => settle("handed-off");
    document.addEventListener("visibilitychange", onHidden);
    window.addEventListener("blur", onBlur);

    rememberVisit();
    // Assigning rather than opening a window: a popup blocker will not stop a
    // same-tab scheme navigation, and a blocked popup looks like a dead link.
    window.location.href = `synctogether://join/${code}`;
    const timer = window.setTimeout(() => settle("fallback"), 1600);

    return () => {
      window.clearTimeout(timer);
      document.removeEventListener("visibilitychange", onHidden);
      window.removeEventListener("blur", onBlur);
    };
  }, [state, code]);

  const display = "font-[family-name:var(--font-space-grotesk)]";
  const mono = "font-[family-name:var(--font-jetbrains-mono)]";

  // The status bar mirrors the real hand-off: it fills over the same 1600 ms
  // grace window the effect above waits out, and settles on whichever outcome
  // that effect records. It never drives anything itself.
  const status =
    state === "launching"
      ? { dot: "bg-beam-500 shadow-[0_0_10px_var(--color-beam-500)]", label: "Opening SyncTogether…" }
      : state === "handed-off"
        ? { dot: "bg-cue", label: "Handed to the app" }
        : state === "fallback"
          ? { dot: "bg-signal", label: "The app didn't open" }
          : null;

  const lit = "btn-primary-gradient inline-flex items-center justify-center gap-2.5 h-[52px] px-6 rounded-[4px] text-base font-semibold text-center cursor-pointer";
  const outline =
    "inline-flex items-center justify-center h-[52px] px-[22px] rounded-[4px] text-base font-semibold text-white border border-[#5A4F44] hover:border-gray-500 transition-colors cursor-pointer";

  return (
    <div className="w-full grid lg:grid-cols-[1fr_1fr] gap-10 lg:gap-[72px] items-center">
      <div className="flex flex-col gap-8 min-w-0">
        {heading}
        {/* Tilted wrapper + stamp compose around Ticket rather than editing it. */}
        <div className="relative -rotate-2 pt-4">
          <Ticket
            animate
            stub={
              <span className={`${mono} text-lg sm:text-2xl font-semibold tracking-[0.08em]`}>
                {code}
              </span>
            }
          >
            <p className={`${mono} text-[10px] sm:text-[11px] uppercase tracking-[0.14em] text-[#A33A22]`}>
              Admit one<span className="hidden sm:inline"> · you&apos;re invited</span>
            </p>
            <p className={`${display} mt-2 text-3xl sm:text-[44px] font-extrabold tracking-[-0.035em] leading-[0.98]`}>
              Movie night
            </p>
            <p className="mt-3 text-sm text-[#5A4F44]">Your seat is saved in room {code}</p>
          </Ticket>
          <JoinStamp
            top="Seat"
            big="Saved"
            bottom="Will call"
            className="absolute -top-10 sm:-top-12 right-[6.5rem] sm:right-[8.5rem]"
          />
        </div>
      </div>

      <div className="flex flex-col gap-6 min-w-0">
        {status && (
          <div className="relative overflow-hidden flex items-center gap-3 rounded-md border border-rail bg-seat px-4 sm:px-5 py-3.5" role="status">
            <span className={`w-2.5 h-2.5 shrink-0 rounded-full ${status.dot}`} aria-hidden="true" />
            <span className={`${mono} text-xs sm:text-[13px] tracking-[0.08em] uppercase text-white`}>{status.label}</span>
            <span className="flex-1" />
            <span className={`${mono} text-xs text-gray-500`}>1.6s</span>
            {state === "launching" && (
              <span
                key={attempt}
                aria-hidden="true"
                className="join-handoff-bar absolute left-0 bottom-0 h-[2px] w-full origin-left bg-beam-500"
              />
            )}
          </div>
        )}

        {state === "handed-off" && (
          <div className="space-y-3">
            <p className="text-gray-300">
              Handed over to the app. You can close this tab.
            </p>
            <button
              onClick={attemptHandoff}
              className="text-sm text-white underline underline-offset-4 decoration-rail hover:decoration-beam-500 cursor-pointer"
            >
              Nothing happened? Try again
            </button>
          </div>
        )}

        {/*
          The two "you need the app" states share a pitch but differ in framing:
          somebody who has been here before already knows what this is and just
          needs the download, while a first-timer needs to be told before being
          asked to install anything.
        */}
        {(state === "first-time" || state === "fallback") && (
          <div className="flex flex-col gap-6">
            <div className="flex flex-col gap-6">
              <p className={`${display} text-3xl sm:text-[40px] font-extrabold tracking-[-0.04em] leading-[0.92] text-white`}>
                {state === "first-time"
                  ? "Movie night, from wherever you both are."
                  : "You'll need the app to join."}
              </p>
              <p className="text-[17px] text-gray-400 leading-[1.55]">
                SyncTogether keeps a film on the same frame for everyone in the
                room, with your faces beside it. Free on Mac and Windows. No
                account needed to join.
              </p>
            </div>

            <ol className="border-t border-aisle">
              {[
                "Your own video file, or a YouTube link",
                "Voice and facecams beside the film",
                "Play, pause and skip stay in sync",
              ].map((label, i) => (
                <li key={label} className="flex gap-4 border-b border-aisle py-[13px] text-[15px] text-white">
                  <span className={`${mono} text-[#5A4F44]`}>0{i + 1}</span>
                  <span>{label}</span>
                </li>
              ))}
            </ol>

            {phone ? (
              <div className="flex flex-col gap-3">
                <button onClick={copyDownloadLink} className={lit}>
                  {copied ? <Check className="w-4 h-4" /> : <Mail className="w-4 h-4" />}
                  <span aria-live="polite">{copied ? "Link copied. Send it to your computer" : "Copy the download link"}</span>
                </button>
                <button onClick={attemptHandoff} className={outline}>
                  Open in the app
                </button>
              </div>
            ) : (
              <div className="flex flex-col sm:flex-row gap-3">
                <Link href={`/download?code=${code}`} className={lit}>
                  <Download strokeWidth={1.8} className="w-[18px] h-[18px]" />
                  Download free
                </Link>
                <button onClick={attemptHandoff} className={outline}>
                  Open in the app
                </button>
              </div>
            )}

            <p className="text-[13px] text-gray-500 leading-[1.55]">
              {phone ? "On your computer? " : "Nothing happened? "}Install, open the app and type{" "}
              <span className={`${mono} text-white`}>{code}</span> on the join
              card. The room will still be waiting.
            </p>
          </div>
        )}
      </div>

      <style>{`
        @keyframes join-handoff-fill { from { transform: scaleX(0); } to { transform: scaleX(1); } }
        .join-handoff-bar { animation: join-handoff-fill 1600ms linear both; }
      `}</style>
    </div>
  );
}
