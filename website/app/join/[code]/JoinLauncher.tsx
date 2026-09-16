"use client";

import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { GlassPanel } from "@/components/GlassPanel";

/**
 * Tries to hand the invite to an installed app, and offers the download when
 * nothing answers.
 *
 * The custom scheme cannot be probed - a browser gives no callback either way -
 * so the only signal is whether the page loses focus, which is what happens
 * when the OS hands the URL to another application. After the grace window with
 * the page still visible, nothing took it.
 */
export function JoinLauncher({ code }: { code: string }) {
  const [state, setState] = useState<"launching" | "fallback" | "handed-off">("launching");
  const settled = useRef(false);

  useEffect(() => {
    const settle = (next: "fallback" | "handed-off") => {
      if (settled.current) return;
      settled.current = true;
      setState(next);
    };

    const onHidden = () => {
      if (document.visibilityState === "hidden") settle("handed-off");
    };
    document.addEventListener("visibilitychange", onHidden);
    window.addEventListener("blur", () => settle("handed-off"));

    // Assigning rather than opening a window: a popup blocker will not stop a
    // same-tab scheme navigation, and a blocked popup looks like a dead link.
    window.location.href = `synctogether://join/${code}`;
    const timer = window.setTimeout(() => settle("fallback"), 1600);

    return () => {
      window.clearTimeout(timer);
      document.removeEventListener("visibilitychange", onHidden);
    };
  }, [code]);

  const retry = () => {
    window.location.href = `synctogether://join/${code}`;
  };

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
            onClick={retry}
            className="text-sm text-[var(--pt-text-accent)] underline underline-offset-4"
          >
            Nothing happened? Try again
          </button>
        </div>
      )}

      {state === "fallback" && (
        <div className="space-y-5">
          <p className="text-gray-300">
            SyncTogether does not seem to be installed on this device. Grab it - it is
            free, and the room will still be waiting.
          </p>
          <div className="flex flex-col sm:flex-row gap-3 justify-center">
            <Link
              href={`/download?code=${code}`}
              className="btn-primary-gradient px-6 py-3 rounded-xl font-semibold text-white"
            >
              Download SyncTogether
            </Link>
            <button
              onClick={retry}
              className="px-6 py-3 rounded-xl font-semibold text-gray-200 border border-white/10 hover:border-white/25 transition-colors"
            >
              I already have it
            </button>
          </div>
          <p className="text-xs text-gray-500">
            Already installed? Open the app and enter{" "}
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
