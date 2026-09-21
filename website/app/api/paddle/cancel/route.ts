import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { paddleApiHost, isPaddleApiKeyUsable } from "@/lib/paddle_env";

/**
 * Cancels the caller's subscription at the end of the period they have paid
 * for.
 *
 * Two things changed here, and both were capable of costing real money.
 *
 * It used to fetch an unfiltered `per_page=20` page of *every* subscription on
 * the account and scan it for one whose `custom_data.user_id` matched. Paddle
 * returns newest first, so from the twenty-first customer onwards the match
 * simply was not in the response - and the local row was deleted regardless,
 * because the Paddle call's failure was only `console.warn`ed. The customer
 * lost access in the app and carried on being billed. The subscription id is
 * now stored on the row by the webhook and addressed directly.
 *
 * It also cancelled `immediately`, which threw away the remainder of a month
 * the customer had already paid for - a refund magnet, and a consumer-law
 * problem in the EU and UK where Paddle is merchant of record. It now cancels
 * at the next billing period and leaves the row intact; `effective_tier`
 * expires it on `current_period_end`, and Paddle's `subscription.canceled`
 * arrives at that boundary to flip the tier.
 */
export async function POST() {
  try {
    const supabase = await createClient();
    const {
      data: { user },
    } = await supabase.auth.getUser();

    if (!user) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    const adminSupabase = createAdminClient();
    const { data: existing } = await adminSupabase
      .from("subscriptions")
      .select("source, tier, current_period_end, paddle_subscription_id")
      .eq("user_id", user.id)
      .maybeSingle();

    if (!existing || existing.tier !== "premium") {
      return NextResponse.json({ success: true, tier: "free" });
    }

    // Manual and debug grants have no Paddle subscription behind them, so there
    // is nothing to cancel remotely and clearing the row locally is correct.
    if (existing.source !== "paddle") {
      const { error } = await adminSupabase
        .from("subscriptions")
        .delete()
        .eq("user_id", user.id);
      if (error) {
        console.error("Failed to clear non-Paddle subscription:", error);
        return NextResponse.json({ error: "Failed to update subscription" }, { status: 500 });
      }
      return NextResponse.json({ success: true, tier: "free" });
    }

    if (!existing.paddle_subscription_id) {
      // A Paddle-sourced row with no subscription id predates the webhook
      // recording one. Deleting it locally would leave Paddle billing them, so
      // this has to be a visible failure rather than a silent one.
      console.error(`Paddle subscription id missing for user ${user.id}`);
      return NextResponse.json(
        { error: "subscription_unlinked" },
        { status: 409 }
      );
    }

    if (!isPaddleApiKeyUsable()) {
      console.error("Cancellation attempted with no usable Paddle API key");
      return NextResponse.json({ error: "billing_unconfigured" }, { status: 500 });
    }

    const res = await fetch(
      `${paddleApiHost()}/subscriptions/${existing.paddle_subscription_id}/cancel`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${process.env.PADDLE_API_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ effective_from: "next_billing_period" }),
      }
    );

    if (!res.ok) {
      // Never clear the local row when Paddle did not accept the cancellation -
      // that is the combination that bills somebody for access they no longer
      // have.
      const body = await res.text();
      console.error(`Paddle cancellation failed (${res.status}): ${body}`);
      return NextResponse.json({ error: "cancellation_failed" }, { status: 502 });
    }

    // The row stays premium until `current_period_end`, which is what the
    // customer paid for. Paddle's `subscription.canceled` closes it out.
    return NextResponse.json({
      success: true,
      tier: "premium",
      cancelsAt: existing.current_period_end,
      scheduled: true,
    });
  } catch (error) {
    console.error("Cancel subscription route error:", error);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
