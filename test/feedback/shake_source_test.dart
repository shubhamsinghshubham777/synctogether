import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/feedback/bug_report.dart';
import 'package:synctogether/feedback/contract.dart';
import 'package:synctogether/feedback/fake_feedback_service.dart';
import 'package:synctogether/feedback/feedback_services.dart';
import 'package:synctogether/feedback/shake_source.dart';
import 'package:synctogether/feedback/shake_to_report.dart';
import 'package:synctogether/ui/pt_theme.dart';

/// A source the test fires by hand and whose subscriptions it counts.
class _FakeSource implements ShakeSource {
  final controller = StreamController<void>.broadcast();
  int built = 0;
  int listening = 0;

  @override
  Stream<void> get shakes {
    built++;
    late final StreamController<void> c;
    c = StreamController<void>(onListen: () => listening++, onCancel: () => listening--);
    controller.stream.listen((_) => c.add(null));
    return c.stream;
  }

  void shake() => controller.add(null);
}

class _DummySource implements ShakeSource {
  @override
  Stream<void> get shakes => const Stream<void>.empty();
}

GoRouter _router() => GoRouter(
  initialLocation: '/lobby',
  routes: [
    GoRoute(
      path: '/lobby',
      builder: (_, _) => const Scaffold(body: Text('lobby')),
    ),
  ],
);

void main() {
  late FeedbackService saved;
  setUp(() {
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

  group('which source a platform gets', () {
    test('iOS builds the native source and never touches the accelerometer', () {
      var native = 0, accel = 0;
      final s = ShakeToReport.defaultSource(
        platform: TargetPlatform.iOS,
        native: () {
          native++;
          return _DummySource();
        },
        accelerometer: () {
          accel++;
          return _DummySource();
        },
      );
      expect(s, isA<_DummySource>());
      expect([native, accel], [1, 0]);
    });

    test('Android builds the accelerometer source and no native one', () {
      var native = 0, accel = 0;
      ShakeToReport.defaultSource(
        platform: TargetPlatform.android,
        native: () {
          native++;
          return _DummySource();
        },
        accelerometer: () {
          accel++;
          return _DummySource();
        },
      );
      expect([native, accel], [0, 1]);
    });
  });

  group('NativeShakeSource', () {
    const channel = MethodChannel('app.synctogether/test_shake');

    Future<void> nativeShake() =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(const MethodCall('shake')),
          (_) {},
        );

    test('one native call is one event, and only while listened to', () async {
      final source = NativeShakeSource(channel: channel);
      await nativeShake(); // nobody listening: goes nowhere
      var count = 0;
      final sub = source.shakes.listen((_) => count++);
      await nativeShake();
      await nativeShake();
      await Future<void>.delayed(Duration.zero);
      expect(count, 2);

      await sub.cancel();
      await nativeShake();
      await Future<void>.delayed(Duration.zero);
      expect(count, 2, reason: 'the handler is gone once the last listener cancels');
    });

    test('any other method is ignored', () async {
      final source = NativeShakeSource(channel: channel);
      var count = 0;
      final sub = source.shakes.listen((_) => count++);
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(const MethodCall('other')),
        (_) {},
      );
      await Future<void>.delayed(Duration.zero);
      expect(count, 0);
      await sub.cancel();
    });
  });

  group('ShakeToReport with a source', () {
    ShakeToReport make(_FakeSource source, {Duration Function()? clock}) => ShakeToReport(
      source: () => source,
      clock: clock,
      phoneProbe: () async => true,
      touchOverride: true,
    );

    testWidgets('subscribes only while phone, enabled, foreground and attached', (t) async {
      final source = _FakeSource();
      final shake = make(source);
      final router = _router();
      await t.pumpWidget(MaterialApp.router(routerConfig: router, theme: buildPTTheme()));

      expect(source.listening, 0, reason: 'nothing before it is attached');
      await shake.attach(router);
      expect(source.listening, 1);

      await shake.setEnabled(false);
      expect(source.listening, 0);
      await shake.setEnabled(true);
      expect(source.listening, 1);

      shake.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(source.listening, 0);
      shake.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(source.listening, 1);

      shake.detach(router);
      expect(source.listening, 0);
    });

    testWidgets('a tablet never subscribes at all', (t) async {
      final source = _FakeSource();
      final shake = ShakeToReport(
        source: () => source,
        phoneProbe: () async => false,
        touchOverride: true,
      );
      final router = _router();
      await t.pumpWidget(MaterialApp.router(routerConfig: router, theme: buildPTTheme()));
      await shake.attach(router);
      expect(source.built, 0);
    });

    testWidgets('a shake opens the sheet, and a second one inside the cooldown does not', (
      t,
    ) async {
      var now = Duration.zero;
      final source = _FakeSource();
      final shake = make(source, clock: () => now);
      final router = _router();
      await t.pumpWidget(MaterialApp.router(routerConfig: router, theme: buildPTTheme()));
      await shake.attach(router);
      now += ShakeToReport.settle;

      source.shake();
      await t.pump(const Duration(milliseconds: 400));
      expect(BugReport.isOpen, isTrue);

      // Close it, then shake again within the cooldown: swallowed.
      await t.tapAt(const Offset(5, 5));
      await t.pump(const Duration(milliseconds: 400));
      await t.pump(const Duration(milliseconds: 400));
      expect(BugReport.isOpen, isFalse);
      now += const Duration(milliseconds: 500);
      source.shake();
      await t.pump(const Duration(milliseconds: 400));
      expect(BugReport.isOpen, isFalse);

      // Past the cooldown it opens again.
      now += ShakeToReport.cooldown;
      source.shake();
      await t.pump(const Duration(milliseconds: 400));
      expect(BugReport.isOpen, isTrue);
    });
  });
}
