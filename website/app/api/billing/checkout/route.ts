import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { activeProvider } from "@/lib/billing/registry";

/**
 * Starts a checkout with the *active* provider. The user id comes from the
 * session cookie, never from the request body - it used to be set in the
 * browser, which let a caller attach a purchase to anybody.
 */
export async function POST(request: Request) {
  try {
    const supabase = await createClient();
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

    const body = await request.json().catch(() => ({}));
    const plan = body?.plan;
    if (plan !== "monthly" && plan !== "annual") {
      return NextResponse.json({ error: "invalid_plan" }, { status: 400 });
    }

    const provider = activeProvider();
    const { data: existing } = await createAdminClient()
      .from("subscriptions")
      .select("tier, source, current_period_end, provider_customer_id")
      .eq("user_id", user.id)
      .maybeSingle();

    const premium =
      existing?.tier === "premium" &&
      (existing.current_period_end == null || new Date(existing.current_period_end) > new Date());
    if (premium) return NextResponse.json({ error: "already_premium" }, { status: 409 });

    const { url } = await provider.createCheckout({
      userId: user.id,
      email: user.email ?? undefined,
      // A customer id belongs to the provider that minted it.
      customerId:
        existing?.source === provider.id ? existing.provider_customer_id ?? undefined : undefined,
      plan,
      successUrl: `${new URL(request.url).origin}/account?subscribed=true`,
    });
    return NextResponse.json({ url });
  } catch (error) {
    console.error("Checkout route error:", error);
    return NextResponse.json({ error: "checkout_unavailable" }, { status: 502 });
  }
}
