"use server";

import { revalidatePath } from "next/cache";
import { headers } from "next/headers";
import { isAuthorizedLocalAccess } from "@/lib/admin-guard";
import { createAdminClient } from "@/lib/supabase/admin";
import { normalizeVersion, reasonError, versionError } from "@/lib/bug_board_logic";

/**
 * Every action re-checks the gate itself: a Server Action is a public POST
 * endpoint, so rendering the page only on a loopback host protects nothing on
 * its own. These actions write straight to users' "Your reports", so they are
 * the part of the internal tools that must not rely on the page.
 */
export type BoardResult = { ok: true } | { ok: false; error: string };

// Shape only; whether the report exists is the database's answer.
const CODE = /^BUG-[A-Z0-9]{4}$/;

const FRIENDLY: Record<string, string> = {
  reason_required: "A reason of at least 20 characters is required.",
  fixed_in_required: "Pick the first version that has the fix.",
  fixed_in_invalid: "Use a plain version like 1.4.2.",
  fixed_before_report: "That version is older than the one this report came from.",
  original_required: "Pick the original report first.",
  unknown_original: "That original report doesn't exist any more.",
  cannot_duplicate_self: "That would make a report follow itself.",
  not_found: "That report doesn't exist any more.",
  invalid_status: "That isn't a status.",
};

async function allowed(): Promise<boolean> {
  return isAuthorizedLocalAccess({ headers: await headers() });
}

function friendly(message: string): string {
  const hit = Object.keys(FRIENDLY).find((k) => message.includes(k));
  return hit ? FRIENDLY[hit] : "Something went wrong saving that. Nothing was changed.";
}

async function setStatus(
  code: string,
  args: {
    status: "received" | "looking" | "fixed" | "wontfix" | "duplicate";
    fixedIn?: string;
    reason?: string;
    original?: string;
  },
): Promise<BoardResult> {
  const supabase = createAdminClient();
  const { error } = await supabase.rpc("admin_set_bug_status", {
    p_code: code,
    p_status: args.status,
    p_fixed_in: args.fixedIn ?? null,
    p_reason: args.reason ?? null,
    p_duplicate_of_code: args.original ?? null,
    p_public_title: null,
  });
  if (error) {
    console.error("[bug-board] status change failed", { code, status: args.status, message: error.message });
    return { ok: false, error: friendly(error.message) };
  }
  console.info("[bug-board] status changed", { code, status: args.status, original: args.original });
  revalidatePath("/internal/bugs");
  return { ok: true };
}

export async function moveBugAction(code: string, target: "received" | "looking"): Promise<BoardResult> {
  if (!(await allowed())) return { ok: false, error: "Not available here." };
  if (!CODE.test(code) || (target !== "received" && target !== "looking")) {
    return { ok: false, error: "That isn't a report." };
  }
  return setStatus(code, { status: target });
}

export async function markFixedAction(code: string, version: string): Promise<BoardResult> {
  if (!(await allowed())) return { ok: false, error: "Not available here." };
  if (!CODE.test(code)) return { ok: false, error: "That isn't a report." };
  const bad = versionError(version);
  if (bad) return { ok: false, error: bad };
  return setStatus(code, { status: "fixed", fixedIn: normalizeVersion(version) });
}

export async function closeWontFixAction(code: string, reason: string): Promise<BoardResult> {
  if (!(await allowed())) return { ok: false, error: "Not available here." };
  if (!CODE.test(code)) return { ok: false, error: "That isn't a report." };
  const bad = reasonError(reason);
  if (bad) return { ok: false, error: bad };
  return setStatus(code, { status: "wontfix", reason: reason.trim() });
}

export async function markDuplicateAction(
  code: string,
  originalCode: string,
  originalPublicTitle?: string,
): Promise<BoardResult> {
  if (!(await allowed())) return { ok: false, error: "Not available here." };
  if (!CODE.test(code) || !CODE.test(originalCode)) return { ok: false, error: "That isn't a report." };
  if (code === originalCode) return { ok: false, error: FRIENDLY.cannot_duplicate_self };

  const title = originalPublicTitle?.trim();
  if (title) {
    if (title.length > 120) return { ok: false, error: "That title is too long (120 characters at most)." };
    // The neutral title users see for the original; set before linking so the
    // link never shows a fallback label for a moment.
    const { error } = await createAdminClient()
      .from("bug_reports")
      .update({ public_title: title })
      .eq("code", originalCode);
    if (error) {
      console.error("[bug-board] public title failed", { originalCode, message: error.message });
      return { ok: false, error: friendly(error.message) };
    }
  }
  return setStatus(code, { status: "duplicate", original: originalCode });
}
