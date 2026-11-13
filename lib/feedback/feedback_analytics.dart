import '../analytics.dart';

/// The only place the bug-report product events are sent from. Pure delegation
/// to [Analytics.track] with fixed literals so `test/analytics_catalog_test.dart`
/// can see them, and so no caller can attach free text.
///
/// Call these only where a human caused the event (a tap), never for an
/// impression. See the Analytics section of `docs/agent/ui-and-av.md`.
abstract final class FeedbackAnalytics {
  /// [source]: `button`, `shortcut`, `menu` (macOS Help menu), `shake`, `more`, `profile`, `nudge`, `review`,
  /// `reports` (the closed-report page's "Still happening?").
  static void opened(String source) =>
      Analytics.instance.track('bug_report_opened', {'source': source});

  /// [category] is a `BugCategory.name` or `none`.
  static void sent({required String category, required bool screenshot, required bool queued}) =>
      Analytics.instance.track('bug_report_sent', {
        'category': category,
        'screenshot': screenshot,
        'queued': queued,
      });

  static void introDismissed() => Analytics.instance.track('bug_intro_dismissed');

  /// [reason]: `stall`, `reconnect`, `upload`, `error` or `crash`.
  static void nudgeTapped(String reason) =>
      Analytics.instance.track('bug_nudge_tapped', {'reason': reason});

  /// [choice]: `great` or `not_quite`.
  static void reviewAnswered(String choice) =>
      Analytics.instance.track('review_prompt_answered', {'choice': choice});
}
