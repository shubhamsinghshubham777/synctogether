import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/feedback/discovery/coach_scrim.dart';
import 'package:synctogether/feedback/discovery/discovery_anchor.dart';
import 'package:synctogether/feedback/discovery/discovery_host.dart';
import 'package:synctogether/feedback/discovery/discovery_prefs.dart';
import 'package:synctogether/feedback/discovery/discovery_triggers.dart';
import 'package:synctogether/feedback/fake_feedback_service.dart';
import 'package:synctogether/feedback/feedback_services.dart';
import 'package:synctogether/ui/pt_theme.dart';

final _boundary = GlobalKey();
var _taps = 0;

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
                // Stands in for the bug button: same anchor, a counted tap.
                DiscoveryAnchor(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _taps++,
                    child: const SizedBox(width: 36, height: 36),
                  ),
                ),
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

Widget _app(GoRouter router) => MaterialApp.router(
  debugShowCheckedModeBanner: false,
  theme: buildPTTheme(),
  routerConfig: router,
  builder: (context, child) => RepaintBoundary(
    key: _boundary,
    child: DiscoveryHost(router: router, child: child!),
  ),
);

Future<void> _show(
  WidgetTester tester, {
  Size size = const Size(1280, 800),
  double textScale = 1,
  bool due = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  _taps = 0;
  FeedbackServices.instance = FakeFeedbackService();
  SharedPreferences.setMockInitialValues({});
  DiscoveryTriggers.instance = DiscoveryTriggers(
    prefs: DiscoveryPrefs(testPrefs: await SharedPreferences.getInstance()),
  );
  await tester.pumpWidget(_app(_router()));
  if (due) await DiscoveryTriggers.instance.noteRoomVisited();
  await DiscoveryTriggers.instance.start();
  // The anchor publishes after a frame, then the mark measures after another.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

CoachScrimPainter _painter(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find.descendant(of: find.byType(CoachScrim), matching: find.byType(CustomPaint)),
            )
            .painter!
        as CoachScrimPainter;

Future<Color> _pixel(WidgetTester tester, Offset at) async {
  final boundary = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final c = await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final i = (at.dy.round() * image.width + at.dx.round()) * 4;
    return Color.fromARGB(
      data.getUint8(i + 3),
      data.getUint8(i),
      data.getUint8(i + 1),
      data.getUint8(i + 2),
    );
  });
  return c!;
}

int _chan(double v) => (v * 255).round();

void main() {
  testWidgets('no scrim while the coach mark is not shown', (tester) async {
    await _show(tester, due: false); // first launch: not due yet
    expect(find.text('Hit a snag? Tap the bug.'), findsNothing);
    expect(find.byType(CoachScrim), findsNothing);
  });

  testWidgets('the scrim has its hole on the bug button', (tester) async {
    await _show(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CoachScrim), findsOneWidget);
    final anchor = DiscoveryAnchor.activeRect()!;
    final hole = _painter(tester).hole.outerRect;
    expect(hole.contains(anchor.topLeft), isTrue);
    expect(hole.contains(anchor.bottomRight), isTrue);
    // Hugs the button: a few px of ring and gap, never a big window.
    expect(hole.width - anchor.width, lessThan(20));
    expect(hole.height - anchor.height, lessThan(20));
  });

  for (final c in [
    (name: 'desktop', size: const Size(1280, 800), scale: 1.0),
    (name: 'phone', size: const Size(390, 844), scale: 1.0),
    (name: 'phone at 2x text', size: const Size(390, 844), scale: 2.0),
  ]) {
    testWidgets('the hole is lit and the rest is dimmed (${c.name})', (tester) async {
      await _show(tester, size: c.size, textScale: c.scale);
      await tester.pump(const Duration(milliseconds: 600));
      final anchor = DiscoveryAnchor.activeRect()!;
      // Between the button and its ring: inside the hole, nothing of ours is
      // painted there, so it must show the page untouched.
      final lit = await _pixel(tester, Offset(anchor.left - 1, anchor.center.dy));
      // A corner of the window, far from the hole and the card.
      final dim = await _pixel(tester, Offset(6, c.size.height - 6));
      final plain = PTColors.canvas;
      final shaded = Color.alphaBlend(
        PTColors.scrimBase.withValues(alpha: CoachScrim.dim),
        PTColors.canvas,
      );
      expect((lit.r * 255 - plain.r * 255).abs(), lessThan(2));
      expect((lit.g * 255 - plain.g * 255).abs(), lessThan(2));
      expect(_chan(dim.r), closeTo(_chan(shaded.r), 2));
      expect(_chan(dim.g), closeTo(_chan(shaded.g), 2));
      expect(_chan(dim.r), lessThan(_chan(lit.r)));
    });
  }

  testWidgets('a tap on the dim dismisses and saves "seen"', (tester) async {
    await _show(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Hit a snag? Tap the bug.'), findsOneWidget);
    await tester.tapAt(const Offset(40, 700));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CoachScrim), findsNothing);
    expect(find.text('Hit a snag? Tap the bug.'), findsNothing);
    expect(DiscoveryTriggers.instance.coachVisible, isFalse);
    expect((await SharedPreferences.getInstance()).getBool('feedback.coach_shown'), isTrue);
    expect(_taps, 0, reason: 'a tap on the dim is not a tap on the app underneath');
  });

  testWidgets('"Got it" dismisses and saves "seen"', (tester) async {
    await _show(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Got it'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CoachScrim), findsNothing);
    expect((await SharedPreferences.getInstance()).getBool('feedback.coach_shown'), isTrue);
  });

  testWidgets('a tap on the lit button reaches it once and ends the mark', (tester) async {
    await _show(tester);
    await tester.pump(const Duration(milliseconds: 400));
    final at = DiscoveryAnchor.activeRect()!.center;
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_taps, 1);
    expect(find.byType(CoachScrim), findsNothing);
    expect((await SharedPreferences.getInstance()).getBool('feedback.coach_shown'), isTrue);
  });

  testWidgets('Escape dismisses and saves "seen"', (tester) async {
    await _show(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CoachScrim), findsNothing);
    expect((await SharedPreferences.getInstance()).getBool('feedback.coach_shown'), isTrue);
  });

  testWidgets('the card absorbs taps (nothing underneath fires)', (tester) async {
    await _show(tester);
    await tester.pump(const Duration(milliseconds: 400));
    // Text inside the card is not "the dim": it must not dismiss.
    await tester.tap(find.text('Hit a snag? Tap the bug.'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Hit a snag? Tap the bug.'), findsOneWidget);
  });

  testWidgets('fades in over 220 ms', (tester) async {
    await _show(tester);
    // A few frames after it appears, 220 ms is far from done.
    expect(_painter(tester).opacity, lessThan(CoachScrim.dim - 0.005));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_painter(tester).opacity, closeTo(CoachScrim.dim, 0.001));
  });

  testWidgets('fades in within 100 ms under reduce-motion', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
    );
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _show(tester);
    await tester.pump(const Duration(milliseconds: 60));
    expect(_painter(tester).opacity, closeTo(CoachScrim.dim, 0.001));
  });

  test('the painter hit-tests "not hit" inside the hole only', () {
    final hole = RRect.fromRectAndRadius(
      const Rect.fromLTWH(100, 10, 40, 40),
      const Radius.circular(8),
    );
    final p = CoachScrimPainter(fade: const AlwaysStoppedAnimation(1), hole: hole);
    expect(p.hitTest(const Offset(120, 30)), isFalse);
    expect(p.hitTest(const Offset(10, 10)), isTrue);
    expect(p.opacity, CoachScrim.dim);
  });
}
