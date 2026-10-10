import { NextRequest, NextResponse } from "next/server";
import { usdPrices } from "@/lib/pricing";

/** One USD price for everyone - see `usdPrices`. */
export async function GET(request: NextRequest) {
  const country = (new URL(request.url).searchParams.get("country") || "US").toUpperCase();
  return NextResponse.json({ ...usdPrices(country), source: "usd_only" });
}
