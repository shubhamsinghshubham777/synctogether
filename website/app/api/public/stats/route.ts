import { NextResponse } from "next/server";
import { getPublicStats } from "@/lib/public-metrics";

export const revalidate = 3600;

export async function GET() {
  try {
    const stats = await getPublicStats();
    if (!stats.publishable) {
      return NextResponse.json({ publishable: false });
    }
    return NextResponse.json(stats);
  } catch {
    return NextResponse.json({ publishable: false });
  }
}
