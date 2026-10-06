"use server";

import { revalidatePath } from "next/cache";
import { createAdminClient } from "@/lib/supabase/admin";

export async function banRoomAction(
  roomId: string,
  reason: string,
  reportId?: string,
  notes?: string
) {
  const supabase = createAdminClient();
  const { error } = await supabase.rpc("admin_ban_room", {
    p_room_id: roomId,
    p_reason: reason,
    p_report_id: reportId || null,
    p_notes: notes || "Banned from Moderation Dashboard",
    p_ai_assisted: false,
  });

  if (error) {
    throw new Error(`Failed to ban room: ${error.message}`);
  }

  revalidatePath("/internal/moderation");
  return { success: true };
}

export async function warnUserAction(
  userId: string,
  reason: string,
  reportId?: string,
  notes?: string
) {
  const supabase = createAdminClient();
  const { error } = await supabase.rpc("admin_warn_user", {
    p_user_id: userId,
    p_reason: reason,
    p_report_id: reportId || null,
    p_notes: notes || "Warned from Moderation Dashboard",
    p_ai_assisted: false,
  });

  if (error) {
    throw new Error(`Failed to warn user: ${error.message}`);
  }

  revalidatePath("/internal/moderation");
  return { success: true };
}

export async function banUserAction(
  userId: string,
  reason: string,
  reportId?: string,
  notes?: string
) {
  const supabase = createAdminClient();
  const { error } = await supabase.rpc("admin_ban_user", {
    p_user_id: userId,
    p_reason: reason,
    p_report_id: reportId || null,
    p_notes: notes || "Banned from Moderation Dashboard",
    p_ai_assisted: false,
  });

  if (error) {
    throw new Error(`Failed to ban user: ${error.message}`);
  }

  revalidatePath("/internal/moderation");
  return { success: true };
}

export async function dismissReportAction(reportId: string, notes?: string) {
  const supabase = createAdminClient();
  const { error } = await supabase.rpc("admin_dismiss_report", {
    p_report_id: reportId,
    p_notes: notes || "Dismissed from Moderation Dashboard",
  });

  if (error) {
    throw new Error(`Failed to dismiss report: ${error.message}`);
  }

  revalidatePath("/internal/moderation");
  return { success: true };
}

export async function banRoomAndWarnUserAction(
  roomId: string,
  userId: string,
  reason: string,
  reportId?: string,
  notes?: string
) {
  const supabase = createAdminClient();

  if (roomId) {
    const { error: roomErr } = await supabase.rpc("admin_ban_room", {
      p_room_id: roomId,
      p_reason: reason,
      p_report_id: reportId || null,
      p_notes: notes || "Room banned via composite action",
      p_ai_assisted: false,
    });
    if (roomErr) throw new Error(`Failed to ban room: ${roomErr.message}`);
  }

  if (userId) {
    const { error: userErr } = await supabase.rpc("admin_warn_user", {
      p_user_id: userId,
      p_reason: reason,
      p_report_id: reportId || null,
      p_notes: notes || "User warned via composite action",
      p_ai_assisted: false,
    });
    if (userErr) throw new Error(`Failed to warn user: ${userErr.message}`);
  }

  revalidatePath("/internal/moderation");
  return { success: true };
}

export async function banRoomAndBanUserAction(
  roomId: string,
  userId: string,
  reason: string,
  reportId?: string,
  notes?: string
) {
  const supabase = createAdminClient();

  if (roomId) {
    const { error: roomErr } = await supabase.rpc("admin_ban_room", {
      p_room_id: roomId,
      p_reason: reason,
      p_report_id: reportId || null,
      p_notes: notes || "Room banned via composite action",
      p_ai_assisted: false,
    });
    if (roomErr) throw new Error(`Failed to ban room: ${roomErr.message}`);
  }

  if (userId) {
    const { error: userErr } = await supabase.rpc("admin_ban_user", {
      p_user_id: userId,
      p_reason: reason,
      p_report_id: reportId || null,
      p_notes: notes || "User banned via composite action",
      p_ai_assisted: false,
    });
    if (userErr) throw new Error(`Failed to ban user: ${userErr.message}`);
  }

  revalidatePath("/internal/moderation");
  return { success: true };
}

export async function recordAiTriageAction(
  reportId: string,
  score: number,
  action: string,
  reasoning: string
) {
  const supabase = createAdminClient();
  const { error } = await supabase.rpc("admin_record_ai_triage", {
    p_report_id: reportId,
    p_risk_score: score,
    p_recommended_action: action,
    p_reasoning: reasoning,
  });

  if (error) {
    throw new Error(`Failed to record AI triage: ${error.message}`);
  }

  revalidatePath("/internal/moderation");
  return { success: true };
}
