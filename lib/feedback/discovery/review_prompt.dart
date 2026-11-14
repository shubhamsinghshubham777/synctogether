import 'package:material_ui/material_ui.dart';

import '../../ui/buttons.dart';
import '../../ui/glass.dart';
import '../../ui/pt_theme.dart';
import '../feedback_analytics.dart';
import 'open_report.dart';
import 'discovery_triggers.dart';

/// "How's the show going?" after a finished film. "Not quite" is an extra door
/// to the bug sheet, never a gate: the rating link stays in Profile for
/// everyone, because the stores forbid hiding it from anyone.
///
/// Asks at most twice a year and only when the platform rating sheet is wired
/// ([DiscoveryTriggers.onRate]); otherwise it quietly does nothing.
Future<void> maybeAskForReview(BuildContext context) async {
  final t = DiscoveryTriggers.instance;
  if (!await t.shouldAskReview() || !context.mounted) return;
  await t.recordReviewAsked();
  if (!context.mounted) return;
  final choice = await showGlassDialog<bool>(
    context: context,
    width: 380,
    sheetOnCompact: true,
    builder: (context) => const _ReviewPrompt(),
  );
  if (!context.mounted) return;
  if (choice == true) {
    FeedbackAnalytics.reviewAnswered('great');
    DiscoveryTriggers.onRate?.call();
  } else if (choice == false) {
    FeedbackAnalytics.reviewAnswered('not_quite');
    await openReportFrom(context, 'review');
  }
}

class _ReviewPrompt extends StatelessWidget {
  const _ReviewPrompt();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      spacing: 14,
      children: [
        Text("How's the show going?", style: PTText.cardHeading.copyWith(fontSize: 20)),
        Row(
          spacing: 10,
          children: [
            Expanded(
              child: PTButton(
                label: 'Great, rate it',
                height: 44,
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ),
            Expanded(
              child: PTButton(
                label: 'Not quite',
                variant: .secondary,
                height: 44,
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
