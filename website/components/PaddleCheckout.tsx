"use client";

import { initializePaddle, type Paddle } from "@paddle/paddle-js";

/**
 * Paddle.js initialisation and the Premium checkout overlay.
 *
 * The environment defaults to `production`, not `sandbox`. It used to be the
 * other way around in two places - the `getPaddleInstance` default parameter
 * and the `|| "sandbox"` in `openPaddleCheckout` - and `usePricing` calls
 * `getPaddleInstance()` with no arguments to read localised prices. So on any
 * deployment where NEXT_PUBLIC_PADDLE_ENVIRONMENT was unset or dropped, the
 * price preview initialised Paddle against sandbox first, the promise below
 * memoised it, and the checkout the customer then opened inherited a sandbox
 * instance while displaying live prices. Defaulting to production means a
 * missing variable fails loudly against the live catalog rather than silently
 * opening a checkout nobody gets billed through.
 */

function paddleEnvironment(): "sandbox" | "production" {
  return process.env.NEXT_PUBLIC_PADDLE_ENVIRONMENT === "sandbox"
    ? "sandbox"
    : "production";
}

let paddlePromise: Promise<Paddle | undefined> | null = null;
/** The `pwCustomer` the memoised instance was built with, so we know when it is stale. */
let initializedCustomerId: string | null = null;

/**
 * `pwCustomer` is what activates Paddle Retain against a signed-in customer.
 * It must be the Paddle customer ID (`ctm_...`) - not our Supabase user id and
 * not an email address, either of which Retain simply cannot resolve.
 *
 * Retain needs it at `Paddle.Initialize` time, but the price preview on the
 * pricing page initialises Paddle long before we know who is signed in. So the
 * instance is re-initialised once - and only once - when a customer id first
 * becomes available for an instance that was built anonymously.
 */
export function getPaddleInstance(paddleCustomerId?: string) {
  if (typeof window === "undefined") return paddlePromise;

  const customerId = paddleCustomerId ?? null;
  const needsCustomerUpgrade =
    customerId !== null && initializedCustomerId !== customerId;

  if (!paddlePromise || needsCustomerUpgrade) {
    initializedCustomerId = customerId;
    paddlePromise = initializePaddle({
      environment: paddleEnvironment(),
      token: process.env.NEXT_PUBLIC_PADDLE_CLIENT_TOKEN || "",
      ...(customerId ? { pwCustomer: { id: customerId } } : {}),
    });
  }
  return paddlePromise;
}

export async function openPaddleCheckout({
  priceId,
  userEmail,
  userId,
  paddleCustomerId,
  successUrl = "/account?subscribed=true",
}: {
  priceId: string;
  userEmail?: string;
  userId: string;
  /** Paddle customer ID (`ctm_...`) for Retain, when we already have one on file. */
  paddleCustomerId?: string;
  successUrl?: string;
}) {
  try {
    const paddle = await getPaddleInstance(paddleCustomerId);
    if (!paddle) {
      throw new Error("Failed to initialize Paddle.js");
    }

    paddle.Checkout.open({
      items: [{ priceId, quantity: 1 }],
      customer: paddleCustomerId
        ? { id: paddleCustomerId }
        : userEmail
          ? { email: userEmail }
          : undefined,
      customData: { user_id: userId },
      settings: {
        successUrl: `${window.location.origin}${successUrl}`,
        displayMode: "overlay",
        theme: "dark",
      },
    });
  } catch (error) {
    console.error("Paddle Checkout error:", error);
    // Strictly a development affordance. The old condition also fired on
    // `!token`, so a production deployment missing NEXT_PUBLIC_PADDLE_CLIENT_TOKEN
    // showed a paying customer a dialog captioned "Development Mode" and let
    // them send themselves to the success page.
    if (process.env.NODE_ENV !== "production") {
      const confirmMock = window.confirm(
        "Development Mode: Running in test/sandbox. Would you like to simulate a successful checkout redirect to /account?"
      );
      if (confirmMock) {
        window.location.href = successUrl;
      }
      return;
    }
    alert("Unable to open checkout overlay. Please try again later or contact support.");
  }
}
