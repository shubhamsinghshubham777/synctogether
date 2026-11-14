import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/feedback/contract.dart';
import 'package:synctogether/feedback/discovery/discovery_logic.dart';
import 'package:synctogether/feedback/discovery/discovery_prefs.dart';
import 'package:synctogether/feedback/discovery/discovery_triggers.dart';
import 'package:synctogether/feedback/fake_feedback_service.dart';
import 'package:synctogether/feedback/feedback_services.dart';
import 'package:synctogether/feedback/reports_screen.dart';

BugReportRow row(String code, BugStatus s, {DateTime? at, String? fixedIn}) => BugReportRow(
  code: code,
  category: BugCategory.video,
  title: 'Video went black',
  status: s,
  fixedIn: fixedIn,
  createdAt: at ?? DateTime(2026, 11, 13, 21, 52),
);

Future<DiscoveryTriggers> triggers(
  DateTime Function() clock, [
  Map<String, Object> seed = const {},
]) async {
  SharedPreferences.setMockInitialValues(seed);
  final t = DiscoveryTriggers(
    prefs: DiscoveryPrefs(testPrefs: await SharedPreferences.getInstance()),
    clock: clock,
  );
  return t;
}

void main() {
  final now = DateTime(2026, 11, 13, 22);

  group('logic', () {
    test('nudge: once per session, 14 days after an answer', () {
      expect(nudgeAllowed(now: now, shownThisSession: false), isTrue);
      expect(nudgeAllowed(now: now, shownThisSession: true), isFalse);
      expect(
        nudgeAllowed(
          now: now,
          shownThisSession: false,
          lastAnsweredAt: now.subtract(const Duration(days: 13)),
        ),
        isFalse,
      );
      expect(
        nudgeAllowed(
          now: now,
          shownThisSession: false,
          lastAnsweredAt: now.subtract(const Duration(days: 14)),
        ),
        isTrue,
      );
    });

    test('coach: never first launch, once ever', () {
      expect(coachDue(alreadyShown: false, launches: 1, roomsVisited: 0), isFalse);
      expect(coachDue(alreadyShown: false, launches: 2, roomsVisited: 0), isTrue);
      expect(coachDue(alreadyShown: false, launches: 1, roomsVisited: 1), isTrue);
      expect(coachDue(alreadyShown: true, launches: 9, roomsVisited: 9), isFalse);
    });

    test('review: at most two a year', () {
      final a = [now.subtract(const Duration(days: 100)), now.subtract(const Duration(days: 30))];
      expect(reviewAllowed(now: now, asked: a), isFalse);
      expect(reviewAllowed(now: now, asked: [a.last]), isTrue);
      expect(
        reviewAllowed(now: now, asked: [now.subtract(const Duration(days: 400)), ...a]),
        isFalse,
      );
      expect(
        reviewAllowed(now: now, asked: [now.subtract(const Duration(days: 400)), a.last]),
        isTrue,
      );
    });

    test('newlyFixed skips ones already told', () {
      final rows = [row('BUG-1', BugStatus.fixed), row('BUG-2', BugStatus.looking)];
      expect(newlyFixed(rows, {})?.code, 'BUG-1');
      expect(newlyFixed(rows, {'BUG-1'}), isNull);
    });

    test('reportsSummary', () {
      expect(reportsSummary([]), 'Nothing sent yet');
      expect(
        reportsSummary([
          row('a', BugStatus.fixed),
          row('b', BugStatus.received),
          row('c', BugStatus.saved),
        ]),
        '2 sent · 1 fixed',
      );
      expect(reportsSummary([row('c', BugStatus.saved)]), '1 saved on this device');
    });

    test('analytics reasons are the catalog values', () {
      expect(
        [for (final r in NudgeReason.values) nudgeAnalyticsReason(r)],
        ['stall', 'reconnect', 'upload', 'error', 'crash'],
      );
    });

    test('reportWhen', () {
      expect(reportWhen(DateTime(2026, 11, 13, 9, 5), now), 'Today 09:05');
      expect(reportWhen(DateTime(2026, 11, 11, 21, 52), now), 'Wed 21:52');
      expect(reportWhen(DateTime(2026, 10, 4), now), 'Oct 4');
    });
  });

  group('triggers', () {
    late FeedbackService saved;
    setUp(() => saved = FeedbackServices.instance);
    tearDown(() => FeedbackServices.instance = saved);

    test('nudge shows once, then the cooldown holds across launches', () async {
      FeedbackServices.instance = FakeFeedbackService();
      var clock = now;
      final t = await triggers(() => clock);
      await t.start();
      t.notify(NudgeReason.streamStall);
      expect(t.nudge, NudgeReason.streamStall);
      t.notify(NudgeReason.uploadFailed); // already showing
      await t.answerNudge(accepted: false);
      expect(t.nudge, isNull);
      t.notify(NudgeReason.recoveredError); // same session
      expect(t.nudge, isNull);

      // New session, 3 days later: still cooling down. 15 days later: free.
      final prefs = DiscoveryPrefs(testPrefs: await SharedPreferences.getInstance());
      clock = now.add(const Duration(days: 3));
      final t2 = DiscoveryTriggers(prefs: prefs, clock: () => clock);
      await t2.start();
      t2.notify(NudgeReason.previousCrash);
      expect(t2.nudge, isNull);
      clock = now.add(const Duration(days: 15));
      final t3 = DiscoveryTriggers(prefs: prefs, clock: () => clock);
      await t3.start();
      t3.notify(NudgeReason.previousCrash);
      expect(t3.nudge, NudgeReason.previousCrash);
    });

    test('coach waits for the second launch and needs an anchor', () async {
      FeedbackServices.instance = FakeFeedbackService();
      final t = await triggers(() => now);
      await t.start(); // launch 1
      t.anchorChanged(true);
      expect(t.coachVisible, isFalse);

      final prefs = DiscoveryPrefs(testPrefs: await SharedPreferences.getInstance());
      final t2 = DiscoveryTriggers(prefs: prefs, clock: () => now);
      await t2.start(); // launch 2
      expect(t2.coachVisible, isFalse); // no anchor yet
      t2.anchorChanged(true);
      expect(t2.coachVisible, isTrue);
      await t2.dismissCoach();
      expect(t2.coachVisible, isFalse);

      final t3 = DiscoveryTriggers(prefs: prefs, clock: () => now);
      await t3.start();
      t3.anchorChanged(true);
      expect(t3.coachVisible, isFalse); // once ever
    });

    test('a visited room makes the coach due on launch 1', () async {
      FeedbackServices.instance = FakeFeedbackService();
      final t = await triggers(() => now);
      await t.start();
      t.anchorChanged(true);
      await t.noteRoomVisited();
      expect(t.coachVisible, isTrue);
    });

    test('fixed banner appears for a fixed report and stays gone once dismissed', () async {
      final svc = FakeFeedbackService();
      FeedbackServices.instance = svc;
      final t = await triggers(() => now);
      await t.start();
      expect(t.fixedBanner, isNull);
      svc.debugSetRows([row('BUG-7K2M', BugStatus.fixed, fixedIn: '1.4.2')]);
      await Future<void>.delayed(Duration.zero);
      expect(t.fixedBanner?.code, 'BUG-7K2M');
      await t.dismissFixed();
      svc.debugSetRows([row('BUG-7K2M', BugStatus.fixed, fixedIn: '1.4.2')]);
      await Future<void>.delayed(Duration.zero);
      expect(t.fixedBanner, isNull);
    });

    test('review ask needs the store seam', () async {
      final t = await triggers(() => now);
      DiscoveryTriggers.onRate = null;
      expect(await t.shouldAskReview(), isFalse);
      DiscoveryTriggers.onRate = () {};
      addTearDown(() => DiscoveryTriggers.onRate = null);
      expect(await t.shouldAskReview(), isTrue);
      await t.recordReviewAsked();
      await t.recordReviewAsked();
      expect(await t.shouldAskReview(), isFalse);
    });
  });

  group('reports screen', () {
    testWidgets('lists the four states', (tester) async {
      final svc = FakeFeedbackService()
        ..debugSetRows([
          row('BUG-7K2M', BugStatus.fixed, fixedIn: '1.4.2'),
          row('BUG-3F9A', BugStatus.looking),
          row('BUG-1C0D', BugStatus.received),
          row('local', BugStatus.saved),
        ]);
      final saved = FeedbackServices.instance;
      FeedbackServices.instance = svc;
      addTearDown(() => FeedbackServices.instance = saved);
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: ReportsBody())),
        ),
      );
      await tester.pump();
      expect(find.text('FIXED FROM 1.4.2'), findsOneWidget);
      expect(find.text('LOOKING INTO IT'), findsOneWidget);
      expect(find.text('RECEIVED'), findsOneWidget);
      expect(find.text('SAVED ON THIS DEVICE'), findsOneWidget);
      expect(find.text('BUG-7K2M'), findsOneWidget);
    });
  });
}
