import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/env.dart';
import 'package:synctogether/pairing/pair_links.dart';
import 'package:synctogether/pairing/push_service.dart';

class FakeBridge implements PushBridge {
  FakeBridge({this.initial = PushPermission.unknown, this.onRequest = PushPermission.granted});

  PushPermission initial;
  PushPermission onRequest;
  PushToken? current = const PushToken(platform: 'ios', token: 'tok-1', environment: 'sandbox');
  String? launch;
  Map<String, String>? configured;
  bool configuredCalled = false;
  int requests = 0;
  final tokens = StreamController<PushToken>.broadcast();
  final tapsController = StreamController<String?>.broadcast();

  @override
  Future<void> configure(Map<String, String>? firebase) async {
    configuredCalled = true;
    configured = firebase;
  }

  @override
  Future<PushPermission> permission() async => initial;

  @override
  Future<PushPermission> request() async {
    requests++;
    initial = onRequest;
    return onRequest;
  }

  @override
  Future<PushToken?> token() async => current;

  @override
  Stream<PushToken> get tokenChanges => tokens.stream;

  @override
  Stream<String?> get taps => tapsController.stream;

  @override
  Future<String?> launchRoute() async => launch;

  @override
  Future<void> openSettings() async {}
}

void main() {
  late FakeBridge bridge;
  late List<PushToken> registered;
  late List<String> unregistered;
  late PushService service;

  setUp(() {
    bridge = FakeBridge();
    registered = [];
    unregistered = [];
    service = PushService(
      bridge: bridge,
      register: (t) async => registered.add(t),
      unregister: (t) async => unregistered.add(t),
    );
  });

  tearDown(() {
    Env.resetOverridesForTesting();
    service.dispose();
  });

  test('starting never prompts and never registers a device that has not agreed', () async {
    await service.start();
    expect(bridge.requests, 0, reason: 'the OS prompt is only for a person who just asked');
    expect(registered, isEmpty);
    expect(service.enabled, isFalse);
    expect(service.supported, isTrue);
  });

  test('an already-permitted device registers on start, without asking', () async {
    bridge.initial = PushPermission.granted;
    await service.start();
    expect(bridge.requests, 0);
    expect(registered.single.token, 'tok-1');
    expect(registered.single.environment, 'sandbox');
  });

  test('turning something on asks once, then registers', () async {
    await service.start();
    final result = await service.enable();
    expect(result, PushPermission.granted);
    expect(bridge.requests, 1);
    expect(registered.single.token, 'tok-1');
    expect(service.enabled, isTrue);
  });

  test('a "no" is reported, nothing is registered, and the app carries on', () async {
    bridge.onRequest = PushPermission.denied;
    final result = await service.enable();
    expect(result, PushPermission.denied);
    expect(registered, isEmpty);
    expect(service.enabled, isFalse);
  });

  test('a platform with no push says so and is never asked', () async {
    bridge.initial = PushPermission.unsupported;
    final result = await service.enable();
    expect(result, PushPermission.unsupported);
    expect(bridge.requests, 0);
    expect(service.supported, isFalse);
  });

  test('a refreshed token is sent, and the same token is not sent twice', () async {
    bridge.initial = PushPermission.granted;
    await service.start();
    bridge.tokens.add(const PushToken(platform: 'ios', token: 'tok-2'));
    bridge.tokens.add(const PushToken(platform: 'ios', token: 'tok-2'));
    await Future<void>.delayed(Duration.zero);
    expect(registered.map((t) => t.token), ['tok-1', 'tok-2']);
  });

  test('signing out unregisters this device once, and only if it was registered', () async {
    await service.forgetDevice();
    expect(unregistered, isEmpty);
    bridge.initial = PushPermission.granted;
    await service.start();
    await service.forgetDevice();
    await service.forgetDevice();
    expect(unregistered, ['tok-1']);
  });

  test('a failing registration does not stop the service or mark the token sent', () async {
    var calls = 0;
    final flaky = PushService(
      bridge: bridge..initial = PushPermission.granted,
      register: (t) async {
        calls++;
        if (calls == 1) throw Exception('network');
        registered.add(t);
      },
      unregister: (_) async {},
    );
    addTearDown(flaky.dispose);
    await flaky.start();
    expect(registered, isEmpty);
    bridge.tokens.add(bridge.current!);
    await Future<void>.delayed(Duration.zero);
    expect(registered.single.token, 'tok-1', reason: 'the retry is not blocked by the failure');
  });

  test('Android is handed the Firebase options the build was configured with', () async {
    Env.overrideFirebaseOptions = {'apiKey': 'k', 'appId': 'a', 'projectId': 'p', 'senderId': 's'};
    await service.start();
    expect(bridge.configured?['projectId'], 'p');
  });

  test(
    'with no Firebase defines there are no options, so a fork never reaches our project',
    () async {
      expect(Env.firebaseOptions, isNull, reason: 'nothing is baked in');
      await service.start();
      expect(bridge.configuredCalled, isTrue);
      expect(bridge.configured, isNull);
    },
  );

  test('taps are translated, and an unknown route still arrives as a null target', () async {
    await service.start();
    final seen = <PushTarget?>[];
    service.taps.listen(seen.add);
    bridge.tapsController.add('our-room');
    bridge.tapsController.add('retired-route');
    await Future<void>.delayed(Duration.zero);
    expect(seen[0], isA<OpenOurRoom>());
    expect(seen[1], isNull);
  });

  test('the launching notification is a target, once, and a missing one is null', () async {
    expect(await service.takeLaunchTarget(), isNull);
    bridge.launch = 'date-night';
    expect(await service.takeLaunchTarget(), isA<OpenPath>());
  });
}
