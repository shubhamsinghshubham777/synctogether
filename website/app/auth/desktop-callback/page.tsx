"use client";

import { Suspense, useEffect } from "react";
import { useSearchParams } from "next/navigation";
import Link from "next/link";
import { Ticket } from "@/components/Ticket";
import { Kicker, Headline, Stamp, display, mono } from "@/components/booth/Booth";
import { PTButton } from "@/components/PTButton";
import confetti from "canvas-confetti";
import { ArrowUpRight, ArrowRight } from "lucide-react";


function DesktopCallbackContent() {
  const searchParams = useSearchParams();

  const error = searchParams.get("error") || searchParams.get("error_code");
  const rawErrorDesc =
    searchParams.get("error_description") ||
    searchParams.get("error_message") ||
    (error ? "The authentication process was cancelled or failed." : null);
  const errorMessage = rawErrorDesc ? rawErrorDesc.replace(/\+/g, " ") : null;
  const isError = Boolean(error || errorMessage);

  const getDeepLinkUrl = () => {
    if (typeof window === "undefined") return "synctogether://auth-callback";
    const search = window.location.search || "";
    const hash = window.location.hash || "";
    return `synctogether://auth-callback${search}${hash}`;
  };

  useEffect(() => {
    if (isError) return;

    const targetUri = getDeepLinkUrl();

    // Gentle celebratory confetti
    try {
      confetti({
        particleCount: 45,
        spread: 60,
        origin: { y: 0.65 },
        colors: ["#FFB23F", "#FFB23F", "#6FD6C4", "#FFB23F"],
        disableForReducedMotion: true,
      });
    } catch {
      // Ignore if confetti fails in headless/SSR environments
    }

    // Automatically trigger deep-link launch
    const timer = setTimeout(() => {
      try {
        window.location.href = targetUri;
      } catch (err) {
        console.error("Deep link navigation error:", err);
      }
    }, 250);

    return () => clearTimeout(timer);
  }, [isError]);

  const handleManualOpen = () => {
    window.location.href = getDeepLinkUrl();
  };

  if (isError) {
    return (
      <div className="w-full max-w-xl space-y-8">
        <div className="space-y-5">
          <Kicker tone="signal">Sign-in incomplete</Kicker>
          <Headline className="text-[clamp(2.5rem,7vw,4.5rem)]">
            <span className="line-in">The ticket</span>
            <span className="line-in [animation-delay:90ms]">didn&apos;t print.</span>
          </Headline>
          <p className="text-lg text-gray-400 leading-relaxed max-w-md break-words">
            {errorMessage || "We couldn't finish signing you in. Please try again."}
          </p>
        </div>

        <div className="flex flex-wrap items-center gap-x-6 gap-y-4">
          <PTButton
            variant="primary"
            size="lg"
            onClick={handleManualOpen}
            rightIcon={<ArrowRight className="w-4 h-4" />}
          >
            Return to the app
          </PTButton>
          <Link
            href="/auth"
            className="text-[15px] font-semibold text-white underline underline-offset-[6px] decoration-rail hover:decoration-beam-500 transition-colors"
          >
            Try signing in again
          </Link>
        </div>
      </div>
    );
  }

  return (
    <div className="w-full max-w-5xl grid lg:grid-cols-[1fr_1.05fr] gap-12 lg:gap-16 items-center">
      <div className="space-y-6 order-2 lg:order-1">
        <Kicker tone="cue">Login successful</Kicker>
        <Headline className="text-[clamp(2.75rem,7vw,5rem)]">
          <span className="line-in">You&apos;re in.</span>
          <span className="line-in [animation-delay:90ms] text-beam-500">Back to the booth.</span>
        </Headline>
        <p className="text-lg text-gray-400 leading-relaxed max-w-md">
          We&apos;ve handed your session to the SyncTogether app. If it didn&apos;t come forward
          on its own, open it below, then this tab can go.
        </p>
        <div className="flex flex-wrap items-center gap-x-6 gap-y-4 pt-2">
          <PTButton
            variant="primary"
            size="lg"
            onClick={handleManualOpen}
            rightIcon={<ArrowUpRight className="w-4 h-4" />}
          >
            Open SyncTogether
          </PTButton>
          <Link
            href="/account"
            className="text-[15px] font-semibold text-white underline underline-offset-[6px] decoration-rail hover:decoration-beam-500 transition-colors"
          >
            Your account on the web
          </Link>
        </div>
      </div>

      <div className="relative order-1 lg:order-2 pt-6 pr-4 sm:pr-8">
        <Ticket
          animate
          stub={
            <span className={`${mono} text-sm sm:text-lg font-semibold tracking-[0.08em]`}>ADMIT&nbsp;1</span>
          }
        >
          <p className={`${mono} text-[10px] sm:text-[11px] tracking-[0.14em] text-[#6B5F52]`}>
            DESKTOP · SIGN-IN
          </p>
          <p className={`${display} mt-1.5 text-2xl sm:text-4xl font-extrabold tracking-[-0.035em] leading-[0.95]`}>
            Your seat is held.
          </p>
          <p className="mt-2 text-xs sm:text-sm text-[#5A4F44] truncate">synctogether://auth-callback</p>
        </Ticket>
        <div className="absolute right-0 -top-2 sm:-top-4">
          <Stamp top="LOGIN" main="OK" bottom="SIGNED IN" tone="signal" tilt={12} />
        </div>
      </div>
    </div>
  );
}

export default function DesktopCallbackPage() {
  return (
    <div className="min-h-[80vh] flex items-center justify-center px-4 sm:px-6 lg:px-8 py-12 md:py-12">
      <Suspense
        fallback={
          <p className={`${mono} text-xs tracking-[0.16em] uppercase text-gray-500`}>
            Completing authentication…
          </p>
        }
      >
        <DesktopCallbackContent />
      </Suspense>
    </div>
  );
}
