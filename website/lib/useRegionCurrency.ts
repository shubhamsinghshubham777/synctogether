"use client";

import { useEffect, useState } from "react";
import type { PatronCurrency } from "./constants";

const CURRENCIES: PatronCurrency[] = ["USD", "INR", "PKR"];

// One lookup per page load, shared by every component that asks, so the plans
// and the configurator never fetch twice or disagree.
let pending: Promise<PatronCurrency> | null = null;

function detect(): Promise<PatronCurrency> {
  pending ??= (async () => {
    const ctrl = new AbortController();
    const timeout = setTimeout(() => ctrl.abort(), 1500);
    try {
      const res = await fetch("/api/region", { signal: ctrl.signal, cache: "no-store" });
      const currency = res.ok ? ((await res.json()) as { currency?: PatronCurrency }).currency : undefined;
      return currency && CURRENCIES.includes(currency) ? currency : "USD";
    } catch {
      // Offline, timed out or blocked: USD, the page's default.
      return "USD";
    } finally {
      clearTimeout(timeout);
    }
  })();
  return pending;
}

/** The visitor's Patron currency. `detecting` is true until it is known, so
 *  callers show a placeholder rather than flashing USD and then swapping. */
export function useRegionCurrency(): { currency: PatronCurrency; detecting: boolean } {
  const [state, setState] = useState<{ currency: PatronCurrency; detecting: boolean }>({
    currency: "USD",
    detecting: true,
  });

  useEffect(() => {
    let cancelled = false;
    detect().then((currency) => {
      // One update, so the currency and the end of loading share a render.
      if (!cancelled) setState({ currency, detecting: false });
    });
    return () => {
      cancelled = true;
    };
  }, []);

  return state;
}
