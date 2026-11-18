import 'package:material_ui/material_ui.dart';

import '../feedback/ui/bug_report_button.dart';
import '../nav.dart';
import 'booth_icons.g.dart';
import 'buttons.dart';
import 'pt_theme.dart';

/// The touch header every pushed page shares (Profile is the reference): a back
/// square, the page title in card-heading type, optional [trailing] actions and
/// the bug button. One gutter, one vertical rhythm and one type style, so
/// moving between Profile, Patron seats, Leaderboard and the pair pages never
/// shifts the title or the buttons.
class PTScreenTitleBar extends StatelessWidget {
  const PTScreenTitleBar({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  /// The page gutter on touch layouts; content below the bar uses the same one.
  static double gutterFor(double width) => width >= 720 ? 48.0 : 22.0;

  @override
  Widget build(BuildContext context) {
    final gutter = gutterFor(MediaQuery.sizeOf(context).width);
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 10, gutter, 12),
      child: Row(
        children: [
          PTIconButton(
            icon: BoothIcons.arrowBack,
            iconSize: 20,
            size: 44,
            tooltip: 'Back',
            onPressed: () => goBack(context),
          ),
          const SizedBox(width: 22),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: .ellipsis,
              style: PTText.cardHeading.copyWith(fontSize: 18),
            ),
          ),
          if (trailing != null) ...[trailing!, const SizedBox(width: 12)],
          const BugReportButton(),
        ],
      ),
    );
  }
}
