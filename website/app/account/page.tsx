"use client";

import { Suspense, useEffect, useRef, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import Image from "next/image";
import { GlassPanel } from "@/components/GlassPanel";
import { PTButton } from "@/components/PTButton";
import { createClient } from "@/lib/supabase/client";
import type { User } from "@supabase/supabase-js";
import confetti from "canvas-confetti";
import {
  Sparkles,
  ShieldCheck,
  Layers,
  Users,
  Video,
  Clock,
  LogOut,
  Download,
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
  const [isLoggingOut, setIsLoggingOut] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const celebratedRef = useRef(false);

  const router = useRouter();
  const searchParams = useSearchParams();
  const isSubscribedRedirect = searchParams.get("subscribed") === "true";
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
            const errDesc = hashParams.get("error_description") || hashParams.get("error") || searchParams.get("error_description") || searchParams.get("error");
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
  }, [router, supabase]);

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
                colors: ["#8B5CF6", "#C084FC", "#FBBF24", "#22D3EE"],
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
    if (!window.confirm("Are you sure you want to cancel your Premium subscription? Your account will revert to the Free tier.")) {
      return;
    }
    setIsCancelling(true);
    try {
      const res = await fetch("/api/paddle/cancel", { method: "POST" });
      if (res.ok) {
        setSubscription(null);
        const { data: entData } = await supabase.rpc("my_entitlement");
        if (entData) {
          const ent = Array.isArray(entData) ? entData[0] : entData;
          setEntitlement(ent);
        }
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
    return (
      <div className="max-w-4xl mx-auto py-24 px-4 text-center space-y-4">
        <div className="w-10 h-10 border-2 border-purple-500 border-t-transparent rounded-full animate-spin mx-auto" />
        <p className="text-sm text-gray-400">Loading your account details...</p>
      </div>
    );
  }

  const isPremium = entitlement?.tier === "premium";

  return (
    <div className="relative py-12 md:py-16 px-4 sm:px-6 lg:px-8 max-w-5xl mx-auto space-y-8">
      <div className="glow-blob-purple top-10 left-1/2 -translate-x-1/2 opacity-30" />

      {errorMsg && (
        <GlassPanel
          className="p-4 border-rose-500/30 bg-rose-950/20 text-rose-200 text-sm flex items-start justify-between gap-3 animate-in fade-in slide-in-from-top-4 duration-300"
        >
          <div className="flex items-start gap-3">
            <AlertCircle className="w-5 h-5 text-rose-400 shrink-0 mt-0.5" />
            <div>
              <h4 className="font-semibold text-rose-200">Authentication Alert</h4>
              <p className="text-xs text-rose-300/80 mt-0.5 leading-relaxed">{errorMsg}</p>
            </div>
          </div>
          <button
            type="button"
            onClick={() => setErrorMsg(null)}
            className="text-rose-400 hover:text-rose-200 p-1 rounded-lg hover:bg-rose-500/10 transition-colors cursor-pointer"
            aria-label="Dismiss alert"
          >
            <X className="w-4 h-4" />
          </button>
        </GlassPanel>
      )}

      {isSubscribedRedirect && verifying && !isPremium && (
        <GlassPanel
          className="p-6 border-purple-500/30 bg-[#1F172E] space-y-2 animate-in fade-in slide-in-from-top-4 duration-300"
        >
          <div className="flex items-center gap-3">
            <RefreshCw className="w-5 h-5 text-purple-400 animate-spin shrink-0" />
            <div>
              <h3 className="text-base font-semibold text-white font-[family-name:var(--font-space-grotesk)]">
                Verifying Subscription Status...
              </h3>
              <p className="text-xs text-purple-200/70">
                Confirming your upgrade with Paddle and activating your account benefits.
              </p>
            </div>
          </div>
        </GlassPanel>
      )}

      {isSubscribedRedirect && isPremium && (
        <GlassPanel
          glow="gold"
          className="p-6 border-amber-400/40 bg-[#1F172E] space-y-2 animate-in fade-in slide-in-from-top-4 duration-300"
        >
          <div className="flex items-center gap-3">
            <CheckCircle2 className="w-6 h-6 text-amber-300 shrink-0" />
            <div>
              <h3 className="text-lg font-bold text-white font-[family-name:var(--font-space-grotesk)]">
                Welcome to SyncTogether Premium! 🎉
              </h3>
              <p className="text-xs text-amber-200/80">
                Your subscription is active! All premium benefits are enabled on your account.
              </p>
            </div>
          </div>
        </GlassPanel>
      )}

      <GlassPanel className="p-8 space-y-6 border-purple-500/20">
        <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-6">
          <div className="flex items-center gap-4">
            {user?.user_metadata?.avatar_url ? (
              <Image
                src={user.user_metadata.avatar_url}
                alt={user.user_metadata?.full_name || "Avatar"}
                width={64}
                height={64}
                className="w-16 h-16 rounded-2xl border-2 border-purple-400/40 shadow-lg"
              />
            ) : (
              <div className="w-16 h-16 rounded-2xl bg-purple-600 flex items-center justify-center text-2xl font-bold text-white shadow-lg">
                {user?.email?.charAt(0).toUpperCase() || "U"}
              </div>
            )}
            <div>
              <div className="flex items-center gap-2">
                <h1 className="text-2xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
                  {user?.user_metadata?.full_name || "SyncTogether User"}
                </h1>
                <span
                  className={`text-xs font-bold font-mono uppercase px-2.5 py-0.5 rounded-full border ${
                    isPremium
                      ? "bg-amber-400/20 text-amber-300 border-amber-400/40"
                      : "bg-purple-500/20 text-purple-300 border-purple-400/30"
                  }`}
                >
                  {isPremium ? "★ PREMIUM" : "FREE TIER"}
                </span>
              </div>
              <p className="text-xs text-gray-400 mt-1">{user?.email}</p>
            </div>
          </div>

          <PTButton
            onClick={handleSignOut}
            variant="ghost"
            size="sm"
            isLoading={isLoggingOut}
            leftIcon={<LogOut className="w-4 h-4" />}
          >
            Sign Out
          </PTButton>
        </div>
      </GlassPanel>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        <GlassPanel
          glow={isPremium ? "gold" : "purple"}
          className={`md:col-span-2 p-8 space-y-6 flex flex-col justify-between ${
            isPremium ? "border-amber-400/40 bg-[#1A1428]" : "border-purple-500/20"
          }`}
        >
          <div className="space-y-4">
            <div className="flex items-center justify-between">
              <div>
                <span className="text-xs font-bold uppercase tracking-wider text-purple-300 font-mono">
                  Current Plan
                </span>
                <h2 className="text-3xl font-extrabold text-white font-[family-name:var(--font-space-grotesk)] mt-1">
                  SyncTogether {isPremium ? "Premium" : "Free"}
                </h2>
              </div>
              {isPremium ? (
                <Sparkles className="w-8 h-8 text-amber-400" />
              ) : (
                <Layers className="w-8 h-8 text-purple-400" />
              )}
            </div>

            {isPremium ? (
              <div className="p-4 rounded-xl bg-amber-500/10 border border-amber-400/20 space-y-2 text-xs text-amber-200">
                <p className="font-semibold text-white flex items-center gap-1.5">
                  <ShieldCheck className="w-4 h-4 text-amber-400" />
                  <span>Active Subscription</span>
                </p>
                {subscription?.current_period_end && (
                  <p className="text-gray-300">
                    Next billing / renewal date:{" "}
                    <strong>
                      {new Date(
                        subscription.current_period_end
                      ).toLocaleDateString(undefined, {
                        year: "numeric",
                        month: "long",
                        day: "numeric",
                      })}
                    </strong>
                  </p>
                )}
                <p className="text-[11px] text-gray-400">
                  To update your payment method or cancel renewal, use the link in your email receipt or contact support.
                </p>
              </div>
            ) : (
              <div className="p-4 rounded-xl bg-purple-500/10 border border-purple-400/20 space-y-2 text-xs text-purple-200">
                <p className="text-gray-300">
                  You are currently on the Free tier. Upgrade to unlock 20 persistent rooms, 16 members, and video facecams.
                </p>
              </div>
            )}
          </div>

          <div className="pt-4 flex flex-wrap items-center gap-4">
            {isPremium ? (
              <>
                <button
                  onClick={handleCancelSubscription}
                  disabled={isCancelling}
                  className="inline-flex items-center gap-2 px-4 py-2 rounded-xl bg-red-500/10 hover:bg-red-500/20 text-red-300 hover:text-red-200 text-xs font-semibold border border-red-500/30 transition-all cursor-pointer disabled:opacity-50"
                >
                  {isCancelling ? (
                    <>
                      <RefreshCw className="w-3.5 h-3.5 animate-spin" />
                      <span>Cancelling...</span>
                    </>
                  ) : (
                    <span>Cancel Subscription</span>
                  )}
                </button>
                <a
                  href="mailto:support@synctogether.app?subject=Subscription%20Support"
                  className="inline-flex items-center gap-2 px-4 py-2 rounded-xl bg-white/5 hover:bg-white/10 text-gray-300 hover:text-white text-xs font-semibold border border-white/10 transition-colors"
                >
                  <span>Contact Support</span>
                </a>
              </>
            ) : (
              <PTButton
                href="/pricing"
                variant="gold"
                size="md"
                leftIcon={<Sparkles className="w-4 h-4" />}
              >
                Upgrade to Premium
              </PTButton>
            )}
          </div>
        </GlassPanel>

        <GlassPanel className="p-6 space-y-4 border-purple-500/20 flex flex-col justify-between">
          <div className="space-y-3">
            <h3 className="text-xs font-bold uppercase tracking-wider text-gray-400 font-mono">
              Account Caps &amp; Quotas
            </h3>
            <ul className="space-y-3 text-xs text-gray-300">
              <li className="flex items-center justify-between border-b border-white/5 pb-2">
                <span className="flex items-center gap-2">
                  <Layers className="w-3.5 h-3.5 text-purple-400" /> Active Rooms
                </span>
                <span className="font-bold text-white">
                  {entitlement?.max_live_rooms ?? 4}
                </span>
              </li>
              <li className="flex items-center justify-between border-b border-white/5 pb-2">
                <span className="flex items-center gap-2">
                  <Users className="w-3.5 h-3.5 text-purple-400" /> Max Members
                </span>
                <span className="font-bold text-white">
                  {entitlement?.max_members ?? 8}
                </span>
              </li>
              <li className="flex items-center justify-between border-b border-white/5 pb-2">
                <span className="flex items-center gap-2">
                  <Clock className="w-3.5 h-3.5 text-purple-400" /> Session Limit
                </span>
                <span className="font-bold text-white">
                  {entitlement?.max_total_session_minutes
                    ? `${entitlement.max_total_session_minutes / 60}h`
                    : entitlement?.max_session_minutes
                    ? `${entitlement.max_session_minutes / 60}h`
                    : "4h"}
                </span>
              </li>
              <li className="flex items-center justify-between border-b border-white/5 pb-2">
                <span className="flex items-center gap-2">
                  <Video className="w-3.5 h-3.5 text-purple-400" /> Facecams
                </span>
                <span className="font-bold text-white">
                  {entitlement?.av_level === "video"
                    ? "Video + Voice"
                    : entitlement?.av_level === "voice"
                    ? "Voice"
                    : "None"}
                </span>
              </li>
              <li className="flex items-center justify-between border-b border-white/5 pb-2">
                <span className="flex items-center gap-2">
                  <Sparkles className="w-3.5 h-3.5 text-purple-400" /> Persistent Rooms
                </span>
                <span className="font-bold text-white">
                  {(entitlement?.persistent_room_cap ?? 0) > 0
                    ? `${entitlement?.persistent_room_cap}`
                    : "0 (24h nap)"}
                </span>
              </li>
            </ul>
          </div>

          <div className="pt-2">
            <button
              onClick={handleExportData}
              className="text-[11px] text-gray-400 hover:text-purple-300 flex items-center gap-1.5 transition-colors cursor-pointer"
            >
              <Download className="w-3.5 h-3.5" />
              <span>Export Account Data</span>
            </button>
          </div>
        </GlassPanel>
      </div>
    </div>
  );
}

export default function AccountPage() {
  return (
    <Suspense
      fallback={
        <div className="max-w-4xl mx-auto py-24 text-center text-sm text-gray-400">
          Loading dashboard...
        </div>
      }
    >
      <AccountDashboard />
    </Suspense>
  );
}
