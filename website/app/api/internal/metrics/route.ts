import { NextResponse } from "next/server";
import { isAuthorizedLocalAccess } from "@/lib/admin-guard";
import { getDashboardMetrics } from "@/lib/metrics";
import { ProductionCredentialsError } from "@/lib/supabase/admin";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  // Enforce local-only access or valid secret token (returns 404 otherwise)
  if (!isAuthorizedLocalAccess(request)) {
    return new Response("Not Found", { status: 404 });
  }

  try {
    const metrics = await getDashboardMetrics();
    return NextResponse.json(metrics, {
      headers: {
        "Cache-Control": "no-store, max-age=0, must-revalidate",
      },
    });
  } catch (error) {
    if (error instanceof ProductionCredentialsError) {
      return NextResponse.json(
        {
          error: "Production Credentials Required",
          code: error.code,
          message: error.message,
          resolution: error.resolution,
        },
        { status: 428 }
      );
    }

    console.error("Internal metrics API error:", error);
    return NextResponse.json(
      { error: "Failed to gather internal metrics" },
      { status: 500 }
    );
  }
}
