import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/feedback/contract.dart';
import 'package:synctogether/ui/coach_scrim.dart';
import 'package:synctogether/feedback/discovery/discovery_host.dart';
import 'package:synctogether/feedback/discovery/discovery_logic.dart';
import 'package:synctogether/feedback/discovery/discovery_prefs.dart';
import 'package:synctogether/feedback/discovery/discovery_triggers.dart';
import 'package:synctogether/feedback/discovery/help_rows.dart';
import 'package:synctogether/feedback/shake_to_report.dart';
import 'package:synctogether/feedback/fake_feedback_service.dart';
import 'package:synctogether/feedback/feedback_services.dart';
import 'package:synctogether/feedback/reports_screen.dart';
import 'package:synctogether/feedback/ui/bug_report_button.dart';
import 'package:synctogether/ui/pt_theme.dart';

import '../support/screen_matrix.dart';
import 'layout_support.dart';

BugReportRow _row(String code, BugStatus s, String title, {String? fixedIn}) => BugReportRow(
  code: code,
  category: BugCategory.video,
  title: title,
  status: s,
  fixedIn: fixedIn,
  createdAt: DateTime.now().subtract(const Duration(hours: 2)),
);

/// A lobby-shaped stand-in: a header with the real bug button, dressed in the
/// real host the way main.dart does it.
Widget _app(GoRouter router) => MaterialApp.router(
  debugShowCheckedModeBanner: false,
  theme: buildPTTheme(),
  routerConfig: router,
  builder: (context, child) => DiscoveryHost(router: router, child: child!),
);

GoRouter _router() => GoRouter(
  initialLocation: '/lobby',
  routes: [
    GoRoute(
      path: '/lobby',
      builder: (context, state) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const Expanded(child: Text('sync·together')),
                const BugReportButton(),
                const SizedBox(width: 10),
                const CircleAvatar(radius: 18, child: Text('M')),
              ],
            ),
          ),
        ),
      ),
    ),
  ],
);

void main() {
  late FeedbackService saved;
  setUp(() async {
    saved = FeedbackServices.instance;
    SharedPreferences.setMockInitialValues({});
    DiscoveryTriggers.instance = DiscoveryTriggers(
      prefs: DiscoveryPrefs(testPrefs: await SharedPreferences.getInstance()),
    );
  });
  tearDown(() => FeedbackServices.instance = saved);

  screenMatrix('feedback/reports', (tester, c, s) async {
    FeedbackServices.instance = FakeFeedbackService()
      ..debugSetRows([
        _row('BUG-7K2M', BugStatus.fixed, 'Video went black', fixedIn: '1.4.2'),
        _row('BUG-3F9A', BugStatus.looking, "Chat won't send on cellular"),
        _row('BUG-1C0D', BugStatus.received, 'Seek bar jumps on fold'),
        _row('local', BugStatus.saved, 'No signal in the lift'),
      ]);
    await pumpAtSize(tester, const ReportsScreen(), c, textScale: s, singlePane: true);
    await tester.pump(const Duration(milliseconds: 400));
    await finishCase(tester);
  });

  screenMatrix('feedback/reports-empty', (tester, c, s) async {
    FeedbackServices.instance = FakeFeedbackService();
    await pumpAtSize(tester, const ReportsScreen(), c, textScale: s, singlePane: true);
    await tester.pump(const Duration(milliseconds: 400));
    await finishCase(tester);
  });

  screenMatrix('feedback/coach-mark', (tester, c, s) async {
    FeedbackServices.instance = FakeFeedbackService();
    await pumpAtSize(tester, _app(_router()), c, textScale: s, wrapInApp: false);
    await DiscoveryTriggers.instance.noteRoomVisited();
    await DiscoveryTriggers.instance.start();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Hit a snag? Tap the bug.'), findsOneWidget);
    // Nothing the coach mark paints may leave the window: the ring (4 px in)
    // and the card (12 px in), wherever this layout puts the bug button.
    final window = tester.getRect(find.byType(DiscoveryHost));
    final safe = MediaQuery.paddingOf(tester.element(find.byType(DiscoveryHost)));
    final ring = tester.getRect(find.byKey(const ValueKey('coach-ring')));
    final ringBounds = Rect.fromLTRB(
      window.left + safe.left + 4,
      window.top + safe.top + 4,
      window.right - safe.right - 4,
      window.bottom - safe.bottom - 4,
    );
    expect(ring.left, greaterThanOrEqualTo(ringBounds.left - 0.01), reason: 'ring left');
    expect(ring.top, greaterThanOrEqualTo(ringBounds.top - 0.01), reason: 'ring top');
    expect(ring.right, lessThanOrEqualTo(ringBounds.right + 0.01), reason: 'ring right');
    expect(ring.bottom, lessThanOrEqualTo(ringBounds.bottom + 0.01), reason: 'ring bottom');
    final card = tester.getRect(
      find.ancestor(of: find.text('Got it'), matching: find.byType(Container)).last,
    );
    expect(card.left, greaterThanOrEqualTo(window.left + 12 - 0.01), reason: 'card left');
    expect(card.right, lessThanOrEqualTo(window.right - 12 + 0.01), reason: 'card right');
    // The dim covers the whole window and has its hole on the lit button.
    expect(tester.getRect(find.byType(CoachScrim)), window, reason: 'scrim spans the window');
    final hole =
        (tester
                    .widget<CustomPaint>(
                      find.descendant(
                        of: find.byType(CoachScrim),
                        matching: find.byType(CustomPaint),
                      ),
                    )
                    .painter!
                as CoachScrimPainter)
            .hole
            .outerRect;
    expect(hole.contains(ring.center), isTrue, reason: 'hole is on the button');
    expect(hole.shortestSide, lessThan(ring.shortestSide + 4), reason: 'hole hugs the ring');
    await finishCase(tester);
  });

  screenMatrix('feedback/nudge-and-fixed', (tester, c, s) async {
    final svc = FakeFeedbackService()
      ..debugSetRows([_row('BUG-7K2M', BugStatus.fixed, 'Video went black', fixedIn: '1.4.2')]);
    FeedbackServices.instance = svc;
    await pumpAtSize(tester, _app(_router()), c, textScale: s, wrapInApp: false);
    await DiscoveryTriggers.instance.start();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.textContaining('Fixed from 1.4.2 onward'), findsOneWidget);
    DiscoveryTriggers.instance.notify(NudgeReason.streamStall);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text("That didn't go smoothly."), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    await finishCase(tester);
  });

  screenMatrix('feedback/shake-help-row', (tester, c, s) async {
    FeedbackServices.instance = FakeFeedbackService();
    final shake = ShakeToReport.instance;
    shake.available.value = true;
    addTearDown(() => shake.available.value = false);
    await pumpAtSize(
      tester,
      const Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(padding: EdgeInsets.all(20), child: FeedbackHelpRows()),
        ),
      ),
      c,
      textScale: s,
      singlePane: true,
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Shake to report'), findsOneWidget);
    await finishCase(tester);
  });

  screenMatrix('feedback/shake-intro-banner', (tester, c, s) async {
    FeedbackServices.instance = FakeFeedbackService();
    final shake = ShakeToReport.instance;
    await pumpAtSize(tester, _app(_router()), c, textScale: s, wrapInApp: false);
    shake.introPending.value = true;
    addTearDown(() => shake.introPending.value = false);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Shaking opens bug reports.'), findsOneWidget);
    expect(find.text('Keep it'), findsOneWidget);
    expect(find.text('Turn off'), findsOneWidget);
    await finishCase(tester);
  });
}
