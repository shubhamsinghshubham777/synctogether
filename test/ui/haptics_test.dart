import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/ui/haptics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => PTHaptics.debugOnFire = null);

  test('each moment maps to one weight', () {
    final fired = <String>[];
    PTHaptics.debugOnFire = fired.add;
    PTHaptics.selection();
    PTHaptics.tap();
    PTHaptics.moment();
    expect(fired, ['selection', 'tap', 'moment']);
  });

  test('reaches the platform channel on a phone', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') calls.add(call.arguments as String);
        return null;
      },
    );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    PTHaptics.tap();
    PTHaptics.moment();
    await Future<void>.delayed(Duration.zero);
    // The test host is not a desktop build, so the calls go through.
    expect(calls, ['HapticFeedbackType.lightImpact', 'HapticFeedbackType.mediumImpact']);
  });

  test('desktop never touches the channel', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') calls.add(call.arguments as String);
        return null;
      },
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
    PTHaptics.tap();
    PTHaptics.moment();
    await Future<void>.delayed(Duration.zero);
    expect(calls, isEmpty);
  });
}
