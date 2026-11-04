import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/av/background_call.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/background_call');
  late List<MethodCall> calls;
  var fail = false;

  setUp(() {
    calls = [];
    fail = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        calls.add(call);
        if (fail) throw PlatformException(code: 'nope');
        return null;
      },
    );
  });

  group('BackgroundCall', () {
    test('is inert where unsupported', () async {
      final bc = BackgroundCall(channel: channel, supported: () => false);
      await bc.update(mic: true, cam: false, title: 'Room');
      await bc.stop();
      expect(calls, isEmpty);
      expect(bc.isRunning, isFalse);
    });

    test('starts once and only re-sends when mic or cam change', () async {
      final bc = BackgroundCall(channel: channel, supported: () => true);
      await bc.update(mic: false, cam: false, title: 'Room');
      await bc.update(mic: false, cam: false, title: 'Room');
      await bc.update(mic: true, cam: false, title: 'Room');
      expect(calls.map((c) => c.method), ['start', 'start']);
      expect(calls.last.arguments, {'mic': true, 'cam': false, 'title': 'Room'});
    });

    test('stop is sent once and only when running', () async {
      final bc = BackgroundCall(channel: channel, supported: () => true);
      await bc.stop();
      expect(calls, isEmpty);
      await bc.update(mic: false, cam: false, title: 'Room');
      await bc.stop();
      await bc.stop();
      expect(calls.map((c) => c.method), ['start', 'stop']);
      expect(bc.isRunning, isFalse);
    });

    test('a failed start is swallowed and retried on the next change', () async {
      final bc = BackgroundCall(channel: channel, supported: () => true);
      fail = true;
      await bc.update(mic: false, cam: false, title: 'Room');
      expect(bc.isRunning, isFalse);
      fail = false;
      await bc.update(mic: false, cam: false, title: 'Room');
      expect(bc.isRunning, isTrue);
      expect(calls, hasLength(2));
    });
  });

  group('shouldHoldScreenAwake', () {
    test('only on mobile, in a room, while playing', () {
      expect(shouldHoldScreenAwake(mobile: true, inRoom: true, playing: true), isTrue);
      expect(shouldHoldScreenAwake(mobile: true, inRoom: true, playing: false), isFalse);
      expect(shouldHoldScreenAwake(mobile: true, inRoom: false, playing: true), isFalse);
      expect(shouldHoldScreenAwake(mobile: false, inRoom: true, playing: true), isFalse);
    });
  });
}
