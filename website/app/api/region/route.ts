import { NextResponse } from "next/server";
import { countryFromHeaders, currencyForCountry } from "@/lib/constants";

export const dynamic = "force-dynamic";

/**
 * Which Patron currency to default the pricing picker to. Production is behind
 * Cloudflare, which sets `cf-ipcountry` (see `countryFromHeaders`); with no
 * geo header at all (local dev) this answers USD, the page's default.
 * Nothing is stored or logged, and the visitor can always pick another region.
 */
export async function GET(request: Request) {
  const currency = currencyForCountry(countryFromHeaders(request.headers));
  return NextResponse.json({ currency }, { headers: { "Cache-Control": "no-store" } });
}
