import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// Shared shapes for the bug-report feature. Stable on purpose: every
/// workstream codes against this file, so change it only with the lead.

enum BugCategory { video, sound, sync, chat, camera, other }

/// `saved` is local-only (queued offline); the rest mirror bug_reports.status.
/// `wontfix` and `duplicate` are the two ways the team closes a report without
/// a fix; both always arrive with something the user can read (a reason, or the
/// original report).
enum BugStatus { saved, received, looking, fixed, wontfix, duplicate }

/// The report a duplicate follows: its code, a neutral title and where it
/// stands. Never the other reporter's note or details.
class OriginalRef {
  const OriginalRef({required this.code, required this.title, required this.status});

  final String code;
  final String title;
  final BugStatus status;
}

/// What a tap collects. [screenshotPng] is taken first, before any sheet opens;
/// the rest fills in via [FeedbackService.gather].
class BugCapture {
  const BugCapture({
    this.screenshotPng,
    required this.screenRoute,
    this.summary = const {},
    this.logsText = '',
    this.context = const {},
    this.sentryEventId,
    this.fileName,
    this.includeFileName = false,
  });

  final Uint8List? screenshotPng;
  final String screenRoute;

  /// Ordered label -> value lines shown in "See exactly what we send".
  final Map<String, String> summary;

  /// Attached as logs.txt.
  final String logsText;

  /// Stored in bug_reports.context (jsonb, 16 KB cap).
  final Map<String, Object?> context;
  final String? sentryEventId;

  /// The playing video's redacted base name (never a path or URL). It is
  /// gathered but **never sent unless [includeFileName] is true**, which the
  /// sheet's "Include the video's file name" switch sets and which is off by
  /// default.
  final String? fileName;
  final bool includeFileName;

  /// The name only when the user opted in, else null.
  String? get fileNameToSend => includeFileName ? fileName : null;

  BugCapture copyWith({
    Uint8List? screenshotPng,
    bool clearScreenshot = false,
    String? screenRoute,
    Map<String, String>? summary,
    String? logsText,
    Map<String, Object?>? context,
    String? sentryEventId,
    String? fileName,
    bool clearFileName = false,
    bool? includeFileName,
  }) => BugCapture(
    screenshotPng: clearScreenshot ? null : (screenshotPng ?? this.screenshotPng),
    screenRoute: screenRoute ?? this.screenRoute,
    summary: summary ?? this.summary,
    logsText: logsText ?? this.logsText,
    context: context ?? this.context,
    sentryEventId: sentryEventId ?? this.sentryEventId,
    fileName: clearFileName ? null : (fileName ?? this.fileName),
    includeFileName: includeFileName ?? this.includeFileName,
  );
}

class BugReportRow {
  const BugReportRow({
    required this.code,
    required this.category,
    required this.title,
    required this.status,
    this.fixedIn,
    required this.createdAt,
    this.reason,
    this.duplicateOf,
    this.sameCount = 0,
    this.notifyWhenFixed = false,
    this.closedAt,
  });

  /// e.g. BUG-7K2M.
  final String code;
  final BugCategory category;
  final String title;
  final BugStatus status;

  /// The FIRST app version that contains the fix, shown as "Fixed from X.Y.Z
  /// onward" and compared "installed >= this", never for equality: a store may
  /// reject X.Y.Z and a later build ships instead.
  final String? fixedIn;
  final DateTime createdAt;

  /// Why the team closed it (`wontfix`), written by a person and shown as is.
  final String? reason;

  /// Set when [status] is `duplicate`.
  final OriginalRef? duplicateOf;

  /// How many other reports follow the same original (the server's count, which
  /// is the same for the original and each follower). 0 when it is alone.
  final int sameCount;
  final bool notifyWhenFixed;
  final DateTime? closedAt;
}

sealed class SubmitResult {
  const SubmitResult();
}

class Sent extends SubmitResult {
  const Sent(this.code);
  final String code;
}

class Queued extends SubmitResult {
  const Queued(this.localId);
  final String localId;
}

class RateLimited extends SubmitResult {
  const RateLimited(this.retryIn);
  final Duration retryIn;
}

abstract class FeedbackService {
  /// Screenshot first, before any sheet opens. Must return fast (< 300 ms).
  Future<BugCapture> captureScreen(BuildContext ctx);

  /// Slower data (sync, media, av, device, breadcrumbs). Returns [c] enriched.
  Future<BugCapture> gather(BugCapture c);

  Future<SubmitResult> submit(
    BugCapture c, {
    required BugCategory? category,
    String? note,
    required bool includeScreenshot,
  });

  /// Your reports. Emits on open and on app resume.
  Stream<List<BugReportRow>> watchMine();

  /// Retry saved reports (on reconnect and at launch).
  Future<void> flushQueue();

  /// "Tell me when it's fixed". [ref] is the code a [Sent] carried, or the
  /// local id a [Queued] carried; a queued report keeps the choice on the
  /// device and sends it with the report.
  Future<void> setNotifyWhenFixed(String ref, bool on);

  /// "Add more details" after sending. Same [ref] rules as above.
  Future<void> appendNote(String ref, String text);
}
