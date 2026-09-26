import { resolveBilling, type BillingDetails, type PaddleBillingSource } from "./paddle_webhook.ts";

export interface PaddleSubscriptionItem extends PaddleBillingSource {
  id?: string;
  status?: string;
  custom_data?: {
    user_id?: string;
  };
  current_billing_period?: {
    ends_at?: string;
  };
}

export interface FulfillmentInput {
  user: { id: string } | null;
  existingSub: { tier: string; current_period_end?: string | null } | null;
  /** Injectable so the expiry branch is testable without freezing the clock. */
  now?: Date;
  paddleApiKey?: string;
  fetchPaddleSubs?: (userId: string) => Promise<{ data?: PaddleSubscriptionItem[] } | null>;
}

export interface FulfillmentResult {
  status: number;
  success: boolean;
  shouldUpsert: boolean;
  error?: string;
  subscription?: unknown;
  periodEnd?: string;
  billing?: BillingDetails;
  tier?: string;
}

export async function fetchPaddleUserSubscriptions(
  apiKey: string,
  isSandbox: boolean
): Promise<{ data?: PaddleSubscriptionItem[] } | null> {
  const paddleApiHost = isSandbox
    ? "https://sandbox-api.paddle.com"
    : "https://api.paddle.com";

  // This path polls immediately after a checkout, so the subscription being
  // looked for is the most recently created one and Paddle returns newest
  // first. That is what makes a scan survivable here where it was not in the
  // cancel route, which looks up arbitrarily old subscriptions and now
  // addresses them by the id the webhook stores.
  const res = await fetch(`${paddleApiHost}/subscriptions?per_page=50`, {
    headers: {
      Authorization: `Bearer ${apiKey}`,
    },
  });

  if (!res.ok) {
    throw new Error(`Paddle API responded with status ${res.status}`);
  }

  return res.json();
}

export async function validateAndResolveFulfillment(
  input: FulfillmentInput
): Promise<FulfillmentResult> {
  const { user, existingSub, paddleApiKey, fetchPaddleSubs, now = new Date() } = input;

  // 1. Authentication check
  if (!user || !user.id) {
    return {
      status: 401,
      success: false,
      shouldUpsert: false,
      error: "Unauthorized",
    };
  }

  // 2. Early return if the existing subscription is premium AND still current.
  //    The expiry check is the point: without it a lapsed row short-circuits
  //    this route into reporting premium forever. `effective_tier` re-checks
  //    server-side so entitlement was never actually wrong, but this endpoint
  //    was answering with a state that had stopped being true.
  const existingIsCurrent =
    existingSub?.tier === "premium" &&
    (existingSub.current_period_end == null ||
      new Date(existingSub.current_period_end) > now);

  if (existingIsCurrent && existingSub) {
    return {
      status: 200,
      success: true,
      shouldUpsert: false,
      subscription: existingSub,
      tier: "premium",
    };
  }

  // 3. API key validation
  if (!paddleApiKey || paddleApiKey.trim() === "" || paddleApiKey.includes("xxx")) {
    return {
      status: 500,
      success: false,
      shouldUpsert: false,
      error: "Paddle billing integration is unconfigured",
    };
  }

  // 4. Fetch user subscriptions from Paddle
  try {
    const fetcher = fetchPaddleSubs || (() => Promise.resolve(null));
    const response = await fetcher(user.id);
    const subs = response?.data || [];

    // Find subscription that matches user id and is in active/trialing status
    const matchedSub = subs.find((s) => {
      const matchesUser = s.custom_data?.user_id === user.id;
      const isActive = s.status === "active" || s.status === "trialing";
      return matchesUser && isActive;
    });

    if (!matchedSub) {
      return {
        status: 404,
        success: false,
        shouldUpsert: false,
        error: "No active Paddle subscription found for user",
      };
    }

    const periodEnd =
      matchedSub.current_billing_period?.ends_at ||
      new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString();

    return {
      status: 200,
      success: true,
      shouldUpsert: true,
      periodEnd,
      billing: resolveBilling(matchedSub),
      tier: "premium",
    };
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : "Paddle API verification error";
    return {
      status: 502,
      success: false,
      shouldUpsert: false,
      error: `Paddle verification failed: ${message}`,
    };
  }
}
