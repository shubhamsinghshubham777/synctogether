"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import type { User } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import { openPaddleCheckout } from "@/components/PaddleCheckout";
import { paddlePriceIds } from "@/lib/paddle_env";


/**
 * The Premium checkout branch shared by PricingTable and the Tier Configurator:
 * already-premium goes to /account, signed-out goes to /auth, everyone else
 * opens Paddle checkout. Keeping this in one place is what "do not duplicate
 * that logic" (see the plan) actually means - two call sites, one branch.
 */
export function usePremiumCheckout() {
  const [user, setUser] = useState<User | null>(null);
  const [isPremium, setIsPremium] = useState(false);
  // Paddle customer id (`ctm_...`) for Retain. Written by the webhook, so it
  // exists for anyone who has checked out before and is null for a first
  // purchase - which is fine: Retain has nothing to act on until then.
  const [paddleCustomerId, setPaddleCustomerId] = useState<string | undefined>();
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
          const { data: custRow } = await supabase
            .from("subscriptions")
            .select("paddle_customer_id")
            .eq("user_id", user.id)
            .maybeSingle();
          if (ignore) return;
          if (custRow?.paddle_customer_id) {
            setPaddleCustomerId(custRow.paddle_customer_id);
          }

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
      const priceId =
        billingCycle === "annual" ? paddlePriceIds.annual : paddlePriceIds.monthly;
      await openPaddleCheckout({
        priceId,
        userId: user.id,
        userEmail: user.email,
        paddleCustomerId,
      });
    } finally {
      setIsLoadingCheckout(false);
    }
  }

  return { user, isPremium, isLoadingCheckout, goPremium };
}
