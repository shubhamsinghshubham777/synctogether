import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// Shared shapes for the bug-report feature. Stable on purpose: every
/// workstream codes against this file, so change it only with the lead.

enum BugCategory { video, sound, sync, chat, camera, other }

/// `saved` is local-only (queued offline); the rest mirror bug_reports.status.
enum BugStatus { saved, received, looking, fixed }

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

  BugCapture copyWith({
    Uint8List? screenshotPng,
    bool clearScreenshot = false,
    String? screenRoute,
    Map<String, String>? summary,
    String? logsText,
    Map<String, Object?>? context,
    String? sentryEventId,
  }) => BugCapture(
    screenshotPng: clearScreenshot ? null : (screenshotPng ?? this.screenshotPng),
    screenRoute: screenRoute ?? this.screenRoute,
    summary: summary ?? this.summary,
    logsText: logsText ?? this.logsText,
    context: context ?? this.context,
    sentryEventId: sentryEventId ?? this.sentryEventId,
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
  });

  /// e.g. BUG-7K2M.
  final String code;
  final BugCategory category;
  final String title;
  final BugStatus status;
  final String? fixedIn;
  final DateTime createdAt;
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
}
