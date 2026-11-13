import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:synctogether/diagnostics.dart';

import 'bug_reports_api.dart';
import 'capture/collector.dart';
import 'capture/probes.dart';
import 'capture/screenshot.dart';
import 'contract.dart';
import 'queue.dart';

const kReportContextMaxBytes = 16000;
const kReportCooldown = Duration(seconds: 30);
const kQueueMaxAttempts = 8;
const kNoteMaxChars = 2000;

String? _clip(String? s) =>
    s == null || s.length <= kNoteMaxChars ? s : s.substring(0, kNoteMaxChars);

/// Keeps [context] under the server's 16 KB cap by dropping the largest
/// top-level entries first (never `route`/`app`, which the team needs most).
Map<String, Object?> capContext(
  Map<String, Object?> context, {
  int maxBytes = kReportContextMaxBytes,
}) {
  final out = {...context};
  int size() => utf8.encode(jsonEncode(out)).length;
  const keep = {'route', 'app', 'user_id', 'follow_up_of'};
  while (size() > maxBytes) {
    final drop = out.entries.where((e) => !keep.contains(e.key)).toList()
      ..sort((a, b) => jsonEncode(b.value).length.compareTo(jsonEncode(a.value).length));
    if (drop.isEmpty) return {'route': out['route'], 'truncated': true};
    out.remove(drop.first.key);
    out['truncated'] = true;
  }
  return out;
}

/// The real [FeedbackService]: screenshot + context -> Sentry feedback and the
/// `bug_reports` row, with a durable queue when the network (or a session) is
/// missing. Every step degrades alone: Sentry off or failing never blocks the
/// row, and a failing row still leaves the Sentry copy.
class RealFeedbackService with WidgetsBindingObserver implements FeedbackService {
  RealFeedbackService({
    required this.api,
    BugReportQueue? queue,
    DateTime Function()? now,
    this.sentryTimeout = const Duration(seconds: 4),
    Future<Uint8List?> Function()? screenshot,
    List<Duration>? retryBackoff,
  }) : queue = queue ?? BugReportQueue(),
       _now = now ?? DateTime.now,

       _screenshot = screenshot ?? captureAppScreenshot,
       _backoff =
           retryBackoff ??
           const [
             Duration(minutes: 1),
             Duration(minutes: 2),
             Duration(minutes: 5),
             Duration(minutes: 15),
           ];

  final BugReportsApi api;
  final BugReportQueue queue;
  final DateTime Function() _now;
  final Duration sentryTimeout;
  final Future<Uint8List?> Function() _screenshot;
  final List<Duration> _backoff;

  DateTime? _lastSubmit;
  final _listeners = <void Function()>[];
  Timer? _retry;
  int _retryStep = 0;
  bool _flushing = false;
  bool _started = false;

  /// Hooks resume and launch retries. Call once after Supabase is up.
  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    unawaited(flushQueue());
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _retry?.cancel();
    _started = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(flushQueue());
    _notify();
  }

  void _notify() {
    for (final f in List.of(_listeners)) {
      f();
    }
  }

  @override
  Future<BugCapture> captureScreen(BuildContext ctx) async {
    final route = currentRoute(ctx);
    Uint8List? png;
    try {
      png = await _screenshot();
    } catch (e, s) {
      reportNonFatal(e, s, during: 'capturing a bug report screenshot');
    }
    trace(
      'bug report opened',
      category: 'feedback',
      data: {'screenshot': png != null, 'route': route},
    );
    return BugCapture(screenshotPng: png, screenRoute: route);
  }

  @override
  Future<BugCapture> gather(BugCapture c) async {
    final g = await gatherCapture(c);
    // Offered to the sheet's opt-in switch; never part of the default report.
    return g.copyWith(fileName: FeedbackProbes.optional('media.file_name'));
  }

  @override
  Future<SubmitResult> submit(
    BugCapture c, {
    required BugCategory? category,
    String? note,
    required bool includeScreenshot,
  }) async {
    final last = _lastSubmit;
    if (last != null && _now().difference(last) < kReportCooldown) {
      return RateLimited(kReportCooldown - _now().difference(last));
    }
    final cleanNote = note?.trim();
    final fileName = c.fileNameToSend;
    final summary = {...c.summary, if (fileName != null) 'file': fileName};
    final report = QueuedReport(
      id: const Uuid().v4(),
      category: category?.name,
      note: (cleanNote == null || cleanNote.isEmpty) ? null : _clip(cleanNote),
      context: capContext({
        ...c.context,
        'summary': summary,
        if (fileName != null) 'media_file_name': fileName,
      }),
      createdAt: _now(),
    );
    final png = includeScreenshot ? c.screenshotPng : null;
    _lastSubmit = _now();
    final result = await _deliver(
      report,
      screenshot: png,
      logs: c.logsText,
      sentryEventId: c.sentryEventId,
    );
    if (result is Queued) {
      await queue.add(report, screenshot: png, logs: c.logsText);
      _armRetry();
    }
    if (result is Sent) await _applyChoices(result.code, report);
    if (result is RateLimited) _lastSubmit = _now();
    trace(
      'bug report ${result.runtimeType}',
      category: 'feedback',
      data: {'category': category?.name, 'screenshot': png != null, 'note': report.note != null},
    );
    _notify();
    return result;
  }

  /// One delivery attempt: Sentry (best effort, bounded), then the row.
  Future<SubmitResult> _deliver(
    QueuedReport r, {
    Uint8List? screenshot,
    String? logs,
    String? sentryEventId,
  }) async {
    final eventId = sentryEventId ?? await _sendToSentry(r, screenshot, logs);
    try {
      final code = await api.submit(
        category: r.category,
        note: r.note,
        context: r.context,
        sentryEventId: eventId,
      );
      return Sent(code);
    } on BugReportRateLimited catch (e) {
      return RateLimited(e.retryIn);
    } on BugReportRejected catch (e, s) {
      // Never retry the same bytes: say so, then land a minimal report so the
      // user's tap still reaches the team.
      reportNonFatal(e, s, during: 'sending a bug report (rejected)');
      try {
        final code = await api.submit(
          category: r.category,
          note: _clip(r.note),
          context: {'route': r.context['route'], 'rejected': true},
          sentryEventId: eventId,
        );
        return Sent(code);
      } catch (e2, s2) {
        reportNonFatal(e2, s2, during: 'sending a minimal bug report');
        return Queued(r.id);
      }
    } catch (e, s) {
      // Offline, no session yet (login screen) or a server hiccup: keep it.
      reportNonFatal(e, s, during: 'sending a bug report');
      return Queued(r.id);
    }
  }

  /// What the user chose on the success screen before the report had a code:
  /// the "tell me when it's fixed" switch (on unless they turned it off) and any
  /// extra details. Best effort and never re-queues the report, which has
  /// already landed: a failure here is reported and the user can set it again
  /// from the screen.
  Future<void> _applyChoices(String code, QueuedReport r) async {
    try {
      if (r.notifyWhenFixed) await api.setNotifyWhenFixed(code, true);
      final more = r.appendix;
      if (more != null && more.isNotEmpty) await api.appendNote(code, more);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'applying the choices on a sent bug report');
    }
  }

  @override
  Future<void> setNotifyWhenFixed(String ref, bool on) async {
    final queued = await queue.setNotify(ref, on);
    trace('bug report notify choice', category: 'feedback', data: {'on': on, 'queued': queued});
    if (!queued) await api.setNotifyWhenFixed(ref, on);
    _notify();
  }

  @override
  Future<void> appendNote(String ref, String text) async {
    final clean = _clip(text.trim());
    if (clean == null || clean.isEmpty) return;
    final queued = await queue.appendNote(ref, clean);
    trace('bug report details added', category: 'feedback', data: {'queued': queued});
    if (!queued) await api.appendNote(ref, clean);
    _notify();
  }

  Future<String?> _sendToSentry(QueuedReport r, Uint8List? screenshot, String? logs) async {
    if (!Sentry.isEnabled) return null;
    try {
      return await Future(() async {
        final label = r.category ?? 'uncategorised';
        final id = await Sentry.captureMessage(
          'Bug report: $label',
          level: SentryLevel.info,
          withScope: (scope) {
            scope.setTag('kind', 'bug_report');
            scope.setTag('category', label);
          },
        );
        if (id == SentryId.empty()) return null;
        await Sentry.captureFeedback(
          SentryFeedback(message: r.note ?? 'Bug report ($label)', associatedEventId: id),
          hint: Hint.withAttachments([
            if (screenshot != null)
              SentryAttachment.fromUint8List(
                screenshot,
                'screenshot.png',
                contentType: 'image/png',
              ),
            if (logs != null && logs.isNotEmpty)
              SentryAttachment.fromUint8List(
                Uint8List.fromList(utf8.encode(logs)),
                'logs.txt',
                contentType: 'text/plain',
              ),
          ]),
        );
        return id.toString();
      }).timeout(sentryTimeout);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'sending bug report to Sentry');
      return null;
    }
  }

  @override
  Future<void> flushQueue() async {
    if (_flushing) return;
    if (!api.signedIn) {
      // Login screen or a lapsed session: keep checking while reports wait.
      if ((await queue.load()).isNotEmpty) _armRetry();
      return;
    }
    _flushing = true;
    try {
      final pending = await queue.load();
      var failed = false;
      for (final r in pending) {
        final png = await queue.screenshotOf(r);
        final logs = await queue.logsOf(r);
        final res = await _deliver(r, screenshot: png, logs: logs);
        if (res is Sent) {
          await queue.remove(r.id);
          await _applyChoices(res.code, r);
          trace('queued bug report sent', category: 'feedback', data: {'attempts': r.attempts});
        } else {
          failed = true;
          if (r.attempts + 1 >= kQueueMaxAttempts) {
            await queue.remove(r.id);
            reportNonFatal(
              StateError('bug report dropped after $kQueueMaxAttempts attempts'),
              null,
              during: 'flushing the bug report queue',
            );
          } else {
            await queue.setAttempts(r.id, r.attempts + 1);
          }
        }
      }
      if (failed) {
        _armRetry();
      } else {
        _retryStep = 0;
      }
      _notify();
    } catch (e, s) {
      reportNonFatal(e, s, during: 'flushing the bug report queue');
    } finally {
      _flushing = false;
    }
  }

  void _armRetry() {
    _retry?.cancel();
    final delay = _backoff[_retryStep.clamp(0, _backoff.length - 1)];
    _retryStep++;
    _retry = Timer(delay, () => unawaited(flushQueue()));
  }

  @override
  Stream<List<BugReportRow>> watchMine() {
    late StreamController<List<BugReportRow>> ctrl;
    void push() async {
      final rows = await _rows();
      if (!ctrl.isClosed) ctrl.add(rows);
    }

    ctrl = StreamController<List<BugReportRow>>(
      onListen: () {
        _listeners.add(push);
        push();
      },
      onCancel: () => _listeners.remove(push),
    );
    return ctrl.stream;
  }

  List<BugReportRow> _lastServerRows = const [];

  Future<List<BugReportRow>> _rows() async {
    if (api.signedIn) {
      try {
        _lastServerRows = await api.mine();
      } catch (e, s) {
        reportNonFatal(e, s, during: 'loading your bug reports');
      }
    }
    final saved = [
      for (final r in await queue.load())
        BugReportRow(
          code: 'BUG-····',
          category: categoryFromName(r.category),
          title: (r.note ?? categoryTitle(categoryFromName(r.category))).split('\n').first,
          status: .saved,
          createdAt: r.createdAt,
          notifyWhenFixed: r.notifyWhenFixed,
        ),
    ];
    return [...saved, ..._lastServerRows];
  }
}
