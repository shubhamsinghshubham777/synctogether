"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import type { User } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";


/**
 * The Premium checkout branch shared by PricingTable and the Tier Configurator:
 * already-premium goes to /account, signed-out goes to /auth, everyone else
 * asks the server for a checkout with whichever provider is active. Keeping this in one place is what "do not duplicate
 * that logic" (see the plan) actually means - two call sites, one branch.
 */
export function usePremiumCheckout() {
  const [user, setUser] = useState<User | null>(null);
  const [isPremium, setIsPremium] = useState(false);
  const [isLoadingCheckout, setIsLoadingCheckout] = useState(false);
  const router = useRouter();
  const supabase = createClient();

  useEffect(() => {
    let ignore = false;
    async function checkAuth() {
      const {
        data: { user },
      } = await supabase.auth.getUser();
      if (ignore) return;
      setUser(user);
      if (user) {
        try {
          const { data: entData } = await supabase.rpc("my_entitlement");
          if (ignore) return;
          if (entData) {
            const ent = Array.isArray(entData) ? entData[0] : entData;
            setIsPremium(ent?.tier === "premium");
          } else {
            const { data: sub } = await supabase
              .from("subscriptions")
              .select("tier, current_period_end")
              .eq("user_id", user.id)
              .maybeSingle();
            if (ignore) return;
            if (sub?.tier === "premium") {
              const isExpired = sub.current_period_end && new Date(sub.current_period_end) < new Date();
              setIsPremium(!isExpired);
            }
          }
        } catch {
          if (!ignore) setIsPremium(false);
        }
      }
    }
    checkAuth();
    return () => {
      ignore = true;
    };
  }, [supabase]);

  async function goPremium(billingCycle: "monthly" | "annual") {
    if (isPremium) {
      router.push("/account");
      return;
    }
    if (!user) {
      router.push("/auth?redirect=/pricing");
      return;
    }
    setIsLoadingCheckout(true);
    try {
      // The server owns the user id, the customer id and the provider, so none
      // of them can be chosen by the browser.
      const res = await fetch("/api/billing/checkout", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ plan: billingCycle }),
      });
      if (res.status === 409) {
        router.push("/account");
        return;
      }
      const body = await res.json().catch(() => null);
      if (!res.ok || !body?.url) throw new Error(body?.error ?? `checkout ${res.status}`);
      window.location.assign(body.url);
    } catch (error) {
      console.error("Checkout error:", error);
      alert("Unable to open checkout. Please try again later or contact support.");
    } finally {
      setIsLoadingCheckout(false);
    }
  }

  return { user, isPremium, isLoadingCheckout, goPremium };
}
