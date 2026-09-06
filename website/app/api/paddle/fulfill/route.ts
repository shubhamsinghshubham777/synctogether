import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import {
  validateAndResolveFulfillment,
  fetchPaddleUserSubscriptions,
} from "@/lib/paddle_fulfillment";

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

    // Check if subscription row already exists
    const { data: existingSub } = await adminSupabase
      .from("subscriptions")
      .select("*")
      .eq("user_id", user.id)
      .maybeSingle();

    const apiKey = process.env.PADDLE_API_KEY;
    const isSandbox = process.env.NEXT_PUBLIC_PADDLE_ENVIRONMENT !== "production";

    const resolution = await validateAndResolveFulfillment({
      user,
      existingSub,
      paddleApiKey: apiKey,
      fetchPaddleSubs: async () => fetchPaddleUserSubscriptions(apiKey!, isSandbox),
    });

    if (!resolution.success) {
      return NextResponse.json(
        { error: resolution.error },
        { status: resolution.status }
      );
    }

    if (!resolution.shouldUpsert) {
      return NextResponse.json({
        success: true,
        subscription: resolution.subscription,
        tier: resolution.tier,
      });
    }

    // Upsert subscription only after verified active Paddle subscription
    const { data: newSub, error: upsertError } = await adminSupabase
      .from("subscriptions")
      .upsert(
        {
          user_id: user.id,
          tier: "premium",
          source: "paddle",
          current_period_end: resolution.periodEnd,
          updated_at: new Date().toISOString(),
        },
        { onConflict: "user_id" }
      )
      .select()
      .single();

    if (upsertError) {
      console.error("Failed to fulfill subscription:", upsertError);
      return NextResponse.json({ error: "Failed to update subscription" }, { status: 500 });
    }

    return NextResponse.json({
      success: true,
      subscription: newSub,
      tier: "premium",
    });
  } catch (error) {
    console.error("Fulfill subscription route error:", error);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
