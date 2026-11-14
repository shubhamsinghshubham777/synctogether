import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { normalizeEmail, parseSource, type AndroidSignupResult } from "@/lib/android-testers";
import { getSeatCounts, turnstileOk } from "@/lib/android-testers-server";

const json = (body: AndroidSignupResult | { taken: number; target: number }, status = 200) =>
  NextResponse.json(body, { status, headers: { "Cache-Control": "no-store" } });

/** The seat count the card shows (the page itself is cached; this is for the client-side cards). */
export async function GET() {
  const { taken, target } = await getSeatCounts();
  return NextResponse.json(
    { taken, target },
    { headers: { "Cache-Control": "public, s-maxage=60, stale-while-revalidate=300" } },
  );
}

export async function POST(request: Request) {
  const body = await request.json().catch(() => ({}));

  const email = normalizeEmail(body.email);
  if (!email) return json({ ok: false, error: "email" }, 400);
  if (body.consent !== true) return json({ ok: false, error: "consent" }, 400);

  const ip = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || null;
  if (!(await turnstileOk(body.token, ip))) return json({ ok: false, error: "captcha" }, 400);

  const db = createAdminClient();
  const { data: inserted, error } = await db
    .from("android_testers")
    .insert({ email, source: parseSource(body.source) })
    .select("id")
    .single();

  let id = inserted?.id as number | undefined;
  let state: "saved" | "already" = "saved";
  if (error) {
    // 23505: that address already holds a seat. Not an error to the person.
    if (error.code !== "23505") {
      console.error("Android sign-up error:", error.message);
      return json({ ok: false, error: "server" }, 500);
    }
    const { data: existing } = await db.from("android_testers").select("id").eq("email", email).single();
    id = existing?.id as number | undefined;
    state = "already";
  }
  if (id === undefined) return json({ ok: false, error: "server" }, 500);

  // The seat is the sign-up's place in line, so it never changes once printed.
  const { count: seat } = await db
    .from("android_testers")
    .select("id", { count: "exact", head: true })
    .lte("id", id);
  const { taken, target } = await getSeatCounts();
  return json({ ok: true, state, seat: seat ?? taken, taken, target });
}
