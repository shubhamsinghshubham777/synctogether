import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { applyEvent, type SubscriptionsDb } from "@/lib/billing/apply";
import { providerFor } from "@/lib/billing/registry";

/**
 * Every provider's subscription webhook, at `/api/billing/webhook/<provider>`.
 *
 * Verification fails closed: a missing secret, a missing or malformed signature,
 * a stale timestamp or a wrong digest all end the request before the body is
 * parsed. The decisions live in `lib/billing/` so they can be tested without a
 * database.
 */
export async function POST(
  request: Request,
  { params }: { params: Promise<{ provider: string }> }
) {
  const { provider: providerId } = await params;
  const provider = providerFor(providerId);
  if (!provider) return NextResponse.json({ error: "unknown_provider" }, { status: 404 });

  try {
    const rawBody = await request.text();
    const verdict = provider.verifyWebhook(rawBody, request.headers);
    if (!verdict.ok) {
      // A missing secret is our deployment being wrong, not the caller. 500 so
      // the provider keeps retrying and the events survive until it is fixed;
      // 401 for anything that failed on its merits.
      const status = verdict.reason === "missing_secret" ? 500 : 401;
      console.error(`${provider.id} webhook rejected: ${verdict.reason}`);
      return NextResponse.json({ error: verdict.reason }, { status });
    }

    const event = provider.parseWebhook(rawBody);
    const result = await applyEvent(createAdminClient() as unknown as SubscriptionsDb, event);
    return NextResponse.json(result.body, { status: result.status });
  } catch (error) {
    console.error(`${provider.id} webhook handling error:`, error);
    return NextResponse.json({ error: "Webhook processing error" }, { status: 500 });
  }
}
