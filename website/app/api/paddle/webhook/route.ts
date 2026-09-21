import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import {
  verifyPaddleSignature,
  classifyEvent,
  shouldApplyEvent,
  resolvePeriodEnd,
  isRedundantGrant,
} from "@/lib/paddle_webhook";
import { callerAddress, classifyCaller, paddleWebhookIps } from "@/lib/paddle_ips";

/**
 * Paddle's subscription webhook.
 *
 * Verification fails closed: a missing secret, a missing or malformed
 * `paddle-signature`, a stale timestamp or a wrong digest all end the request
 * before the body is parsed. The decisions themselves live in
 * `lib/paddle_webhook.ts` so they can be tested without a database.
 *
 * Callers are also checked against Paddle's published webhook IPs, fetched
 * from https://api.paddle.com/ips rather than hard-coded. That check sits in
 * front of verification as defence in depth, never in place of it - an
 * allowlisted address still has to present a valid signature. It fails open
 * when the allowlist cannot be fetched, because dropping real subscription
 * events is worse than falling back to the signature check that already fails
 * closed.
 *
 * Revoking sets `tier` to free and dates the row rather than deleting it. The
 * row carries the Paddle ids the cancel route addresses and the event cursor
 * that makes replay safe, and deleting it threw both away - which is how a
 * redelivered `subscription.activated` could undo a cancellation.
 */
export async function POST(request: Request) {
  try {
    const address = callerAddress(request.headers);
    const sourceVerdict = classifyCaller(address, await paddleWebhookIps());
    if (sourceVerdict === "rejected") {
      // Not from Paddle. 403 and no retry semantics to worry about, since a
      // genuine Paddle delivery can never land here.
      console.warn(`Paddle webhook from non-Paddle address: ${address}`);
      return NextResponse.json({ error: "forbidden_source" }, { status: 403 });
    }
    if (sourceVerdict === "unverifiable") {
      // Logged rather than rejected - see the fail-open note above.
      console.warn(
        `Paddle webhook source could not be verified (address: ${address ?? "unknown"}); relying on signature`
      );
    }

    const rawBody = await request.text();

    const verdict = verifyPaddleSignature({
      rawBody,
      signatureHeader: request.headers.get("paddle-signature"),
      secret: process.env.PADDLE_WEBHOOK_SECRET_KEY,
    });

    if (!verdict.ok) {
      // A missing secret is our deployment being wrong, not the caller. 500 so
      // Paddle keeps retrying and the events survive until it is fixed; 401 for
      // anything that failed on its merits, which Paddle also retries but which
      // is never going to start passing.
      const status = verdict.reason === "missing_secret" ? 500 : 401;
      console.error(`Paddle webhook rejected: ${verdict.reason}`);
      return NextResponse.json({ error: verdict.reason }, { status });
    }

    const event = JSON.parse(rawBody);
    const eventType: string = event?.event_type ?? "";
    const data = event?.data ?? {};
    const userId: string | undefined = data?.custom_data?.user_id;

    if (!userId) {
      // Not an error worth retrying - a subscription with no user id attached
      // cannot be applied to anybody, so 200 stops Paddle redelivering it.
      console.warn("Paddle webhook without custom_data.user_id:", eventType);
      return NextResponse.json({ received: true });
    }

    const action = classifyEvent(eventType, data?.status);
    const supabase = createAdminClient();

    const { data: existing } = await supabase
      .from("subscriptions")
      .select("tier, current_period_end, last_event_id, last_event_at")
      .eq("user_id", userId)
      .maybeSingle();

    if (
      !shouldApplyEvent({
        eventId: event?.event_id,
        occurredAt: event?.occurred_at,
        lastEventId: existing?.last_event_id,
        lastEventAt: existing?.last_event_at,
      })
    ) {
      return NextResponse.json({ success: true, skipped: "stale_event" });
    }

    // The cursor advances even for events that change nothing, so a later
    // replay of this one cannot be mistaken for news.
    const cursor = {
      last_event_id: event?.event_id ?? null,
      last_event_at: event?.occurred_at ?? new Date().toISOString(),
      updated_at: new Date().toISOString(),
    };

    if (action === "ignore" || action === "grace") {
      if (!existing) return NextResponse.json({ success: true, action });
      const { error } = await supabase
        .from("subscriptions")
        .update(cursor)
        .eq("user_id", userId);
      if (error) {
        console.error("Failed to advance Paddle event cursor:", error);
        return NextResponse.json({ error: "Database error" }, { status: 500 });
      }
      return NextResponse.json({ success: true, action });
    }

    if (action === "revoke") {
      const { error } = await supabase
        .from("subscriptions")
        .update({
          ...cursor,
          tier: "free",
          current_period_end: new Date().toISOString(),
        })
        .eq("user_id", userId);
      if (error) {
        console.error("Failed to revoke subscription:", error);
        return NextResponse.json({ error: "Database error" }, { status: 500 });
      }
      return NextResponse.json({ success: true, action });
    }

    const periodEnd = resolvePeriodEnd(data);
    if (!periodEnd) {
      // Better to leave the row alone and be told about it than to invent a
      // month and silently record an annual plan as monthly.
      console.error(
        `Paddle ${eventType} for ${userId} carried no billing period; not granting`
      );
      return NextResponse.json({ error: "No billing period on event" }, { status: 422 });
    }

    if (isRedundantGrant(existing, periodEnd)) {
      // Nothing about entitlement changed; still move the cursor so the event
      // is not reconsidered on redelivery.
      await supabase.from("subscriptions").update(cursor).eq("user_id", userId);
      return NextResponse.json({ success: true, deduplicated: true });
    }

    const { error } = await supabase.from("subscriptions").upsert(
      {
        ...cursor,
        user_id: userId,
        tier: "premium",
        source: "paddle",
        current_period_end: periodEnd,
        paddle_subscription_id: data?.id ?? null,
        paddle_customer_id: data?.customer_id ?? null,
      },
      { onConflict: "user_id" }
    );

    if (error) {
      console.error("Failed to upsert subscription:", error);
      return NextResponse.json({ error: "Database error" }, { status: 500 });
    }

    return NextResponse.json({ success: true, action });
  } catch (error) {
    console.error("Paddle webhook handling error:", error);
    return NextResponse.json({ error: "Webhook processing error" }, { status: 500 });
  }
}
