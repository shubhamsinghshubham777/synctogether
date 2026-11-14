import { createAdminClient } from "@/lib/supabase/admin";
import { seatTarget } from "@/lib/android-testers";

/** Server-only reads of the waitlist. The table has no client policy; everything goes through here. */
export async function getSeatCounts(): Promise<{ taken: number; target: number }> {
  const target = seatTarget(process.env.ANDROID_SEAT_TARGET);
  try {
    const { count, error } = await createAdminClient()
      .from("android_testers")
      .select("id", { count: "exact", head: true });
    if (error) {
      console.warn("Android seat count warning:", error.message);
      return { taken: 0, target };
    }
    return { taken: count ?? 0, target };
  } catch (err) {
    console.warn("Android seat count failed:", err);
    return { taken: 0, target };
  }
}

/** Where the open test lives once it exists; unset until the Play account does. */
export function androidTestUrl(): string | null {
  const url = (process.env.ANDROID_TEST_URL ?? "").trim();
  return /^https:\/\//.test(url) ? url : null;
}

/**
 * Cloudflare's server-side check of a Turnstile token. With no secret configured
 * (a self-hoster without captcha) the form is open, like the rest of the site.
 */
export async function turnstileOk(token: unknown, ip: string | null): Promise<boolean> {
  const secret = (process.env.TURNSTILE_SECRET_KEY ?? "").trim();
  if (!secret) return true;
  if (typeof token !== "string" || token.length === 0 || token.length > 2048) return false;
  try {
    const body = new URLSearchParams({ secret, response: token });
    if (ip) body.set("remoteip", ip);
    const res = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", {
      method: "POST",
      body,
    });
    const json = (await res.json()) as { success?: boolean };
    return json.success === true;
  } catch (err) {
    console.warn("Turnstile verify failed:", err);
    return false;
  }
}
