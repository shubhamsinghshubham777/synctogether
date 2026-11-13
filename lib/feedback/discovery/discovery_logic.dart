import '../contract.dart';

/// Pure decisions behind the discovery layers, over plain values, so they are
/// testable without a clock, prefs or widgets (same seam as `sync_logic.dart`).

/// What made the app offer a report. Only things the app itself noticed.
enum NudgeReason { streamStall, persistentReconnect, uploadFailed, recoveredError, previousCrash }

const kNudgeCooldown = Duration(days: 14);
const kReviewCooldown = Duration(days: 365);
const kReviewMaxPerYear = 2;

/// One nudge per session, and 14 days of quiet after the last one was answered
/// (dismissed or accepted).
bool nudgeAllowed({
  required DateTime now,
  required bool shownThisSession,
  DateTime? lastAnsweredAt,
}) {
  if (shownThisSession) return false;
  if (lastAnsweredAt == null) return true;
  return now.difference(lastAnsweredAt) >= kNudgeCooldown;
}

/// The coach mark: once ever, from the second launch or after the first room,
/// never on the very first launch.
bool coachDue({required bool alreadyShown, required int launches, required int roomsVisited}) =>
    !alreadyShown && (launches >= 2 || roomsVisited >= 1);

/// The store-review ask: at most [kReviewMaxPerYear] times in a rolling year.
bool reviewAllowed({required DateTime now, required List<DateTime> asked}) =>
    asked.where((t) => now.difference(t) < kReviewCooldown).length < kReviewMaxPerYear;

/// The newest fixed report the user has not been told about yet.
BugReportRow? newlyFixed(List<BugReportRow> rows, Set<String> told) {
  BugReportRow? best;
  for (final r in rows) {
    if (r.status != BugStatus.fixed || told.contains(r.code)) continue;
    if (best == null || r.createdAt.isAfter(best.createdAt)) best = r;
  }
  return best;
}

/// "3 sent · 1 fixed" for the Profile row. Queued-offline rows are not sent yet.
String reportsSummary(List<BugReportRow> rows) {
  final sent = rows.where((r) => r.status != BugStatus.saved).length;
  final fixed = rows.where((r) => r.status == BugStatus.fixed).length;
  if (rows.isEmpty) return 'Nothing sent yet';
  if (sent == 0) return '${rows.length} saved on this device';
  return fixed == 0 ? '$sent sent' : '$sent sent · $fixed fixed';
}

/// The `reason` value of the nudge-tapped analytics event.
String nudgeAnalyticsReason(NudgeReason r) => switch (r) {
  NudgeReason.streamStall => 'stall',
  NudgeReason.persistentReconnect => 'reconnect',
  NudgeReason.uploadFailed => 'upload',
  NudgeReason.recoveredError => 'error',
  NudgeReason.previousCrash => 'crash',
};

String nudgeCopyTitle(NudgeReason r) => switch (r) {
  NudgeReason.previousCrash => 'The app closed unexpectedly last time.',
  _ => "That didn't go smoothly.",
};

String nudgeCopyBody(NudgeReason r) => switch (r) {
  NudgeReason.previousCrash => 'Send us the details so we can fix it?',
  _ => 'Want to tell us what happened?',
};
