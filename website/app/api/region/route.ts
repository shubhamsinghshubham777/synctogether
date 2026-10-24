import { NextResponse } from "next/server";
import { currencyForCountry } from "@/lib/constants";

export const dynamic = "force-dynamic";

/**
 * Which Patron currency to default the pricing picker to. Vercel sets
 * `x-vercel-ip-country` at the edge; anywhere else (local dev, another host)
 * the header is absent and this answers USD, which is also the page's default.
 * Nothing is stored or logged, and the visitor can always pick another region.
 */
export async function GET(request: Request) {
  const currency = currencyForCountry(request.headers.get("x-vercel-ip-country"));
  return NextResponse.json({ currency }, { headers: { "Cache-Control": "no-store" } });
}
