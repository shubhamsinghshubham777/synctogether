import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { applyEvent, type SubscriptionsDb } from "@/lib/billing/apply";
import { resolveFulfillment } from "@/lib/billing/fulfill";
import { activeProvider, providerFor } from "@/lib/billing/registry";

export async function POST(request: Request) {
  try {
    const supabase = await createClient();
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

    const admin = createAdminClient();
    const { data: existingSub } = await admin
      .from("subscriptions")
      .select("*")
      .eq("user_id", user.id)
      .maybeSingle();

    // A row's own provider wins over the active one: the subscriber may be with
    // the provider we no longer sell through.
    const provider = providerFor(existingSub?.source) ?? activeProvider();
    const checkoutId = new URL(request.url).searchParams.get("checkout_id") ?? undefined;

    const resolution = await resolveFulfillment({
      user,
      existingSub,
      configured: provider.isConfigured(),
      lookup: () => provider.findActiveSubscription(user.id, { checkoutId }),
    });

    if (!resolution.success) {
      return NextResponse.json(
        { error: resolution.error, pending: resolution.pending },
        { status: resolution.status }
      );
    }
    if (!resolution.event) {
      return NextResponse.json({
        success: true,
        subscription: resolution.subscription,
        tier: resolution.tier,
      });
    }

    const result = await applyEvent(admin as unknown as SubscriptionsDb, resolution.event);
    if (result.status >= 400) return NextResponse.json(result.body, { status: result.status });

    const { data: subscription } = await admin
      .from("subscriptions")
      .select("*")
      .eq("user_id", user.id)
      .maybeSingle();
    return NextResponse.json({ success: true, subscription, tier: "premium" });
  } catch (error) {
    console.error("Fulfill subscription route error:", error);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
