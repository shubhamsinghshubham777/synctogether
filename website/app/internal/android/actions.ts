"use server";

import { headers } from "next/headers";
import { revalidatePath } from "next/cache";
import { isAuthorizedLocalAccess } from "@/lib/admin-guard";
import { createAdminClient } from "@/lib/supabase/admin";

/** Stamp testers as added to the Play Console list: the given ids, or every one not yet added. */
export async function markAddedAction(ids?: number[]) {
  if (!isAuthorizedLocalAccess({ headers: await headers() })) throw new Error("Not allowed");
  let q = createAdminClient().from("android_testers").update({ added_at: new Date().toISOString() }).is("added_at", null);
  if (ids) q = q.in("id", ids);
  const { error } = await q;
  if (error) throw new Error(`Could not mark added: ${error.message}`);
  revalidatePath("/internal/android");
}

export type RewardSummary = { granted: number; no_account: number; has_plan: number; skipped: number };

/** Two weeks of Premium for the given testers (or every added, not-yet-rewarded one). Safe to press again. */
export async function grantRewardAction(ids?: number[]): Promise<RewardSummary> {
  if (!isAuthorizedLocalAccess({ headers: await headers() })) throw new Error("Not allowed");
  const db = createAdminClient();
  let targets = ids;
  if (!targets) {
    const { data, error } = await db
      .from("android_testers")
      .select("id")
      .not("added_at", "is", null)
      .is("reward_granted_at", null);
    if (error) throw new Error(`Could not list testers: ${error.message}`);
    targets = (data ?? []).map((r) => r.id as number);
  }
  const out: RewardSummary = { granted: 0, no_account: 0, has_plan: 0, skipped: 0 };
  for (const id of targets) {
    const { data, error } = await db.rpc("grant_android_tester_reward", { p_tester_id: id });
    if (error) throw new Error(`Could not grant: ${error.message}`);
    if (data === "granted") out.granted++;
    else if (data === "no_account") out.no_account++;
    else if (data === "has_plan") out.has_plan++;
    else out.skipped++;
  }
  revalidatePath("/internal/android");
  return out;
}
