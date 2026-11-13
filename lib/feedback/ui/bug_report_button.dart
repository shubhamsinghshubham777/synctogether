import 'package:flutter/material.dart';

import '../../ui/buttons.dart';
import '../bug_report.dart';

/// The bug button that sits in every header. W4 owns placement and swaps the
/// glyph for `BoothIcons.bug`; [compact] is the 36 px desktop-bar size.
class BugReportButton extends StatelessWidget {
  const BugReportButton({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) => PTIconButton(
    icon: Icons.bug_report_outlined,
    size: compact ? 36 : 44,
    iconSize: compact ? 18 : 21,
    tooltip: 'Report a bug',
    onPressed: () => BugReport.open(context),
  );
}
