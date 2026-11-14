import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/feedback/accelerometer_shake_source.dart';
import 'package:synctogether/feedback/bug_report.dart';
import 'package:synctogether/feedback/contract.dart';
import 'package:synctogether/feedback/fake_feedback_service.dart';
import 'package:synctogether/feedback/feedback_services.dart';
import 'package:synctogether/feedback/shake_to_report.dart';
import 'package:synctogether/ui/pt_theme.dart';

typedef _Sample = ({double x, double y, double z});

/// A clock the test moves by hand and a sensor it feeds by hand.
class _Rig {
  _Rig({this.phone = true, this.touch = true, SharedPreferences? prefs}) {
    shake = ShakeToReport(
      prefs: prefs,
      source: () => AccelerometerShakeSource(sensor: () => sensor.stream, clock: () => now),
      clock: () => now,
      phoneProbe: () async => phone,
      touchOverride: touch,
    );
  }

  final bool phone;
  final bool touch;
  final sensor = StreamController<_Sample>.broadcast();
  Duration now = Duration.zero;
  late final ShakeToReport shake;

  /// Four alternating swings 120 ms apart: a deliberate shake.
  Future<void> doShake(WidgetTester t) async {
    for (var i = 0; i < 4; i++) {
      sensor.add((x: i.isEven ? 22.0 : -22.0, y: 0, z: 0));
      now += const Duration(milliseconds: 120);
      await t.pump(const Duration(milliseconds: 1));
    }
  }
}

GoRouter _router(String start) => GoRouter(
  initialLocation: start,
  routes: [
    GoRoute(
      path: '/login',
      builder: (_, _) => const Scaffold(body: Text('login')),
    ),
    GoRoute(
      path: '/lobby',
      builder: (_, _) => const Scaffold(body: Text('lobby')),
    ),
  ],
);

Future<void> _pumpApp(WidgetTester t, GoRouter r) async {
  await t.pumpWidget(MaterialApp.router(routerConfig: r, theme: buildPTTheme()));
  await t.pump(const Duration(milliseconds: 50));
}

void main() {
  late FeedbackService saved;
  setUp(() async {
    saved = FeedbackServices.instance;
    FeedbackServices.instance = FakeFeedbackService();
    SharedPreferences.setMockInitialValues({});
    BugReport.debugReset();
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (_) async => null,
    );
  });
  tearDown(() => FeedbackServices.instance = saved);

  group('setting', () {
    testWidgets('is on by default and survives a restart', (t) async {
      final prefs = await SharedPreferences.getInstance();
      final a = _Rig(prefs: prefs);
      await a.shake.load();
      expect(a.shake.enabled.value, isTrue);

      await a.shake.setEnabled(false);
      expect(prefs.getBool('feedback.shake_enabled'), isFalse);

      final b = _Rig(prefs: await SharedPreferences.getInstance());
      await b.shake.load();
      expect(b.shake.enabled.value, isFalse);
    });

    testWidgets('"Turn off" on the intro flips the setting, "Keep it" does not, once ever', (
      t,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      final keep = _Rig(prefs: prefs);
      await keep.shake.load();
      keep.shake.introPending.value = true;
      await keep.shake.answerIntro(keep: true);
      expect(keep.shake.introPending.value, isFalse);
      expect(keep.shake.enabled.value, isTrue);
      expect(keep.shake.introAnswered, isTrue);

      SharedPreferences.setMockInitialValues({});
      final off = _Rig(prefs: await SharedPreferences.getInstance());
      await off.shake.load();
      await off.shake.answerIntro(keep: false);
      expect(off.shake.enabled.value, isFalse);
      expect(off.shake.introAnswered, isTrue);
    });
  });

  group('listening', () {
    testWidgets('reads the sensor only on a phone with the setting on, in the foreground', (
      t,
    ) async {
      final r = _Rig();
      final router = _router('/lobby');
      await _pumpApp(t, router);
      await r.shake.attach(router);
      expect(r.shake.listening, isTrue);
      expect(r.shake.available.value, isTrue);

      await r.shake.setEnabled(false);
      expect(r.shake.listening, isFalse);
      await r.shake.setEnabled(true);
      expect(r.shake.listening, isTrue);

      r.shake.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(r.shake.listening, isFalse);
      r.shake.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(r.shake.listening, isTrue);

      r.shake.detach(router);
      expect(r.shake.listening, isFalse);
    });

    testWidgets('a remount (new host attaches before the old one detaches) keeps listening', (
      t,
    ) async {
      final r = _Rig();
      final router = _router('/lobby');
      await _pumpApp(t, router);
      await r.shake.attach(router); // the first host
      await r.shake.attach(router); // the remounted host, mounted first
      r.shake.detach(router); // the old host is disposed afterwards
      expect(r.shake.listening, isTrue);
      r.shake.detach(router);
      expect(r.shake.listening, isFalse);
    });

    testWidgets('a tablet or a non-touch platform never reads the sensor', (t) async {
      final tablet = _Rig(phone: false);
      final desktop = _Rig(touch: false);
      final router = _router('/lobby');
      await _pumpApp(t, router);
      await tablet.shake.attach(router);
      await desktop.shake.attach(router);
      expect(tablet.shake.listening, isFalse);
      expect(tablet.shake.available.value, isFalse);
      expect(desktop.shake.listening, isFalse);
    });
  });

  group('triggering', () {
    testWidgets('a shake opens the report sheet once it has settled', (t) async {
      final r = _Rig();
      final router = _router('/lobby');
      await _pumpApp(t, router);
      await r.shake.attach(router);
      r.now += ShakeToReport.settle;

      await r.doShake(t);
      await t.pump(const Duration(milliseconds: 400));
      expect(BugReport.isOpen, isTrue);
      expect(find.textContaining('Something off?'), findsOneWidget);
    });

    testWidgets('ignored while the app is still starting up', (t) async {
      final r = _Rig();
      final router = _router('/lobby');
      await _pumpApp(t, router);
      await r.shake.attach(router);
      r.now += const Duration(milliseconds: 1000);
      expect(r.shake.ignoreReason(), 'starting up');

      await r.doShake(t);
      await t.pump(const Duration(milliseconds: 400));
      expect(BugReport.isOpen, isFalse);
    });

    testWidgets('ignored on the login page', (t) async {
      final r = _Rig();
      final router = _router('/login');
      await _pumpApp(t, router);
      await r.shake.attach(router);
      r.now += ShakeToReport.settle;
      expect(r.shake.ignoreReason(), 'login');
    });

    testWidgets('ignored while fullscreen video is playing, and again once it stops', (t) async {
      final r = _Rig();
      final router = _router('/lobby');
      await _pumpApp(t, router);
      await r.shake.attach(router);
      r.now += ShakeToReport.settle;

      var immersivePlaying = true;
      final unregister = r.shake.registerBlocker(() => immersivePlaying);
      expect(r.shake.ignoreReason(), 'immersive playback');
      await r.doShake(t);
      await t.pump(const Duration(milliseconds: 400));
      expect(BugReport.isOpen, isFalse);

      immersivePlaying = false;
      expect(r.shake.ignoreReason(), isNull);
      unregister();
    });

    testWidgets('ignored while a report is already open, so typing is not reset', (t) async {
      final r = _Rig();
      final router = _router('/lobby');
      await _pumpApp(t, router);
      await r.shake.attach(router);
      r.now += ShakeToReport.settle;

      await r.doShake(t);
      await t.pump(const Duration(milliseconds: 400));
      expect(BugReport.isOpen, isTrue);
      expect(r.shake.ignoreReason(), 'report open');
    });

    testWidgets('closing the report after a shake raises the one-time intro, not before', (
      t,
    ) async {
      final r = _Rig();
      final router = _router('/lobby');
      await _pumpApp(t, router);
      await r.shake.attach(router);
      r.now += ShakeToReport.settle;

      await r.doShake(t);
      await t.pump(const Duration(milliseconds: 400));
      expect(r.shake.introPending.value, isFalse);

      // Dismiss the sheet by tapping the barrier.
      await t.tapAt(const Offset(5, 5));
      await t.pump(const Duration(milliseconds: 400));
      await t.pump(const Duration(milliseconds: 400));
      expect(BugReport.isOpen, isFalse);
      expect(r.shake.introPending.value, isTrue);
    });
  });
}
