import type { ReactNode } from "react";
import { PATRON_CURRENCIES, type PatronCurrency } from "@/lib/constants";

/**
 * A figure that depends on the visitor's currency, rendered for every currency
 * so the static page already holds the right one. The root layout's inline
 * script tags <html data-cur> from the cookie middleware sets, and globals.css
 * shows only the matching copy, so nothing waits on a fetch or a hydration and
 * nothing flashes the wrong price. Without the attribute (no JS, crawlers,
 * unknown country) USD shows, the page's default.
 */
export function ByCurrency({ render }: { render: (currency: PatronCurrency) => ReactNode }) {
  return (
    <>
      {PATRON_CURRENCIES.map((currency) => (
        <span key={currency} className="by-cur" data-c={currency}>
          {render(currency)}
        </span>
      ))}
    </>
  );
}
