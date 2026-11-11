"use client";

import { useEffect, type ReactNode } from "react";
import { PTButton } from "@/components/PTButton";
import { openAppLink } from "@/lib/openAppLink";

/** The query and hash carry the session, so they travel to the app verbatim. */
function deepLinkUrl() {
  return `synctogether://auth-callback${window.location.search}${window.location.hash}`;
}

/**
 * The only client part of the callback page. The copy is server-rendered so it
 * is in the first paint: this used to be a whole client page behind
 * `useSearchParams`, whose prerendered HTML was just a "Completing
 * authentication..." line that hydration then replaced - a late LCP and a
 * layout shift on every sign-in.
 */
export function AutoHandoff() {
  useEffect(() => {
    // Loaded after the page is up, so the confetti never weighs on first load.
    import("canvas-confetti")
      .then(({ default: confetti }) =>
        confetti({
          particleCount: 45,
          spread: 60,
          origin: { y: 0.65 },
          colors: ["#FFB23F", "#FFB23F", "#6FD6C4", "#FFB23F"],
          disableForReducedMotion: true,
        }),
      )
      .catch(() => {});
    const timer = window.setTimeout(() => openAppLink(deepLinkUrl()), 250);
    return () => window.clearTimeout(timer);
  }, []);
  return null;
}

export function OpenAppButton({ icon, children }: { icon: ReactNode; children: ReactNode }) {
  return (
    <PTButton variant="primary" size="lg" onClick={() => openAppLink(deepLinkUrl())} rightIcon={icon}>
      {children}
    </PTButton>
  );
}
