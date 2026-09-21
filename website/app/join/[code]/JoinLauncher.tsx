"use client";

import {
  useCallback,
  useEffect,
  useRef,
  useState,
  useSyncExternalStore,
} from "react";
import Link from "next/link";
import { GlassPanel } from "@/components/GlassPanel";
import { Clapperboard, Users, Sparkles } from "lucide-react";

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

export function JoinLauncher({ code }: { code: string }) {
  const visited = useSyncExternalStore(subscribe, hasVisitedBefore, () => false);
  const [phase, setPhase] = useState<Phase | null>(null);

  // Derived rather than stored, so the one-time decision never needs an effect
  // to write it down. Once the user acts, `phase` takes over.
  const state: State = phase ?? (visited ? "launching" : "first-time");

  const settled = useRef(false);

  const attemptHandoff = useCallback(() => {
    settled.current = false;
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

  return (
    <GlassPanel className="p-8 text-center space-y-6">
      <div className="space-y-2">
        <p className="text-sm uppercase tracking-[0.2em] text-[var(--pt-text-accent)]">
          Room code
        </p>
        <p className="font-[family-name:var(--font-jetbrains-mono)] text-4xl font-semibold tracking-[0.35em] text-white">
          {code}
        </p>
      </div>

      {state === "launching" && (
        <p className="text-gray-300">Opening SyncTogether…</p>
      )}

      {state === "handed-off" && (
        <div className="space-y-3">
          <p className="text-gray-300">
            Handed over to the app. You can close this tab.
          </p>
          <button
            onClick={attemptHandoff}
            className="text-sm text-[var(--pt-text-accent)] underline underline-offset-4"
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
        <div className="space-y-6">
          <div className="space-y-2">
            <p className="text-lg font-semibold text-white font-[family-name:var(--font-space-grotesk)]">
              {state === "first-time"
                ? "Movie night, from wherever you both are."
                : "You'll need the app to join."}
            </p>
            <p className="text-sm text-gray-300 leading-relaxed">
              SyncTogether keeps a film playing on the same frame for both of
              you - no counting down from three - with your faces side by side
              while it runs. Free to use, on Mac and Windows.
            </p>
          </div>

          <ul className="grid gap-3 text-left sm:grid-cols-3">
            {[
              { Icon: Clapperboard, label: "Your own video file, or a YouTube link" },
              { Icon: Users, label: "Voice and facecams beside the film" },
              { Icon: Sparkles, label: "Play, pause and skip stay in sync" },
            ].map(({ Icon, label }) => (
              <li
                key={label}
                className="flex items-start gap-2.5 text-xs text-gray-400 leading-snug"
              >
                <Icon className="w-4 h-4 shrink-0 mt-0.5 text-[var(--pt-text-accent)]" />
                <span>{label}</span>
              </li>
            ))}
          </ul>

          <div className="flex flex-col sm:flex-row gap-3 justify-center">
            <Link
              href={`/download?code=${code}`}
              className="btn-primary-gradient px-6 py-3 rounded-xl font-semibold text-white"
            >
              Download free
            </Link>
            <button
              onClick={attemptHandoff}
              className="px-6 py-3 rounded-xl font-semibold text-gray-200 border border-white/10 hover:border-white/25 transition-colors"
            >
              I already have it
            </button>
          </div>

          <p className="text-xs text-gray-500">
            The room will still be waiting. Already installed? Open the app and
            enter{" "}
            <span className="font-[family-name:var(--font-jetbrains-mono)] text-gray-400">
              {code}
            </span>{" "}
            on the join card.
          </p>
        </div>
      )}
    </GlassPanel>
  );
}
