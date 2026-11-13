import 'package:flutter/widgets.dart';

import '../diagnostics.dart';
import '../ui/glass.dart';
import 'contract.dart';
import 'feedback_analytics.dart';
import 'feedback_services.dart';
import 'ui/bug_report_form.dart';

/// Entry point for "Report a bug". Every bug button, shortcut and nudge calls
/// [open]; the screenshot is taken here, before the sheet exists, so the
/// picture shows the problem and not the dialog on top of it.
class BugReport {
  BugReport._();

  static bool _opening = false;

  /// Whether a report is being captured or is on screen. Shake checks it so a
  /// second shake while typing does not reset or re-capture the sheet.
  static bool get isOpen => _opening;

  /// Tests tear the whole tree down without popping the dialog, which would
  /// leave the re-entrancy guard stuck.
  @visibleForTesting
  static void debugReset() => _opening = false;

  /// Captures the screen, then shows the report sheet (phone) or dialog
  /// (wider windows). Playback keeps running behind it. A second call while one
  /// is already open does nothing. [source] names what the user tapped, for the
  /// one `bug_report_opened` event (see [FeedbackAnalytics.opened]).
  ///
  /// [followUpOf] is the code of an earlier report this one answers ("Still
  /// happening? Tell us"): the note starts by naming it and the context carries
  /// `follow_up_of`, so the team sees the thread.
  static Future<void> open(
    BuildContext context, {
    String source = 'button',
    String? followUpOf,
  }) async {
    if (_opening) return;
    _opening = true;
    FeedbackAnalytics.opened(source);
    try {
      final service = FeedbackServices.instance;
      BugCapture capture;
      try {
        capture = await service.captureScreen(context);
      } catch (e, s) {
        // No screenshot is still a report worth sending.
        reportNonFatal(e, s, during: 'bug report screenshot');
        capture = const BugCapture(screenRoute: '');
      }
      if (!context.mounted) return;
      if (followUpOf != null) {
        capture = capture.copyWith(context: {...capture.context, 'follow_up_of': followUpOf});
      }
      trace(
        'bug report opened',
        category: 'feedback',
        data: {
          'route': capture.screenRoute,
          'screenshot': capture.screenshotPng != null,
          'follow_up': followUpOf != null,
        },
      );
      await showGlassDialog<void>(
        context: context,
        width: 520,
        sheetOnCompact: true,
        builder: (_) => BugReportForm(
          service: service,
          capture: capture,
          initialNote: followUpOf == null ? null : 'Following up on $followUpOf: ',
        ),
      );
    } finally {
      _opening = false;
    }
  }
}
