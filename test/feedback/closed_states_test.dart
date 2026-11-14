import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:synctogether/app_version.dart';
import 'package:synctogether/feedback/bug_reports_api.dart';
import 'package:synctogether/feedback/contract.dart';
import 'package:synctogether/feedback/discovery/discovery_triggers.dart';
import 'package:synctogether/feedback/fake_feedback_service.dart';
import 'package:synctogether/feedback/feedback_services.dart';
import 'package:synctogether/feedback/fixed_from.dart';
import 'package:synctogether/feedback/report_detail_screen.dart';
import 'package:synctogether/feedback/reports_screen.dart';

BugReportRow _row(
  String code,
  BugStatus s, {
  String title = 'Video went black',
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
  createdAt: DateTime(2026, 11, 13, 21, 52),
  closedAt: reason == null ? null : DateTime(2026, 11, 14, 10, 14),
  reason: reason,
  duplicateOf: original,
  sameCount: same,
);

const _reason =
    'This is how the fold works on purpose: the seek bar steps aside so it never sits on '
    'the hinge, which can look like a jump. We have added a line about it to the FAQ.';

void main() {
  group('fixed from', () {
    test('parses X.Y.Z and tolerates +build, -pre and a leading v', () {
      expect(parseVersion('1.4.2'), [1, 4, 2]);
      expect(parseVersion('1.4.2+88'), [1, 4, 2]);
      expect(parseVersion('v1.4.2-beta.1'), [1, 4, 2]);
      expect(parseVersion('1.4'), isNull);
      expect(parseVersion('next week'), isNull);
      expect(parseVersion(null), isNull);
    });

    test('at or above the fix, never an exact match', () {
      expect(versionReached('1.4.2', '1.4.2'), isTrue);
      // 1.4.2 was rejected and 1.4.3 shipped: still fixed.
      expect(versionReached('1.4.3', '1.4.2'), isTrue);
      expect(versionReached('1.5.0', '1.4.2'), isTrue);
      expect(versionReached('2.0.0', '1.9.9'), isTrue);
      expect(versionReached('1.4.10', '1.4.9'), isTrue);
      expect(versionReached('1.4.1', '1.4.2'), isFalse);
      expect(versionReached('1.4.9', '1.4.10'), isFalse);
      expect(versionReached('1.3.99', '1.4.0'), isFalse);
    });

    test('anything unreadable counts as not yet', () {
      expect(versionReached(null, '1.4.2'), isFalse);
      expect(versionReached('garbage', '1.4.2'), isFalse);
      expect(versionReached('1.4.2', 'garbage'), isFalse);
      expect(versionReached('1.4.2', null), isFalse);
    });

    test('copy says rolling out until the fix is installed', () {
      expect(fixedPill('1.4.2'), 'FIXED FROM 1.4.2');
      expect(fixedPill(null), 'FIXED');
      expect(
        fixedLine('1.4.2', installed: '1.4.1'),
        'Fixed from 1.4.2 onward. Rolling out to your store soon. Thank you for flagging it.',
      );
      expect(fixedLine('1.4.2', installed: '1.4.3'), contains("it's on this device"));
      expect(fixedBannerTail('1.4.2', installed: '1.4.1'), 'Rolling out to your store soon.');
      expect(fixedBannerTail('1.4.2', installed: '1.4.2'), "It's on this device now.");
    });

    test('Update now exists only while the fix is not here and an updater is set', () {
      expect(showUpdateFor('1.4.2', installed: '1.4.1', canUpdate: true), isTrue);
      expect(showUpdateFor('1.4.2', installed: '1.4.1', canUpdate: false), isFalse);
      expect(showUpdateFor('1.4.2', installed: '1.4.2', canUpdate: true), isFalse);
      expect(showUpdateFor('1.4.2', installed: '1.5.0', canUpdate: true), isFalse);
      expect(showUpdateFor(null, installed: '1.4.1', canUpdate: true), isFalse);
    });
  });

  group('server rows', () {
    final base = {'code': 'BUG-1', 'created_at': '2026-11-13T21:52:00Z', 'category': 'sync'};

    test('closed and duplicate rows keep their reason and their original', () {
      final closed = rowFromJson({
        ...base,
        'status': 'wontfix',
        'reason': ' $_reason ',
        'closed_at': '2026-11-14T10:14:00Z',
      });
      expect(closed.status, BugStatus.wontfix);
      expect(closed.reason, _reason);
      expect(closed.closedAt, isNotNull);

      final dup = rowFromJson({
        ...base,
        'status': 'duplicate',
        'duplicate_of_code': 'BUG-3F9A',
        'duplicate_of_title': 'Chat issue',
        'duplicate_of_status': 'looking',
        'same_count': 11,
        'notify_when_fixed': true,
      });
      expect(dup.status, BugStatus.duplicate);
      expect(dup.duplicateOf!.code, 'BUG-3F9A');
      expect(dup.duplicateOf!.title, 'Chat issue');
      expect(dup.duplicateOf!.status, BugStatus.looking);
      expect(dup.sameCount, 11);
      expect(dup.notifyWhenFixed, isTrue);
    });

    test('a status the app has never heard of falls back to received', () {
      expect(rowFromJson({...base, 'status': 'archived'}).status, BugStatus.received);
      expect(rowFromJson({...base, 'status': null}).status, BugStatus.received);
      expect(
        rowFromJson({
          ...base,
          'status': 'duplicate',
          'duplicate_of_code': 'BUG-2',
          'duplicate_of_status': 'archived',
        }).duplicateOf!.status,
        BugStatus.received,
      );
    });

    test('missing new columns read as plain defaults', () {
      final r = rowFromJson({...base, 'status': 'looking'});
      expect(r.reason, isNull);
      expect(r.duplicateOf, isNull);
      expect(r.sameCount, 0);
      expect(r.notifyWhenFixed, isFalse);
      expect(r.closedAt, isNull);
    });
  });

  group('screens', () {
    late FeedbackService saved;
    late String? savedVersion;
    setUp(() {
      saved = FeedbackServices.instance;
      savedVersion = AppVersion.current;
      AppVersion.current = '1.4.1';
      DiscoveryTriggers.onUpdate = null;
    });
    tearDown(() {
      FeedbackServices.instance = saved;
      AppVersion.current = savedVersion;
      DiscoveryTriggers.onUpdate = null;
    });

    Future<void> pumpApp(WidgetTester tester, Widget child, {String? at}) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final router = GoRouter(
        initialLocation: at ?? '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(body: SingleChildScrollView(child: child)),
          ),
          GoRoute(
            path: '/lobby/profile/reports/:code',
            builder: (_, s) => Scaffold(
              body: SingleChildScrollView(child: ReportDetailBody(code: s.pathParameters['code']!)),
            ),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pump();
    }

    testWidgets('the list shows closed and same-as rows, neutral and tappable', (tester) async {
      FeedbackServices.instance = FakeFeedbackService()
        ..debugSetRows([
          _row('BUG-7K2M', BugStatus.fixed, fixedIn: '1.4.2'),
          _row(
            'BUG-9D4X',
            BugStatus.duplicate,
            title: 'Messages stuck sending',
            original: const OriginalRef(
              code: 'BUG-3F9A',
              title: 'Chat issue',
              status: BugStatus.looking,
            ),
          ),
          _row('BUG-1C0D', BugStatus.wontfix, title: 'Seek bar jumps on fold', reason: _reason),
          _row('BUG-3F9A', BugStatus.looking, same: 11),
        ]);
      await pumpApp(tester, const ReportsBody());
      expect(find.text('FIXED FROM 1.4.2'), findsOneWidget);
      expect(
        find.text(
          'Fixed from 1.4.2 onward. Rolling out to your store soon. Thank you for flagging it.',
        ),
        findsOneWidget,
      );
      expect(find.text('SAME AS BUG-3F9A'), findsOneWidget);
      expect(find.textContaining('Following BUG-3F9A'), findsOneWidget);
      expect(find.textContaining('looking into it', findRichText: true), findsWidgets);
      expect(find.text('CLOSED'), findsOneWidget);
      expect(find.textContaining('the seek bar steps aside'), findsOneWidget);
      expect(find.textContaining('12 people have sent this one'), findsOneWidget);
      // No Update button without an updater, and none for closed rows.
      expect(find.text('Update now'), findsNothing);
    });

    testWidgets('Update now shows only while the fix is not installed', (tester) async {
      DiscoveryTriggers.onUpdate = () {};
      FeedbackServices.instance = FakeFeedbackService()
        ..debugSetRows([_row('BUG-7K2M', BugStatus.fixed, fixedIn: '1.4.2')]);
      await pumpApp(tester, const ReportsBody());
      expect(find.text('Update now'), findsOneWidget);

      AppVersion.current = '1.4.3';
      await pumpApp(tester, const ReportsBody());
      expect(find.text('Update now'), findsNothing);
      expect(find.textContaining("it's on this device"), findsOneWidget);
    });

    testWidgets('tapping a closed row opens its reason in full', (tester) async {
      FeedbackServices.instance = FakeFeedbackService()
        ..debugSetRows([
          _row('BUG-1C0D', BugStatus.wontfix, title: 'Seek bar jumps on fold', reason: _reason),
        ]);
      await pumpApp(tester, const ReportsBody());
      await tester.tap(find.text('Seek bar jumps on fold'));
      await tester.pumpAndSettle();
      expect(find.text('WHY WE CLOSED THIS'), findsOneWidget);
      expect(find.text(_reason), findsOneWidget);
      expect(find.text('Still happening? Tell us'), findsOneWidget);
      expect(find.textContaining('Sent'), findsOneWidget);
      expect(find.textContaining('closed'), findsWidgets);
    });

    testWidgets('a duplicate page tracks only the original, with its steps', (tester) async {
      FeedbackServices.instance = FakeFeedbackService()
        ..debugSetRows([
          _row(
            'BUG-9D4X',
            BugStatus.duplicate,
            title: 'Messages stuck sending',
            same: 11,
            original: const OriginalRef(
              code: 'BUG-3F9A',
              title: "Chat won't send on cellular",
              status: BugStatus.looking,
            ),
          ),
        ]);
      await pumpApp(tester, const SizedBox(), at: '/lobby/profile/reports/BUG-9D4X');
      expect(find.text('SAME AS BUG-3F9A'), findsOneWidget);
      expect(find.text('TRACKING'), findsOneWidget);
      expect(find.text("Chat won't send on cellular"), findsOneWidget);
      expect(find.text('LOOKING INTO IT'), findsOneWidget);
      for (final step in ['Received', 'Looking into it', 'Fixed']) {
        expect(find.text(step), findsOneWidget);
      }
      expect(
        find.text("12 people have sent this one, so it's near the top of the list."),
        findsOneWidget,
      );
    });

    testWidgets('a duplicate that is alone says nothing about a crowd', (tester) async {
      FeedbackServices.instance = FakeFeedbackService()
        ..debugSetRows([
          _row(
            'BUG-9D4X',
            BugStatus.duplicate,
            same: 1,
            original: const OriginalRef(
              code: 'BUG-3F9A',
              title: 'Chat issue',
              status: BugStatus.received,
            ),
          ),
        ]);
      await pumpApp(tester, const SizedBox(), at: '/lobby/profile/reports/BUG-9D4X');
      expect(find.textContaining('people have sent'), findsNothing);
    });

    testWidgets('an unknown code says so instead of crashing', (tester) async {
      FeedbackServices.instance = FakeFeedbackService();
      await pumpApp(tester, const SizedBox(), at: '/lobby/profile/reports/BUG-NOPE');
      expect(find.textContaining("can't find that report"), findsOneWidget);
    });
  });
}
