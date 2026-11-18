import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/player/pip.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('when leaving the app shrinks the room', () {
    const on = PipSupport(supported: true, enabled: true);

    test('only with support, the switch on, a film and a live room', () {
      expect(pipArmed(support: on, hasFilm: true, inRoom: true), isTrue);
      expect(
        pipArmed(support: PipSupport.none, hasFilm: true, inRoom: true),
        isFalse,
        reason: 'the device does not offer it',
      );
      expect(
        pipArmed(support: const PipSupport(supported: true), hasFilm: true, inRoom: true),
        isFalse,
        reason: 'switched off in system settings',
      );
      expect(pipArmed(support: on, hasFilm: false, inRoom: true), isFalse, reason: 'empty window');
      expect(pipArmed(support: on, hasFilm: true, inRoom: false), isFalse, reason: 'left the room');
    });
  });

  group('what the small window says', () {
    test('a picture that is playing says nothing', () {
      expect(pipNotice(connected: true, playing: true, evicted: null), isNull);
    });

    test('paused names who paused it when known', () {
      expect(pipNotice(connected: true, playing: false, evicted: null)?.title, 'Paused');
      expect(
        pipNotice(connected: true, playing: false, evicted: null, pausedBy: 'Priya')?.subtitle,
        'Priya paused the film',
      );
    });

    test('a lost connection is two words and a promise', () {
      final n = pipNotice(connected: false, playing: true, evicted: null)!;
      expect(n.title, 'Reconnecting…');
      expect(n.subtitle, 'The picture will catch up');
    });

    test('a room that is gone, or a removal, outranks everything', () {
      expect(
        pipNotice(connected: false, playing: false, evicted: 'room_ended')?.title,
        'The room ended',
      );
      expect(
        pipNotice(connected: true, playing: true, evicted: 'kicked')?.title,
        'You were removed',
      );
      expect(
        pipNotice(connected: true, playing: true, evicted: 'banned')?.title,
        'You were removed',
      );
    });
  });

  group('the service', () {
    const channel = MethodChannel('app.synctogether/pip');
    final calls = <MethodCall>[];

    PictureInPicture make({bool platform = true}) {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async {
          calls.add(call);
          return switch (call.method) {
            'support' => {'supported': true, 'enabled': false},
            'enter' => true,
            _ => null,
          };
        },
      );
      return PictureInPicture(channel: channel, platformOk: () => platform);
    }

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    });

    test('off Android nothing is promised and nothing crosses the channel', () async {
      final pip = make(platform: false);
      expect((await pip.support()).supported, isFalse);
      await pip.configure(armed: true, w: 16, h: 9, playing: true);
      expect(await pip.enter(), isFalse);
      expect(calls, isEmpty);
    });

    test('support says supported but switched off', () async {
      final s = await make().support();
      expect(s.supported, isTrue);
      expect(s.enabled, isFalse);
    });

    test('configure only crosses the channel when something changed', () async {
      final pip = make();
      await pip.configure(armed: true, w: 16, h: 9, playing: false);
      await pip.configure(armed: true, w: 16, h: 9, playing: false);
      await pip.configure(armed: true, w: 16, h: 9, playing: true);
      expect(calls.where((c) => c.method == 'configure'), hasLength(2));
      expect(calls.last.arguments, {'armed': true, 'w': 16, 'h': 9, 'playing': true});
    });

    test('the window coming and going, and its keys, arrive as events', () async {
      final pip = make();
      await pip.support();
      final actions = <PipAction>[];
      pip.actions.listen(actions.add);
      Future<void> event(Map<String, Object?> m) async {
        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
              channel.name,
              const StandardMethodCodec().encodeMethodCall(MethodCall('event', m)),
              (_) {},
            );
      }

      await event({'type': 'mode', 'inPip': true});
      expect(pip.inPip.value, isTrue);
      await event({'type': 'action', 'id': 'playPause'});
      await event({'type': 'action', 'id': 'back'});
      await event({'type': 'action', 'id': 'nonsense'});
      await Future<void>.delayed(Duration.zero);
      expect(actions, [PipAction.playPause, PipAction.back]);
      await event({'type': 'mode', 'inPip': false});
      expect(pip.inPip.value, isFalse);
    });
  });
}
