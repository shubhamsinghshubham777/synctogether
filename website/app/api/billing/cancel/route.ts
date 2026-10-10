import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { providerFor } from "@/lib/billing/registry";

/**
 * Cancels the caller's subscription at the end of the period they have paid
 * for, dispatching on the row's `source` - never on the active provider, since
 * a subscriber may well be with the one we no longer sell through.
 *
 * Two things here were each capable of costing real money:
 *  - It addresses the subscription by the id the webhook stored. It used to scan
 *    an unfiltered page of every subscription on the account, so from the
 *    twenty-first customer on the match was not in the response - and the local
 *    row was deleted anyway. The customer lost access and kept being billed.
 *  - It cancels at the next billing period, not `immediately`, which threw away
 *    a month already paid for. The row stays premium until `current_period_end`
 *    and the provider's own `canceled` event closes it out at that boundary.
 *
 * A failed remote call never touches the local row.
 */
export async function POST() {
  try {
    const supabase = await createClient();
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

    const admin = createAdminClient();
    const { data: existing } = await admin
      .from("subscriptions")
      .select("source, tier, current_period_end, provider_subscription_id")
      .eq("user_id", user.id)
      .maybeSingle();

    if (!existing || existing.tier !== "premium") {
      return NextResponse.json({ success: true, tier: "free" });
    }

    const provider = providerFor(existing.source);

    // Manual and debug grants have no provider subscription behind them, so
    // there is nothing to cancel remotely and clearing the row is correct.
    if (!provider && existing.source !== "manual" && existing.source !== "debug") {
      // A provider we no longer speak to. Clearing the row locally would leave
      // that provider billing them, so this is a visible failure.
      console.error(`Unknown billing source "${existing.source}" for user ${user.id}`);
      return NextResponse.json({ error: "unsupported_provider" }, { status: 409 });
    }

    if (!provider) {
      const { error } = await admin.from("subscriptions").delete().eq("user_id", user.id);
      if (error) {
        console.error("Failed to clear non-provider subscription:", error);
        return NextResponse.json({ error: "Failed to update subscription" }, { status: 500 });
      }
      return NextResponse.json({ success: true, tier: "free" });
    }

    if (!provider) return NextResponse.json({ error: "unsupported_provider" }, { status: 409 });

    if (!existing.provider_subscription_id) {
      // Deleting it locally would leave the provider billing them, so this has
      // to be a visible failure rather than a silent one.
      console.error(`${provider.id} subscription id missing for user ${user.id}`);
      return NextResponse.json({ error: "subscription_unlinked" }, { status: 409 });
    }
    if (!provider.isConfigured()) {
      console.error(`Cancellation attempted with ${provider.id} unconfigured`);
      return NextResponse.json({ error: "billing_unconfigured" }, { status: 500 });
    }

    const result = await provider.cancelAtPeriodEnd(existing.provider_subscription_id);
    if (!result.ok) {
      return NextResponse.json({ error: "cancellation_failed" }, { status: 502 });
    }

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
