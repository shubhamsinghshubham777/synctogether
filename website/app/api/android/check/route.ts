import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { normalizeEmail, type AndroidCheckResult } from "@/lib/android-testers";

const json = (body: AndroidCheckResult | { ok: false; error: string }, status = 200) =>
  NextResponse.json(body, { status, headers: { "Cache-Control": "no-store" } });

// Best-effort per-instance limit: it only has to stop someone walking a list of addresses.
const hits = new Map<string, number[]>();
const WINDOW_MS = 60_000;
const MAX_PER_WINDOW = 8;
function limited(ip: string): boolean {
  const now = Date.now();
  const recent = (hits.get(ip) ?? []).filter((t) => now - t < WINDOW_MS);
  recent.push(now);
  hits.set(ip, recent);
  if (hits.size > 5000) hits.clear();
  return recent.length > MAX_PER_WINDOW;
}

/** "Is this address on the list, and has it been added to Google Play yet?" Nothing else is revealed. */
export async function POST(request: Request) {
  const ip = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || "unknown";
  if (limited(ip)) return json({ ok: false, error: "slow" }, 429);

  const body = await request.json().catch(() => ({}));
  const email = normalizeEmail(body.email);
  if (!email) return json({ ok: false, error: "email" }, 400);

  const db = createAdminClient();
  const { data, error } = await db.from("android_testers").select("id, added_at").eq("email", email).maybeSingle();
  if (error) {
    console.error("Android seat check error:", error.message);
    return json({ ok: false, error: "server" }, 500);
  }
  if (!data) return json({ ok: true, found: false });

  const { count } = await db.from("android_testers").select("id", { count: "exact", head: true }).lte("id", data.id);
  return json({ ok: true, found: true, seat: count ?? 0, added: data.added_at !== null });
}
