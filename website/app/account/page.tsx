"use client";

import { Suspense, useEffect, useRef, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import Image from "next/image";
import { Ticket } from "@/components/Ticket";
import { Headline, Stamp, Warming, display, mono } from "@/components/booth/Booth";
import { AccountPatronOffer } from "./AccountPatronOffer";
import { createClient } from "@/lib/supabase/client";
import type { User } from "@supabase/supabase-js";
import confetti from "canvas-confetti";
import {
  CheckCircle2,
  RefreshCw,
  AlertCircle,
  X,
} from "lucide-react";

interface EntitlementData {
  tier: "guest" | "free" | "premium";
  max_live_rooms: number;
  max_members: number;
  max_session_minutes: number;
  max_total_session_minutes: number;
  av_level: string;
  persistent_room_cap: number;
  dormant_hours: number;
}

interface SubscriptionData {
  tier: string;
  current_period_end: string | null;
  source: string;
  updated_at: string;
}

function AccountDashboard() {
  const [user, setUser] = useState<User | null>(null);
  const [entitlement, setEntitlement] = useState<EntitlementData | null>(null);
  const [subscription, setSubscription] = useState<SubscriptionData | null>(null);
  const [loading, setLoading] = useState(true);
  const [verifying, setVerifying] = useState(false);
  const [isCancelling, setIsCancelling] = useState(false);
  const [cancelsAt, setCancelsAt] = useState<string | null>(null);
  const [isLoggingOut, setIsLoggingOut] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const celebratedRef = useRef(false);

  const router = useRouter();
  const searchParams = useSearchParams();
  const isSubscribedRedirect = searchParams.get("subscribed") === "true";
  // Pulled out as primitives so the loader below depends on the two params it
  // actually reads, rather than on the whole searchParams object - which would
  // re-run the account fetch and re-open the realtime channel on any query
  // string change.
  const errorDescriptionParam = searchParams.get("error_description");
  const errorParam = searchParams.get("error");
  const supabase = createClient();

  useEffect(() => {
    const parseUrlErrors = () => {
      let message: string | null = null;

      // 1. Check URL hash fragment (Supabase auth error redirects)
      if (typeof window !== "undefined" && window.location.hash) {
        try {
          const rawHash = window.location.hash.startsWith("#")
            ? window.location.hash.slice(1)
            : window.location.hash;
          const hashParams = new URLSearchParams(rawHash);
          const desc = hashParams.get("error_description");
          const code = hashParams.get("error_code");
          const err = hashParams.get("error");

          if (desc) {
            message = desc.replace(/\+/g, " ");
          } else if (code === "otp_expired") {
            message = "Email link is invalid or has expired. Please request a new code.";
          } else if (err) {
            message = err.replace(/\+/g, " ");
          }
        } catch (e) {
          console.error("Failed to parse URL hash parameters on account page:", e);
        }
      }

      // 2. Fall back to search parameters (?error_description=... or ?error=...)
      if (!message) {
        const desc = searchParams.get("error_description");
        const err = searchParams.get("error");
        if (desc) {
          message = desc.replace(/\+/g, " ");
        } else if (err) {
          message = err.replace(/\+/g, " ");
        }
      }

      if (message) {
        setErrorMsg(message);
      }
    };

    parseUrlErrors();

    window.addEventListener("hashchange", parseUrlErrors);
    return () => window.removeEventListener("hashchange", parseUrlErrors);
  }, [searchParams]);

  useEffect(() => {
    let ignore = false;
    let channel: ReturnType<typeof supabase.channel> | null = null;

    async function loadData() {
      try {
        const {
          data: { user },
        } = await supabase.auth.getUser();

        if (ignore) return;
        if (!user) {
          let target = "/auth?redirect=/account";
          if (typeof window !== "undefined") {
            const rawHash = window.location.hash ? (window.location.hash.startsWith("#") ? window.location.hash.slice(1) : window.location.hash) : "";
            const hashParams = new URLSearchParams(rawHash);
            const errDesc =
              hashParams.get("error_description") ||
              hashParams.get("error") ||
              errorDescriptionParam ||
              errorParam;
            if (errDesc) {
              target += `&error=${encodeURIComponent(errDesc.replace(/\+/g, " "))}` + (window.location.hash || "");
            }
          }
          router.push(target);
          return;
        }
        setUser(user);

        const [entRes, subRes] = await Promise.all([
          supabase.rpc("my_entitlement"),
          supabase.from("subscriptions").select("*").eq("user_id", user.id).maybeSingle(),
        ]);

        if (ignore) return;

        if (!entRes.error && entRes.data) {
          const ent = Array.isArray(entRes.data) ? entRes.data[0] : entRes.data;
          setEntitlement(ent);
        } else {
          setEntitlement({
            tier: "free",
            max_live_rooms: 4,
            max_members: 8,
            max_session_minutes: 240,
            max_total_session_minutes: 240,
            av_level: "voice",
            persistent_room_cap: 0,
            dormant_hours: 24,
          });
        }

        setSubscription(subRes.data ?? null);

        const channelName = `account_subs_${user.id}_${Date.now()}`;
        const newChannel = supabase
          .channel(channelName)
          .on(
            "postgres_changes",
            {
              event: "*",
              schema: "public",
              table: "subscriptions",
              filter: `user_id=eq.${user.id}`,
            },
            async () => {
              if (ignore) return;
              const { data: updatedEnt } = await supabase.rpc("my_entitlement");
              if (updatedEnt && !ignore) {
                const ent = Array.isArray(updatedEnt) ? updatedEnt[0] : updatedEnt;
                setEntitlement(ent);
              }
              const { data: updatedSub } = await supabase
                .from("subscriptions")
                .select("*")
                .eq("user_id", user.id)
                .maybeSingle();
              if (!ignore) {
                setSubscription(updatedSub ?? null);
              }
            }
          );

        if (ignore) {
          supabase.removeChannel(newChannel);
          return;
        }

        channel = newChannel.subscribe();
      } catch (err) {
        if (!ignore) {
          console.error("Failed to load user account data:", err);
        }
      } finally {
        if (!ignore) setLoading(false);
      }
    }

    loadData();

    return () => {
      ignore = true;
      if (channel) {
        supabase.removeChannel(channel);
      }
    };
  }, [router, supabase, errorDescriptionParam, errorParam]);

  useEffect(() => {
    if (!isSubscribedRedirect) return;

    let ignore = false;
    async function fulfill() {
      setVerifying(true);
      try {
        const res = await fetch("/api/paddle/fulfill", { method: "POST" });
        let newSub: SubscriptionData | null = null;
        if (res.ok) {
          const data = await res.json();
          if (data.subscription && !ignore) {
            newSub = data.subscription;
            setSubscription(data.subscription);
          }
        }
        const { data: entData } = await supabase.rpc("my_entitlement");
        let activeTier = "free";
        if (entData && !ignore) {
          const ent = Array.isArray(entData) ? entData[0] : entData;
          setEntitlement(ent);
          activeTier = ent?.tier || "free";
        }

        const isVerifiedPremium = activeTier === "premium" || newSub?.tier === "premium";

        if (isVerifiedPremium) {
          if (!celebratedRef.current) {
            celebratedRef.current = true;
            try {
              confetti({
                particleCount: 100,
                spread: 70,
                origin: { y: 0.6 },
                colors: ["#FFB23F", "#FFC266", "#FBBF24", "#6FD6C4"],
              });
            } catch {
              // ignore confetti errors
            }
          }
        } else {
          // False-positive or unverified redirect - strip the query param quietly
          router.replace("/account");
        }
      } catch (err) {
        console.error("Fulfillment check failed:", err);
        router.replace("/account");
      } finally {
        if (!ignore) {
          setVerifying(false);
        }
      }
    }

    fulfill();

    return () => {
      ignore = true;
    };
  }, [isSubscribedRedirect, router, supabase]);

  const handleCancelSubscription = async () => {
    if (
      !window.confirm(
        "Cancel your Premium subscription? You keep Premium until the end of the period you have already paid for, and you will not be billed again."
      )
    ) {
      return;
    }
    setIsCancelling(true);
    try {
      const res = await fetch("/api/paddle/cancel", { method: "POST" });
      const body = await res.json().catch(() => null);
      if (res.ok) {
        // Cancellation is scheduled at the next billing period, so the
        // subscription is still live and must keep rendering as such -
        // clearing it here showed the Free tier immediately and a reload then
        // contradicted it.
        if (body?.scheduled) {
          setCancelsAt(body.cancelsAt ?? subscription?.current_period_end ?? null);
        } else {
          setSubscription(null);
        }
        const { data: entData } = await supabase.rpc("my_entitlement");
        if (entData) {
          const ent = Array.isArray(entData) ? entData[0] : entData;
          setEntitlement(ent);
        }
      } else if (body?.error === "subscription_unlinked") {
        alert(
          "We could not find the billing record for this subscription. Please contact support so we can stop the billing for you."
        );
      } else {
        alert("Failed to cancel subscription. Please contact support.");
      }
    } catch (err) {
      console.error("Cancellation error:", err);
      alert("An error occurred while canceling. Please try again.");
    } finally {
      setIsCancelling(false);
    }
  };

  const handleSignOut = async () => {
    setIsLoggingOut(true);
    await supabase.auth.signOut();
    router.push("/");
  };

  const handleExportData = () => {
    const exportData = {
      profile: {
        id: user?.id,
        email: user?.email,
        name: user?.user_metadata?.full_name,
        created_at: user?.created_at,
      },
      entitlement,
      subscription,
      exported_at: new Date().toISOString(),
    };

    const blob = new Blob([JSON.stringify(exportData, null, 2)], {
      type: "application/json",
    });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `synctogether-data-${user?.id?.slice(0, 8)}.json`;
    a.click();
    URL.revokeObjectURL(url);
  };

  if (loading) {
    return <Warming label="Finding your seat…" />;
  }

  const isPremium = entitlement?.tier === "premium";
  const displayName = user?.user_metadata?.full_name || "SyncTogether User";
  // A tier that picks its own length reads "up to", as the boards and the pricing table do.
  const sessionHours = entitlement?.max_total_session_minutes
    ? `${
        entitlement.max_total_session_minutes > (entitlement.max_session_minutes ?? 0) ? "up to " : ""
      }${entitlement.max_total_session_minutes / 60} hours`
    : entitlement?.max_session_minutes
    ? `${entitlement.max_session_minutes / 60} hours`
    : "4 hours";
  const facecams =
    entitlement?.av_level === "video" ? "Voice + video" : entitlement?.av_level === "voice" ? "Voice" : "None";
  const persistent =
    (entitlement?.persistent_room_cap ?? 0) > 0 ? `${entitlement?.persistent_room_cap}` : "0 (24h to resume)";
  const patronUntil = subscription?.current_period_end
    ? formatDate(cancelsAt ?? subscription.current_period_end)
    : null;
  // Only a Paddle subscription renews; a manual or debug grant simply ends.
  const billed = subscription?.source === "paddle";
  const nextCharge = billed && !cancelsAt && subscription?.current_period_end ? formatDate(subscription.current_period_end) : null;
  const paidWith = subscription?.source
    ? subscription.source === "paddle"
      ? "Paddle"
      : subscription.source.charAt(0).toUpperCase() + subscription.source.slice(1)
    : null;
  const memberSince = user?.created_at
    ? new Date(user.created_at).toLocaleDateString(undefined, { month: "short", year: "numeric" })
    : null;
  const provider = user?.app_metadata?.provider as string | undefined;
  const providerLabel =
    provider === "google" ? "Google" : provider === "apple" ? "Apple" : provider === "email" ? "email" : null;
  const seasonYear = new Date().getFullYear();

  const errorBanners = (errorMsg || (isSubscribedRedirect && (verifying || isPremium))) && (
    <div className="space-y-3 mb-10">
      {errorMsg && (
        <div
          role="alert"
          className="booth-rise border-l-2 border-signal bg-seat pl-5 pr-3 py-4 flex items-start justify-between gap-3"
        >
          <div className="flex items-start gap-3 min-w-0">
            <AlertCircle className="w-5 h-5 text-signal shrink-0 mt-0.5" />
            <div className="min-w-0">
              <p className={`${mono} text-[11px] tracking-[0.14em] uppercase text-signal`}>Authentication alert</p>
              <p className="text-sm text-gray-300 mt-1 leading-relaxed break-words">{errorMsg}</p>
            </div>
          </div>
          <button
            type="button"
            onClick={() => setErrorMsg(null)}
            className="text-gray-400 hover:text-white p-1.5 rounded-[4px] hover:bg-aisle transition-colors cursor-pointer"
            aria-label="Dismiss alert"
          >
            <X className="w-4 h-4" />
          </button>
        </div>
      )}

      {isSubscribedRedirect && verifying && !isPremium && (
        <div role="status" className="booth-rise border-l-2 border-beam-500 bg-seat pl-5 pr-4 py-4 flex items-center gap-3">
          <RefreshCw className="w-5 h-5 text-beam-500 animate-spin shrink-0" />
          <div>
            <p className={`${display} text-lg font-extrabold tracking-[-0.02em] text-white`}>
              Checking your ticket with the box office…
            </p>
            <p className="text-sm text-gray-400">
              Confirming your upgrade with Paddle and activating your account benefits.
            </p>
          </div>
        </div>
      )}

      {isSubscribedRedirect && isPremium && (
        <div role="status" className="booth-rise border-l-2 border-brass bg-seat pl-5 pr-4 py-4 flex items-center gap-3">
          <CheckCircle2 className="w-6 h-6 text-brass shrink-0" />
          <div>
            <p className={`${display} text-lg font-extrabold tracking-[-0.02em] text-white`}>
              Welcome to the Patron seats.
            </p>
            <p className="text-sm text-gray-400">Your subscription is active. Every Patron perk is on your account.</p>
          </div>
        </div>
      )}
    </div>
  );

  const kicker = `${mono} text-[11px] tracking-[0.14em] uppercase text-gray-500`;
  const valueTone = isPremium ? "text-brass" : "text-white";

  return (
    <div className="px-4 sm:px-6 lg:px-8 max-w-[1248px] mx-auto pt-8 pb-12 md:pt-12 md:pb-16">
      {errorBanners}

      <div className="grid gap-10 lg:gap-12 lg:grid-cols-[168px_minmax(0,1fr)] xl:grid-cols-[168px_minmax(0,1fr)_420px]">
        {/* Side nav */}
        <nav aria-label="Account" className="lg:row-span-2">
          <p className={`${kicker} mb-4 hidden lg:block`}>Your account</p>
          <ul className="flex lg:flex-col gap-1 border-b lg:border-b-0 border-rail overflow-x-auto">
            <li>
              <a
                href="#seat"
                className="block whitespace-nowrap px-3.5 py-2.5 text-[15px] font-semibold text-white border-b-2 lg:border-b-0 lg:border-l-2 border-beam-500"
              >
                Seat &amp; billing
              </a>
            </li>
            <li>
              <a
                href="#your-data"
                className="block whitespace-nowrap px-3.5 py-2.5 text-[15px] text-gray-300 hover:text-white border-b-2 lg:border-b-0 lg:border-l-2 border-transparent lg:border-rail transition-colors"
              >
                Your data
              </a>
            </li>
            <li>
              <button
                type="button"
                onClick={handleSignOut}
                disabled={isLoggingOut}
                className="w-full text-left whitespace-nowrap px-3.5 py-2.5 text-[15px] text-gray-300 hover:text-white border-b-2 lg:border-b-0 lg:border-l-2 border-transparent lg:border-rail transition-colors cursor-pointer disabled:opacity-60 inline-flex items-center gap-2"
              >
                {isLoggingOut && <RefreshCw className="w-3.5 h-3.5 animate-spin" />}
                Sign out
              </button>
            </li>
          </ul>
        </nav>

        {/* Main column */}
        <main id="seat" className="min-w-0 space-y-8 scroll-mt-24">
          <header className="flex items-center gap-4 sm:gap-5 min-w-0">
            {user?.user_metadata?.avatar_url ? (
              <Image
                src={user.user_metadata.avatar_url}
                alt={user.user_metadata?.full_name || "Avatar"}
                width={68}
                height={68}
                className={`w-14 h-14 sm:w-16 sm:h-16 rounded-full shrink-0 ${isPremium ? "shadow-[0_0_0_2px_var(--color-booth),0_0_0_4px_var(--color-brass)]" : "shadow-[0_0_0_2px_var(--color-booth),0_0_0_4px_var(--color-rail)]"}`}
              />
            ) : (
              <div
                className={`w-14 h-14 sm:w-16 sm:h-16 shrink-0 rounded-full bg-[#7A5CFF] flex items-center justify-center text-[25px] font-semibold text-screen ${
                  isPremium
                    ? "shadow-[0_0_0_2px_var(--color-booth),0_0_0_4px_var(--color-brass)]"
                    : "shadow-[0_0_0_2px_var(--color-booth),0_0_0_4px_var(--color-rail)]"
                }`}
              >
                {user?.email?.charAt(0).toUpperCase() || "U"}
              </div>
            )}
            <div className="min-w-0">
              <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
                <Headline className="text-[clamp(1.9rem,5vw,2.9rem)] break-words">{displayName}</Headline>
                {isPremium && (
                  <span className={`${mono} inline-flex items-center gap-1 px-2 py-0.5 text-[11px] tracking-[0.08em] uppercase text-brass border border-brass/70 rounded-[4px]`}>
                    <span aria-hidden="true">★</span> Patron
                  </span>
                )}
              </div>
              <p className={`${mono} text-[13px] text-gray-500 break-words mt-1`}>
                {user?.email}
                {providerLabel && <span className="whitespace-nowrap"> · signed in with {providerLabel}</span>}
              </p>
            </div>
          </header>

          {/* The seat, as a ticket */}
          <section aria-labelledby="plan-heading">
            <Ticket
              paper
              animate
              stub={
                isPremium ? (
                  <span className={`${display} text-3xl`} aria-hidden="true">★</span>
                ) : (
                  <span className={`${mono} text-lg sm:text-2xl font-bold tracking-[0.12em]`}>FREE</span>
                )
              }
            >
              <div className="flex items-center justify-between gap-4">
                <div className="min-w-0">
                  <p className={`${mono} text-[10px] sm:text-[11px] tracking-[0.16em] uppercase text-[#6B5F52]`}>
                    Your seat{isPremium && cancelsAt ? " · cancelled, still valid" : ""}
                  </p>
                  <h2
                    id="plan-heading"
                    className={`${display} mt-1 text-4xl sm:text-5xl font-extrabold tracking-[-0.04em] leading-[1]`}
                  >
                    {isPremium ? "Patron" : "Free"}
                  </h2>
                  <p className="mt-2.5 text-sm text-[#5A4F44]">
                    {isPremium
                      ? patronUntil
                        ? `${cancelsAt ? "Patron until" : "Renews"} ${patronUntil}`
                        : "Patron seat"
                      : memberSince
                      ? `Member since ${memberSince}`
                      : "Free seat"}
                  </p>
                </div>
                {isPremium && (
                  <Stamp
                    top="SEASON"
                    main="PATRON"
                    bottom={String(seasonYear)}
                    tone={cancelsAt ? "ink" : "brass"}
                    shape="round"
                    tilt={-8}
                    className="!hidden sm:!inline-flex shrink-0 !w-24 !h-24 [&>span:nth-child(2)]:!text-xl !text-[#7A5A1E] !border-[#7A5A1E]"
                  />
                )}
              </div>
            </Ticket>
          </section>

          <section aria-labelledby="caps-heading">
            <p id="caps-heading" className={`${kicker} mb-2`}>What your seat includes</p>
            <ul>
              {[
                ["Live rooms", isPremium && (entitlement?.persistent_room_cap ?? 0) > 0
                  ? entitlement?.max_live_rooms === entitlement?.persistent_room_cap ? `${entitlement?.max_live_rooms}, kept for good` : `${entitlement?.max_live_rooms}, ${entitlement?.persistent_room_cap} kept for good`
                  : entitlement?.max_live_rooms ?? 4],
                ["People per room", entitlement?.max_members ?? 8],
                ["Session length", sessionHours],
                ["Facecams", facecams],
                ...(isPremium ? [] : [["Persistent rooms", persistent]]),
              ].map(([label, value]) => (
                <li key={String(label)} className="flex items-baseline justify-between gap-4 py-3 border-b border-rail">
                  <span className="text-[15px] text-gray-300">{label}</span>
                  <span className={`${mono} text-sm tabular-nums text-right ${valueTone}`}>{value}</span>
                </li>
              ))}
            </ul>
          </section>

          <div id="your-data" className="grid sm:grid-cols-2 gap-4 scroll-mt-24">
            <div className="bg-seat border border-rail rounded-[6px] p-[22px] flex flex-col items-start gap-3">
              <p className={kicker}>Your data</p>
              <p className="text-sm text-gray-400 leading-[1.55]">Download everything this page knows about you as JSON.</p>
              <button
                type="button"
                onClick={handleExportData}
                className="inline-flex items-center gap-2.5 h-10 px-[22px] whitespace-nowrap rounded-[4px] border border-[#5A4F44] text-sm font-semibold text-white hover:border-gray-400 transition-colors cursor-pointer"
              >
                Export account data
              </button>
            </div>
            <div className="bg-seat border border-rail rounded-[6px] p-[22px] flex flex-col items-start gap-3">
              <p className={kicker}>Leaving?</p>
              <p className="text-sm text-gray-400 leading-[1.55]">
                Delete your account from Profile in the app. It takes your rooms and recaps with it.
              </p>
              <a
                href="/privacy"
                className="inline-block text-sm text-[#FF8A70] underline underline-offset-4 hover:text-white transition-colors"
              >
                How deleting works
              </a>
            </div>
          </div>
        </main>

        {/* Action column */}
        <aside className="min-w-0 space-y-4 lg:col-start-2 xl:col-start-auto">
          {isPremium ? (
            <>
              <div className="bg-seat border border-rail rounded-[6px] p-6 sm:p-7">
                <div className="flex items-center justify-between gap-3 mb-3">
                  <p className={kicker}>Subscription</p>
                  <p className={`${mono} text-[11px] tracking-[0.14em] uppercase ${cancelsAt ? "text-signal" : "text-cue"}`}>
                    ● {cancelsAt ? "Cancelled" : "Active"}
                  </p>
                </div>
                <ul>
                  {[
                    ["Patron until", patronUntil],
                    ["Next charge", nextCharge],
                    ["Paid with", paidWith],
                  ]
                    .filter(([, v]) => v)
                    .map(([label, value]) => (
                      <li key={label} className="flex items-baseline justify-between gap-4 py-3.5 border-b border-rail">
                        <span className="text-[15px] text-gray-300">{label}</span>
                        <span className={`${mono} text-sm text-white text-right`}>{value}</span>
                      </li>
                    ))}
                </ul>
                <button
                  onClick={handleCancelSubscription}
                  disabled={isCancelling || cancelsAt !== null}
                  className="mt-6 w-full inline-flex items-center justify-center gap-2 px-4 py-3 rounded-[4px] text-signal text-[15px] font-semibold border border-signal hover:bg-signal/10 transition-colors cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  {isCancelling ? (
                    <>
                      <RefreshCw className="w-3.5 h-3.5 animate-spin" />
                      <span>Cancelling...</span>
                    </>
                  ) : (
                    <span>{cancelsAt ? "Cancellation scheduled" : "Cancel subscription"}</span>
                  )}
                </button>
                <p className="mt-4 text-[13px] text-gray-500 leading-relaxed">
                  {cancelsAt
                    ? "Cancelled. You keep Premium until the date above and won't be billed again."
                    : billed
                    ? "Renews on the date above. Cancel and you keep Premium until then. Update a card from the link in your receipt email."
                    : "Nothing renews. This seat was granted, not bought, and ends on the date above."}{" "}
                  <a
                    href="mailto:support@synctogether.app?subject=Subscription%20Support"
                    className="text-gray-300 underline underline-offset-4 hover:text-white"
                  >
                    Contact support
                  </a>
                </p>
              </div>
              <div className="border border-dashed border-rail rounded-[6px] p-5">
                <p className={`${kicker} mb-2`}>Bought in the App Store?</p>
                <p className="text-sm text-gray-300 leading-relaxed">
                  Apple manages that one. Cancel it in App Store settings, not here.
                </p>
              </div>
            </>
          ) : (
            <AccountPatronOffer />
          )}
        </aside>
      </div>
    </div>
  );
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString(undefined, { year: "numeric", month: "short", day: "numeric" });
}

export default function AccountPage() {
  return (
    <Suspense fallback={<Warming label="Loading dashboard…" />}>
      <AccountDashboard />
    </Suspense>
  );
}
