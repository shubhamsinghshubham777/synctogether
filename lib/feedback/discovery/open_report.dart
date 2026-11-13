import 'package:flutter/widgets.dart';

import '../bug_report.dart';

/// Where discovery opens the report sheet from, with the [source] the opening
/// event is attributed to: `profile`, `nudge` or `review`.
///
/// One seam on purpose: `BugReport.open` fires the `bug_report_opened` event
/// itself from the [source] passed here.
Future<void> openReportFrom(BuildContext context, String source) =>
    BugReport.open(context, source: source);
