import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/app_version.dart';
import 'package:synctogether/feedback/contract.dart';
import 'package:synctogether/feedback/fake_feedback_service.dart';
import 'package:synctogether/feedback/feedback_services.dart';
import 'package:synctogether/feedback/report_detail_screen.dart';
import 'package:synctogether/feedback/reports_screen.dart';

import '../support/screen_matrix.dart';
import 'layout_support.dart';

const _reason =
    'This is how the fold works on purpose: the seek bar steps aside so it never sits on the '
    'hinge, which can look like a jump. We have added a line about it to the FAQ so the next '
    'person knows.';

BugReportRow _row(
  String code,
  BugStatus s,
  String title, {
  String? fixedIn,
  String? reason,
  OriginalRef? original,
  int same = 0,
}) => BugReportRow(
  code: code,
  category: BugCategory.video,
  title: title,
  status: s,
  fixedIn: fixedIn,
  createdAt: DateTime.now().subtract(const Duration(days: 1)),
  closedAt: reason == null ? null : DateTime.now().subtract(const Duration(hours: 3)),
  reason: reason,
  duplicateOf: original,
  sameCount: same,
);

final _rows = [
  _row('BUG-7K2M', BugStatus.fixed, 'Video went black', fixedIn: '1.4.2'),
  _row(
    'BUG-9D4X',
    BugStatus.duplicate,
    'Messages stuck sending',
    same: 11,
    original: const OriginalRef(
      code: 'BUG-3F9A',
      title: "Chat won't send on cellular",
      status: BugStatus.looking,
    ),
  ),
  _row('BUG-1C0D', BugStatus.wontfix, 'Seek bar jumps on fold', reason: _reason),
  _row('BUG-3F9A', BugStatus.looking, "Chat won't send on cellular", same: 11),
];

void main() {
  late FeedbackService saved;
  late String? savedVersion;
  setUp(() {
    saved = FeedbackServices.instance;
    savedVersion = AppVersion.current;
    AppVersion.current = '1.4.1';
    FeedbackServices.instance = FakeFeedbackService()..debugSetRows(_rows);
  });
  tearDown(() {
    FeedbackServices.instance = saved;
    AppVersion.current = savedVersion;
  });

  screenMatrix('feedback/reports-closed-states', (tester, c, s) async {
    await pumpAtSize(tester, const ReportsScreen(), c, textScale: s, singlePane: true);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('CLOSED'), findsOneWidget);
    await finishCase(tester);
  });

  screenMatrix('feedback/report-closed-detail', (tester, c, s) async {
    await pumpAtSize(
      tester,
      const ReportDetailScreen(code: 'BUG-1C0D'),
      c,
      textScale: s,
      singlePane: true,
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('WHY WE CLOSED THIS'), findsOneWidget);
    await finishCase(tester);
  });

  screenMatrix('feedback/report-duplicate-detail', (tester, c, s) async {
    await pumpAtSize(
      tester,
      const ReportDetailScreen(code: 'BUG-9D4X'),
      c,
      textScale: s,
      singlePane: true,
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('TRACKING'), findsOneWidget);
    await finishCase(tester);
  });
}
