import { NextResponse, type NextRequest } from "next/server";
import { CURRENCY_COOKIE, countryFromHeaders, currencyForCountry } from "@/lib/constants";
import { updateSession } from "@/lib/supabase/middleware";

/** Only these routes read the Supabase session on the server. Everywhere else the
 *  browser client refreshes its own token, so a marketing page must not pay a
 *  Supabase round trip for a signed-in visitor. */
function needsSession(pathname: string): boolean {
  return pathname.startsWith("/account") || pathname.startsWith("/auth");
}

export async function middleware(request: NextRequest) {
  const response = needsSession(request.nextUrl.pathname) ? await updateSession(request) : NextResponse.next();

  // The visitor's Patron currency, for the pricing figures the static page
  // already holds in every currency (components/ByCurrency.tsx). Readable by the
  // layout's inline script, so it is deliberately not httpOnly; it carries a
  // currency code and nothing else. Only written when it changes.
  const currency = currencyForCountry(countryFromHeaders(request.headers));
  if (request.cookies.get(CURRENCY_COOKIE)?.value !== currency) {
    response.cookies.set(CURRENCY_COOKIE, currency, { path: "/", maxAge: 60 * 60 * 24, sameSite: "lax", secure: process.env.NODE_ENV === "production" });
  }
  return response;
}

export const config = {
  // The pages that show a price, and the two that read the session.
  matcher: ["/", "/pricing", "/account/:path*", "/auth", "/auth/:path*"],
};
