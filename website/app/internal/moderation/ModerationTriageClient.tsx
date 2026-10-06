"use client";

import { useState, useTransition } from "react";
import {
  AlertTriangle,
  Ban,
  CheckCircle2,
  Copy,
  ExternalLink,
  Film,
  MessageSquare,
  ShieldAlert,
  ShieldCheck,
  UserCheck,
  UserX,
  XCircle,
} from "lucide-react";
import { formatPromptForAgent, type HeuristicEvaluation } from "@/lib/moderation-heuristics";
import {
  banRoomAction,
  warnUserAction,
  banUserAction,
  dismissReportAction,
  banRoomAndWarnUserAction,
  banRoomAndBanUserAction,
} from "./actions";

export interface ModerationReportItem {
  id: string;
  reason: string;
  status: string;
  source: string;
  createdAt: string;
  room?: { id?: string; code?: string; isBanned?: boolean; endedAt?: string | null } | null;
  reporter?: { id?: string; displayName?: string; email?: string } | null;
  reported?: {
    id?: string;
    displayName?: string;
    email?: string;
    strikesCount?: number;
    moderationStatus?: string;
    warningReason?: string | null;
    banReason?: string | null;
  } | null;
  media?: {
    kind?: string | null;
    title?: string | null;
    url?: string | null;
  } | null;
  messageExcerpt?: string | null;
  details?: string | null;
  heuristics: HeuristicEvaluation;
}

interface Props {
  reports: ModerationReportItem[];
}

export function ModerationTriageClient({ reports }: Props) {
  const [filter, setFilter] = useState<"all" | "open" | "copyright" | "high_risk" | "actioned" | "dismissed">("open");
  const [isPending, startTransition] = useTransition();
  const [copiedId, setCopiedId] = useState<string | null>(null);
  const [activeActionModal, setActiveActionModal] = useState<{
    reportId: string;
    actionType: "warn" | "ban_user" | "ban_room" | "ban_both_warn" | "ban_both_ban" | "dismiss";
    userId?: string;
    roomId?: string;
    title: string;
    defaultReason: string;
  } | null>(null);

  const [reasonInput, setReasonInput] = useState("");
  const [notesInput, setNotesInput] = useState("");

  const filteredReports = reports.filter((r) => {
    if (filter === "open") return r.status === "open" || r.status === "reviewing";
    if (filter === "copyright") return r.reason === "copyright";
    if (filter === "high_risk") return r.heuristics.riskScore >= 60;
    if (filter === "actioned") return r.status === "actioned";
    if (filter === "dismissed") return r.status === "dismissed";
    return true;
  });

  const handleCopyPrompt = (report: ModerationReportItem) => {
    const text = formatPromptForAgent({
      id: report.id,
      reason: report.reason,
      createdAt: report.createdAt,
      reporter: report.reporter,
      reported: report.reported,
      room: report.room,
      media: report.media,
      messageExcerpt: report.messageExcerpt,
      details: report.details,
      heuristics: report.heuristics,
    });
    navigator.clipboard.writeText(text);
    setCopiedId(report.id);
    setTimeout(() => setCopiedId(null), 2500);
  };

  const openAction = (
    report: ModerationReportItem,
    type: "warn" | "ban_user" | "ban_room" | "ban_both_warn" | "ban_both_ban" | "dismiss"
  ) => {
    let title = "";
    let defaultReason = "";

    if (type === "warn") {
      title = `Issue Strike 1 Warning to ${report.reported?.displayName || "User"}`;
      defaultReason = `Copyright/guidelines violation: ${report.reason} in room ${report.room?.code || ""}`;
    } else if (type === "ban_user") {
      title = `Suspend Account for ${report.reported?.displayName || "User"} (Indefinite Ban)`;
      defaultReason = `Repeat or severe copyright/anti-piracy violation`;
    } else if (type === "ban_room") {
      title = `Terminate and Ban Room ${report.room?.code || ""}`;
      defaultReason = `Room terminated for copyright infringement`;
    } else if (type === "ban_both_warn") {
      title = `Ban Room ${report.room?.code || ""} & Issue Strike 1 Warning to Host`;
      defaultReason = `Unauthorized media streaming / piracy in room ${report.room?.code || ""}`;
    } else if (type === "ban_both_ban") {
      title = `Ban Room ${report.room?.code || ""} & Suspend Host Account (Strike 2)`;
      defaultReason = `Repeated unauthorized media distribution / piracy`;
    } else {
      title = `Dismiss Report`;
      defaultReason = `No violation found`;
    }

    setActiveActionModal({
      reportId: report.id,
      actionType: type,
      userId: report.reported?.id,
      roomId: report.room?.id,
      title,
      defaultReason,
    });
    setReasonInput(defaultReason);
    setNotesInput("");
  };

  const submitAction = () => {
    if (!activeActionModal) return;
    const { reportId, actionType, userId, roomId } = activeActionModal;
    const reason = reasonInput.trim() || activeActionModal.defaultReason;
    const notes = notesInput.trim() || undefined;

    startTransition(async () => {
      try {
        if (actionType === "warn" && userId) {
          await warnUserAction(userId, reason, reportId, notes);
        } else if (actionType === "ban_user" && userId) {
          await banUserAction(userId, reason, reportId, notes);
        } else if (actionType === "ban_room" && roomId) {
          await banRoomAction(roomId, reason, reportId, notes);
        } else if (actionType === "ban_both_warn" && roomId && userId) {
          await banRoomAndWarnUserAction(roomId, userId, reason, reportId, notes);
        } else if (actionType === "ban_both_ban" && roomId && userId) {
          await banRoomAndBanUserAction(roomId, userId, reason, reportId, notes);
        } else if (actionType === "dismiss") {
          await dismissReportAction(reportId, notes);
        }
        setActiveActionModal(null);
      } catch (err: any) {
        alert(err.message || "Failed to execute moderation action");
      }
    });
  };

  return (
    <div className="space-y-6">
      {/* Filter Tabs */}
      <div className="flex flex-wrap gap-2 border-b border-rail pb-3">
        {[
          { id: "open", label: "Open / Triage", count: reports.filter((r) => r.status === "open").length },
          { id: "copyright", label: "Copyright & Piracy", count: reports.filter((r) => r.reason === "copyright").length },
          { id: "high_risk", label: "High Risk (>60%)", count: reports.filter((r) => r.heuristics.riskScore >= 60).length },
          { id: "actioned", label: "Actioned", count: reports.filter((r) => r.status === "actioned").length },
          { id: "dismissed", label: "Dismissed", count: reports.filter((r) => r.status === "dismissed").length },
          { id: "all", label: "All Reports", count: reports.length },
        ].map((t) => (
          <button
            key={t.id}
            onClick={() => setFilter(t.id as any)}
            className={`px-3 py-1.5 rounded-lg text-xs font-mono font-medium transition-colors flex items-center gap-2 ${
              filter === t.id
                ? "bg-purple-600 text-white shadow-sm"
                : "bg-aisle/60 text-gray-300 hover:bg-aisle border border-rail/40"
            }`}
          >
            {t.label}
            <span
              className={`px-1.5 py-0.5 rounded text-[10px] ${
                filter === t.id ? "bg-purple-900/70 text-purple-200" : "bg-black/30 text-gray-400"
              }`}
            >
              {t.count}
            </span>
          </button>
        ))}
      </div>

      {/* Reports List */}
      {filteredReports.length === 0 ? (
        <div className="p-12 text-center rounded-xl bg-aisle/30 border border-rail/60 space-y-2">
          <ShieldCheck className="w-10 h-10 text-emerald-400 mx-auto opacity-80" />
          <h3 className="text-base font-semibold text-gray-200">No reports in this category</h3>
          <p className="text-xs text-gray-400">The queue is clean. Check other filters or return later.</p>
        </div>
      ) : (
        <div className="space-y-4">
          {filteredReports.map((report) => {
            const h = report.heuristics;
            const isActioned = report.status === "actioned" || report.status === "dismissed";
            const strikes = report.reported?.strikesCount ?? 0;
            const status = report.reported?.moderationStatus || "clean";

            return (
              <div
                key={report.id}
                className="p-5 rounded-xl bg-aisle/70 border border-rail transition-all hover:border-purple-500/40 space-y-4"
              >
                {/* Header row */}
                <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2 border-b border-rail/50 pb-3">
                  <div className="flex items-center gap-2.5">
                    <span
                      className={`px-2 py-0.5 rounded text-[10px] font-mono uppercase tracking-wider font-bold ${
                        report.status === "open"
                          ? "bg-amber-500/20 text-amber-300 border border-amber-500/30"
                          : report.status === "actioned"
                          ? "bg-emerald-500/20 text-emerald-300 border border-emerald-500/30"
                          : "bg-gray-700/40 text-gray-400 border border-gray-600/30"
                      }`}
                    >
                      {report.status}
                    </span>

                    <span
                      className={`px-2 py-0.5 rounded text-[10px] font-mono font-medium ${
                        report.reason === "copyright"
                          ? "bg-purple-500/20 text-purple-300 border border-purple-500/30"
                          : "bg-blue-500/20 text-blue-300 border border-blue-500/30"
                      }`}
                    >
                      {report.reason.toUpperCase()}
                    </span>

                    <span className="text-xs font-mono text-gray-400">ID: {report.id.slice(0, 8)}…</span>
                  </div>

                  <div className="text-xs font-mono text-gray-400">
                    {new Date(report.createdAt).toLocaleString()}
                  </div>
                </div>

                {/* Content grid */}
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 text-xs font-mono">
                  {/* Target Column */}
                  <div className="p-3 rounded-lg bg-black/25 border border-rail/40 space-y-2">
                    <div className="text-[11px] font-bold text-gray-400 uppercase tracking-wider">Reported User</div>
                    <div className="text-sm font-semibold text-gray-100 flex items-center justify-between">
                      <span className="truncate">{report.reported?.displayName || "Unknown User"}</span>
                      {status === "banned" ? (
                        <span className="px-1.5 py-0.5 rounded bg-red-900/60 text-red-300 text-[10px] border border-red-500/40">
                          BANNED
                        </span>
                      ) : strikes > 0 ? (
                        <span className="px-1.5 py-0.5 rounded bg-amber-900/60 text-amber-300 text-[10px] border border-amber-500/40">
                          STRIKE {strikes}/2
                        </span>
                      ) : (
                        <span className="px-1.5 py-0.5 rounded bg-emerald-900/60 text-emerald-300 text-[10px] border border-emerald-500/40">
                          CLEAN (0/2)
                        </span>
                      )}
                    </div>
                    <div className="text-[11px] text-gray-400 truncate">ID: {report.reported?.id || "N/A"}</div>
                    {report.reporter?.displayName && (
                      <div className="text-[10px] text-gray-500 pt-1 border-t border-rail/30">
                        Filed by: {report.reporter.displayName}
                      </div>
                    )}
                  </div>

                  {/* Media Snapshot Column */}
                  <div className="p-3 rounded-lg bg-black/25 border border-rail/40 space-y-2">
                    <div className="text-[11px] font-bold text-gray-400 uppercase tracking-wider flex items-center gap-1.5">
                      <Film className="w-3.5 h-3.5 text-purple-400" />
                      Media &amp; Room Evidence
                    </div>
                    <div>
                      <div className="text-[10px] text-gray-400">Room Code:</div>
                      <div className="text-xs font-bold text-purple-300 flex items-center gap-2">
                        {report.room?.code || "N/A"}
                        {report.room?.isBanned && (
                          <span className="px-1.5 py-0.2 rounded bg-red-900/60 text-red-300 text-[9px]">ROOM BANNED</span>
                        )}
                      </div>
                    </div>
                    <div>
                      <div className="text-[10px] text-gray-400">Media Title:</div>
                      <div className="text-xs font-semibold text-gray-200 truncate" title={report.media?.title || ""}>
                        {report.media?.title || "No media title logged"}
                      </div>
                    </div>
                    {report.media?.url && (
                      <div className="truncate text-[10px] text-gray-400">
                        URL: <span className="text-purple-300">{report.media.url}</span>
                      </div>
                    )}
                  </div>

                  {/* Heuristic / AI Risk Box */}
                  <div className="p-3 rounded-lg bg-purple-950/20 border border-purple-500/30 space-y-2">
                    <div className="text-[11px] font-bold text-purple-300 uppercase tracking-wider flex items-center justify-between">
                      <span>Heuristic Piracy Score</span>
                      <span
                        className={`px-2 py-0.5 rounded text-[10px] font-bold ${
                          h.riskScore >= 75
                            ? "bg-red-500 text-white"
                            : h.riskScore >= 45
                            ? "bg-amber-500 text-black"
                            : "bg-emerald-600 text-white"
                        }`}
                      >
                        {h.riskScore}%
                      </span>
                    </div>
                    <div className="text-[11px] text-gray-300 leading-snug">{h.reasoning}</div>
                    {h.detectedPatterns.length > 0 && (
                      <div className="flex flex-wrap gap-1 pt-1">
                        {h.detectedPatterns.map((pat, idx) => (
                          <span
                            key={idx}
                            className="px-1.5 py-0.5 rounded bg-purple-900/50 text-purple-200 text-[9px] border border-purple-400/20"
                          >
                            {pat}
                          </span>
                        ))}
                      </div>
                    )}
                  </div>
                </div>

                {/* Excerpt or details */}
                {(report.messageExcerpt || report.details) && (
                  <div className="p-3 rounded-lg bg-black/40 border border-rail/40 text-xs font-mono space-y-1">
                    {report.messageExcerpt && (
                      <div>
                        <span className="text-gray-400 text-[10px] uppercase tracking-wide">Reported Message: </span>
                        <span className="text-gray-200 italic">&ldquo;{report.messageExcerpt}&rdquo;</span>
                      </div>
                    )}
                    {report.details && (
                      <div>
                        <span className="text-gray-400 text-[10px] uppercase tracking-wide">Reporter Details: </span>
                        <span className="text-gray-200">&ldquo;{report.details}&rdquo;</span>
                      </div>
                    )}
                  </div>
                )}

                {/* Action Bar */}
                <div className="flex flex-wrap items-center justify-between gap-3 pt-2 border-t border-rail/40">
                  {/* Left: AI prompt copy */}
                  <button
                    onClick={() => handleCopyPrompt(report)}
                    className="px-3 py-1.5 rounded-lg bg-aisle/80 hover:bg-aisle border border-rail text-xs font-mono text-gray-300 hover:text-white flex items-center gap-1.5 transition-colors"
                  >
                    <Copy className="w-3.5 h-3.5" />
                    {copiedId === report.id ? "Copied Incident Dossier!" : "Copy Prompt for AI Agent"}
                  </button>

                  {/* Right: Swift Action Buttons */}
                  {!isActioned && (
                    <div className="flex flex-wrap items-center gap-2">
                      <button
                        onClick={() => openAction(report, "dismiss")}
                        disabled={isPending}
                        className="px-3 py-1.5 rounded-lg bg-gray-800/80 hover:bg-gray-700 text-gray-300 text-xs font-mono font-medium border border-gray-600/40 transition-colors"
                      >
                        Dismiss
                      </button>

                      {report.room?.id && !report.room?.isBanned && (
                        <button
                          onClick={() => openAction(report, "ban_room")}
                          disabled={isPending}
                          className="px-3 py-1.5 rounded-lg bg-amber-950/60 hover:bg-amber-900 text-amber-200 text-xs font-mono font-medium border border-amber-600/40 flex items-center gap-1 transition-colors"
                        >
                          <Ban className="w-3.5 h-3.5" />
                          Ban Room
                        </button>
                      )}

                      {report.reported?.id && status !== "banned" && (
                        <button
                          onClick={() => openAction(report, "warn")}
                          disabled={isPending}
                          className="px-3 py-1.5 rounded-lg bg-amber-600/80 hover:bg-amber-500 text-white text-xs font-mono font-medium flex items-center gap-1 transition-colors shadow-sm"
                        >
                          <AlertTriangle className="w-3.5 h-3.5" />
                          Issue Strike 1
                        </button>
                      )}

                      {/* Composite quick action: Ban Room + Strike */}
                      {report.room?.id && !report.room?.isBanned && report.reported?.id && status !== "banned" && (
                        <button
                          onClick={() => openAction(report, strikes >= 1 ? "ban_both_ban" : "ban_both_warn")}
                          disabled={isPending}
                          className="px-3 py-1.5 rounded-lg bg-purple-600 hover:bg-purple-500 text-white text-xs font-mono font-bold flex items-center gap-1 transition-colors shadow-sm"
                        >
                          <ShieldAlert className="w-3.5 h-3.5" />
                          {strikes >= 1 ? "Ban Room & Ban User" : "Ban Room & Warn"}
                        </button>
                      )}

                      {report.reported?.id && status !== "banned" && (
                        <button
                          onClick={() => openAction(report, "ban_user")}
                          disabled={isPending}
                          className="px-3 py-1.5 rounded-lg bg-red-700 hover:bg-red-600 text-white text-xs font-mono font-medium flex items-center gap-1 transition-colors"
                        >
                          <UserX className="w-3.5 h-3.5" />
                          Ban Account
                        </button>
                      )}
                    </div>
                  )}

                  {isActioned && (
                    <div className="text-xs font-mono text-gray-500 flex items-center gap-1">
                      <CheckCircle2 className="w-4 h-4 text-emerald-400" />
                      Resolution recorded
                    </div>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* Action Confirmation Modal */}
      {activeActionModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-sm animate-fade-in">
          <div className="w-full max-w-lg p-6 rounded-2xl bg-aisle border border-rail shadow-2xl space-y-4 font-mono">
            <div className="flex items-center justify-between border-b border-rail pb-3">
              <h3 className="text-base font-bold text-screen flex items-center gap-2">
                <ShieldAlert className="w-5 h-5 text-purple-400" />
                {activeActionModal.title}
              </h3>
              <button
                onClick={() => setActiveActionModal(null)}
                className="text-gray-400 hover:text-white transition-colors"
              >
                ✕
              </button>
            </div>

            <div className="space-y-3">
              <div>
                <label className="text-xs text-gray-400 uppercase tracking-wider block mb-1">
                  Enforcement Reason (Saved to Record)
                </label>
                <textarea
                  rows={2}
                  value={reasonInput}
                  onChange={(e) => setReasonInput(e.target.value)}
                  className="w-full p-2.5 rounded-lg bg-black/40 border border-rail text-xs text-gray-200 focus:outline-none focus:border-purple-500"
                />
              </div>

              <div>
                <label className="text-xs text-gray-400 uppercase tracking-wider block mb-1">
                  Moderator Notes (Optional Internal Log)
                </label>
                <input
                  type="text"
                  placeholder="e.g. Verified infringing video stream on R2"
                  value={notesInput}
                  onChange={(e) => setNotesInput(e.target.value)}
                  className="w-full p-2.5 rounded-lg bg-black/40 border border-rail text-xs text-gray-200 focus:outline-none focus:border-purple-500"
                />
              </div>
            </div>

            <div className="flex items-center justify-end gap-3 pt-3 border-t border-rail">
              <button
                onClick={() => setActiveActionModal(null)}
                disabled={isPending}
                className="px-4 py-2 rounded-lg bg-gray-800 text-gray-300 hover:text-white text-xs"
              >
                Cancel
              </button>
              <button
                onClick={submitAction}
                disabled={isPending}
                className="px-4 py-2 rounded-lg bg-purple-600 hover:bg-purple-500 text-white text-xs font-bold transition-colors"
              >
                {isPending ? "Executing..." : "Confirm & Execute Action"}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
