import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/av/background_call.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/background_call');
  late List<MethodCall> calls;
  var fail = false;
  // What the fake native side reports for `isRunning`.
  var nativeRunning = true;

  setUp(() {
    calls = [];
    fail = false;
    nativeRunning = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        calls.add(call);
        if (call.method == 'isRunning') return nativeRunning;
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
      expect(calls.map((c) => c.method).where((m) => m == 'start'), ['start', 'start']);
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

  group('BackgroundCall state reset', () {
    test('restarts when native says the service is gone', () async {
      final bc = BackgroundCall(channel: channel, supported: () => true);
      await bc.update(mic: false, cam: false, title: 'Room');
      nativeRunning = false;
      await bc.update(mic: false, cam: false, title: 'Room');
      expect(calls.map((c) => c.method), ['start', 'isRunning', 'start']);
      expect(bc.isRunning, isTrue);
    });

    test('does not restart while native is still running', () async {
      final bc = BackgroundCall(channel: channel, supported: () => true);
      await bc.update(mic: false, cam: false, title: 'Room');
      await bc.update(mic: false, cam: false, title: 'Room');
      expect(calls.map((c) => c.method), ['start', 'isRunning']);
    });
  });

  group('ScreenAwake', () {
    late List<bool> applied;
    setUp(() {
      applied = [];
      ScreenAwake.reset();
      ScreenAwake.apply = (enable) async => applied.add(enable);
    });

    test('stays on until every reason is released', () async {
      await ScreenAwake.hold('playback');
      await ScreenAwake.hold('upload');
      await ScreenAwake.release('playback');
      expect(applied, [true]);
      await ScreenAwake.release('upload');
      expect(applied, [true, false]);
    });

    test('is idempotent and ignores releasing an unheld reason', () async {
      await ScreenAwake.release('upload');
      await ScreenAwake.hold('upload');
      await ScreenAwake.hold('upload');
      await ScreenAwake.release('upload');
      await ScreenAwake.release('upload');
      expect(applied, [true, false]);
      expect(ScreenAwake.holds, isEmpty);
    });

    test('setScreenAwake is the playback hold', () async {
      await setScreenAwake(true);
      expect(ScreenAwake.holds, {'playback'});
      await ScreenAwake.hold('upload');
      await setScreenAwake(false);
      expect(applied, [true]);
      expect(ScreenAwake.holds, {'upload'});
    });

    test('a platform failure is swallowed', () async {
      ScreenAwake.apply = (_) async => throw PlatformException(code: 'nope');
      await ScreenAwake.hold('playback');
      expect(ScreenAwake.holds, {'playback'});
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
