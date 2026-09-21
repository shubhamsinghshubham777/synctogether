"use client";

import { useEffect, useRef } from "react";
import { getPaddleInstance } from "@/components/PaddleCheckout";

/**
 * Resumes payment for an existing Paddle transaction named in `?_ptxn=txn_...`.
 *
 * This is what makes the account's **default payment link** work. Paddle sends
 * customers to that link and appends `_ptxn` whenever it needs them to pay an
 * existing transaction rather than start a new purchase - a failed renewal
 * being dunned by Retain, a manually-issued invoice, a checkout the customer
 * abandoned and came back to. The page has to notice the parameter and open a
 * checkout *for that transaction*; it must not open a fresh one, which would
 * bill a second subscription alongside the unpaid first.
 *
 * Without this the default payment link is a dead end: the customer lands on
 * the marketing pricing table, sees no way to settle what they owe, and the
 * subscription lapses. Nothing else on the site reads `_ptxn`, so this
 * component is the whole mechanism.
 */
export function PaddleTransactionCheckout() {
  // Strict mode mounts effects twice in development, and `Checkout.open` is not
  // idempotent - without this guard the overlay opens, closes and reopens.
  const opened = useRef(false);

  useEffect(() => {
    if (opened.current) return;

    // Read from `window` rather than `useSearchParams`, purely so this does not
    // drag the pricing page behind a Suspense boundary for a parameter that is
    // absent on virtually every visit.
    const transactionId = new URLSearchParams(window.location.search).get("_ptxn");
    if (!transactionId) return;
    opened.current = true;

    let cancelled = false;
    (async () => {
      try {
        const paddle = await getPaddleInstance();
        if (!paddle || cancelled) return;
        paddle.Checkout.open({ transactionId });
      } catch (error) {
        // Nothing user-facing to add here: the customer arrived from Paddle to
        // pay, and the alternative to a logged failure is a silent dead end.
        console.error("Could not resume Paddle transaction checkout:", error);
      }
    })();

    return () => {
      cancelled = true;
    };
  }, []);

  return null;
}
