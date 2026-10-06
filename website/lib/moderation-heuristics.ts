/**
 * Zero-Key Offline Heuristic Moderation Scanner
 *
 * Runs locally without any external AI API keys or network requests.
 * Evaluates reported media titles, stream URLs, room metadata, and user strike
 * history to generate an instant risk score and recommended action.
 */

export interface HeuristicEvaluation {
  riskScore: number; // 0 to 100
  riskLevel: "low" | "medium" | "high" | "critical";
  isLikelyPiracy: boolean;
  detectedPatterns: string[];
  suggestedAction: "dismiss" | "warn_user" | "ban_room" | "ban_room_and_warn_user" | "ban_room_and_ban_user";
  reasoning: string;
}

const PIRACY_SCENE_TAGS = [
  /\b(1080p|720p|2160p|4k|uhd)\b/i,
  /\b(webrip|web-dl|bluray|bdrip|dvdrip|hdrip|camrip|telesync|hdcam)\b/i,
  /\b(x264|x265|hevc|h264|h265|avc|remux)\b/i,
  /\b(yify|yts|eztv|rarbg|psa|galaxyrg|tgx)\b/i,
  /\.(torrent|mkv|avi|iso)$/i,
  /\b(magnet:|\.torrent)\b/i,
  /\b[A-Za-z0-9._]+(19\d\d|20[0-3]\d)[._](1080p|720p|2160p|webrip|web-dl|bluray)/i,
];

const PIRACY_KEYWORDS = [
  /\b(pirat|torrent|camrip|leaked|crack|warez|illegal stream)\b/i,
  /\b(full movie|free movie|cinema rip|bootleg)\b/i,
];

export function evaluateReportHeuristics(input: {
  reason: string;
  mediaTitle?: string | null;
  mediaSourceUrl?: string | null;
  mediaKind?: string | null;
  messageExcerpt?: string | null;
  details?: string | null;
  userStrikes?: number;
  userModerationStatus?: string;
}): HeuristicEvaluation {
  const detectedPatterns: string[] = [];
  let score = 0;

  const title = (input.mediaTitle || "").trim();
  const url = (input.mediaSourceUrl || "").trim();
  const details = (input.details || "").trim();
  const excerpt = (input.messageExcerpt || "").trim();
  const combinedText = `${title} ${url} ${details} ${excerpt}`;

  // 1. Copyright category baseline
  if (input.reason === "copyright") {
    score += 35;
    detectedPatterns.push("Reported specifically for copyright infringement");
  } else if (["sexual_content", "hate_speech", "violence"].includes(input.reason)) {
    score += 40;
    detectedPatterns.push(`High severity report category: ${input.reason}`);
  }

  // 2. Check scene release patterns in media title
  for (const regex of PIRACY_SCENE_TAGS) {
    const match = title.match(regex) || url.match(regex);
    if (match) {
      score += 25;
      detectedPatterns.push(`Scene piracy tag match: "${match[0]}"`);
    }
  }

  // 3. Check piracy keywords in complaint details or title
  for (const regex of PIRACY_KEYWORDS) {
    const match = combinedText.match(regex);
    if (match) {
      score += 20;
      detectedPatterns.push(`Piracy/infringement keyword: "${match[0]}"`);
    }
  }

  // 4. Cloud R2 media upload with media kind 'r2' sharing
  if (input.mediaKind === "r2" && title.length > 0) {
    score += 15;
    detectedPatterns.push("Cloud media file redistributed via R2 storage");
  }

  // Cap score between 0 and 100
  score = Math.min(Math.max(score, 0), 100);

  const strikes = input.userStrikes || 0;
  const isLikelyPiracy = score >= 50;

  let riskLevel: HeuristicEvaluation["riskLevel"] = "low";
  if (score >= 80) riskLevel = "critical";
  else if (score >= 60) riskLevel = "high";
  else if (score >= 35) riskLevel = "medium";

  // Determine suggested action based on strikes and risk
  let suggestedAction: HeuristicEvaluation["suggestedAction"] = "dismiss";
  let reasoning = "";

  if (score >= 60) {
    if (strikes >= 1) {
      suggestedAction = "ban_room_and_ban_user";
      reasoning = `High piracy/violation risk (${score}%). Target user already has ${strikes} strike(s). Recommend terminating room and issuing Strike 2 (Indefinite Ban).`;
    } else {
      suggestedAction = "ban_room_and_warn_user";
      reasoning = `Strong indicators of unauthorized copyrighted content (${score}%). Recommend terminating room and issuing Strike 1 Warning.`;
    }
  } else if (score >= 35) {
    if (strikes >= 1) {
      suggestedAction = "warn_user";
      reasoning = `Moderate concern detected (${score}%). Recommend review and issuing warning if violation is verified.`;
    } else {
      suggestedAction = "warn_user";
      reasoning = `Potential policy violation (${score}%). Requires reviewer verification.`;
    }
  } else {
    suggestedAction = "dismiss";
    reasoning = `Low violation probability (${score}%). No prominent scene piracy or abuse signatures found.`;
  }

  return {
    riskScore: score,
    riskLevel,
    isLikelyPiracy,
    detectedPatterns,
    suggestedAction,
    reasoning,
  };
}

export function formatPromptForAgent(report: {
  id: string;
  reason: string;
  createdAt: string;
  reporter?: { displayName?: string; email?: string } | null;
  reported?: { id?: string; displayName?: string; email?: string; strikesCount?: number; status?: string } | null;
  room?: { code?: string; isBanned?: boolean } | null;
  media?: { kind?: string | null; title?: string | null; url?: string | null } | null;
  messageExcerpt?: string | null;
  details?: string | null;
  heuristics?: HeuristicEvaluation;
}): string {
  return `### Moderation Complaint Review Request
**Report ID**: \`${report.id}\`
**Category**: ${report.reason}
**Reported At**: ${report.createdAt}

#### Reported User
- **Name**: ${report.reported?.displayName || "Unknown"}
- **User ID**: \`${report.reported?.id || "N/A"}\`
- **Prior Strikes**: ${report.reported?.strikesCount ?? 0} / 2 (Status: ${report.reported?.status || "clean"})

#### Media & Room Context
- **Room Code**: ${report.room?.code || "N/A"}
- **Media Kind**: ${report.media?.kind || "N/A"}
- **Media Title**: \`${report.media?.title || "N/A"}\`
- **Stream/Source URL**: ${report.media?.url || "N/A"}

#### Complaint Evidence
- **Chat Excerpt**: ${report.messageExcerpt ? `"${report.messageExcerpt}"` : "_None_"}
- **Reporter Details**: ${report.details ? `"${report.details}"` : "_None_"}

#### Heuristic Scan
- **Risk Score**: ${report.heuristics?.riskScore ?? 0}% (${report.heuristics?.riskLevel || "low"})
- **Detected Flags**: ${report.heuristics?.detectedPatterns.join(", ") || "None"}
- **Initial Suggestion**: \`${report.heuristics?.suggestedAction || "dismiss"}\`

**Agent Instructions**:
Please review this evidence. If this constitutes copyright infringement or a community violation, recommend or apply the appropriate action (warn user, ban room, or ban user).`;
}
