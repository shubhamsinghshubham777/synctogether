import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:synctogether/ui/splash_screen.dart';

final _testMedia = Media('file:///dummy.wav');

class _FakePlayer implements Player {
  final playingController = StreamController<bool>.broadcast();
  final durationController = StreamController<Duration>.broadcast();
  final positionController = StreamController<Duration>.broadcast();

  bool isDisposed = false;
  bool playCalled = false;
  double volume = 0;
  Playable? openedMedia;

  @override
  PlayerState state = const PlayerState();

  @override
  late final PlayerStream stream = PlayerStream(
    const Stream.empty(),
    playingController.stream,
    const Stream.empty(),
    positionController.stream,
    durationController.stream,
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
  );

  @override
  Future<void> setVolume(double vol) async {
    volume = vol;
  }

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    openedMedia = playable;
  }

  @override
  Future<void> play() async {
    playCalled = true;
  }

  @override
  Future<void> dispose({bool synchronized = true}) async {
    isDisposed = true;
    await playingController.close();
    await durationController.close();
    await positionController.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PTSplash synchronization & timeout', () {
    testWidgets('does not start visual animation until audio playback actively begins', (
      tester,
    ) async {
      final fakePlayer = _FakePlayer();

      await tester.pumpWidget(
        MaterialApp(
          home: PTSplash(
            playerFactory: () => fakePlayer,
            mediaOverride: _testMedia,
            child: const Text('App Content', textDirection: TextDirection.ltr),
          ),
        ),
      );

      // Initial pump: player open called, but duration not yet emitted.
      await tester.pump(const Duration(milliseconds: 100));
      expect(fakePlayer.openedMedia, isNotNull);
      expect(fakePlayer.playCalled, isFalse);
      // App content is not yet visible.
      expect(find.text('App Content'), findsNothing);

      // Elapse time without duration: animation still does not start.
      await tester.pump(const Duration(milliseconds: 400));
      expect(fakePlayer.playCalled, isFalse);
      expect(find.text('App Content'), findsNothing);

      // Now media demuxes: emit duration.
      fakePlayer.state = fakePlayer.state.copyWith(duration: const Duration(seconds: 1));
      fakePlayer.durationController.add(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 50));

      // Play should have been triggered, but playing stream not yet confirmed.
      expect(fakePlayer.playCalled, isTrue);

      // Still waiting for playing confirmation.
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('App Content'), findsNothing);

      // Audio engine confirms active playback.
      fakePlayer.state = fakePlayer.state.copyWith(playing: true);
      fakePlayer.playingController.add(true);
      await tester.pump(const Duration(milliseconds: 50));

      // Motion begins from t=0. At t=950ms prewarm begins mounting the child.
      await tester.pump(const Duration(milliseconds: 1000));
      expect(find.text('App Content'), findsOneWidget);

      // Pump through the remaining splash exit (total 1800ms).
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.text('App Content'), findsOneWidget);
    });

    testWidgets('falls back to silent animation when audio preloading times out (> 3000 ms)', (
      tester,
    ) async {
      final fakePlayer = _FakePlayer();

      await tester.pumpWidget(
        MaterialApp(
          home: PTSplash(
            playerFactory: () => fakePlayer,
            mediaOverride: _testMedia,
            child: const Text('App Content', textDirection: TextDirection.ltr),
          ),
        ),
      );

      // Pump 1 second: still waiting.
      await tester.pump(const Duration(seconds: 1));
      expect(fakePlayer.playCalled, isFalse);
      expect(fakePlayer.isDisposed, isFalse);
      expect(find.text('App Content'), findsNothing);

      // Pump 1.5 more seconds (total 2.5s): still within 3-second budget.
      await tester.pump(const Duration(milliseconds: 1500));
      expect(fakePlayer.isDisposed, isFalse);
      expect(find.text('App Content'), findsNothing);

      // Advance past the 3000ms audio budget.
      await tester.pump(const Duration(milliseconds: 600));

      // Timed out player must be disposed to guarantee no stray audio plays.
      expect(fakePlayer.isDisposed, isTrue);

      // Animation starts silently and completes.
      await tester.pump(const Duration(milliseconds: 1000));
      expect(find.text('App Content'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 900));
      expect(find.text('App Content'), findsOneWidget);
    });

    testWidgets('falls back to silent animation immediately if player initialization throws', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PTSplash(
            playerFactory: () => throw StateError('No audio output device'),
            mediaOverride: _testMedia,
            child: const Text('App Content', textDirection: TextDirection.ltr),
          ),
        ),
      );

      // Animation starts silently right away.
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNotNull);
      expect(find.text('App Content'), findsNothing);

      // Prewarm builds the child around 950ms.
      await tester.pump(const Duration(milliseconds: 1000));
      expect(find.text('App Content'), findsOneWidget);

      // Splash completes at 1800ms.
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('App Content'), findsOneWidget);
    });

    testWidgets('handles reduced motion mode once audio confirms playing', (tester) async {
      final fakePlayer = _FakePlayer();

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            home: PTSplash(
              playerFactory: () => fakePlayer,
              mediaOverride: _testMedia,
              child: const Text('App Content', textDirection: TextDirection.ltr),
            ),
          ),
        ),
      );

      // Confirm audio ready & playing.
      fakePlayer.state = fakePlayer.state.copyWith(duration: const Duration(seconds: 1));
      fakePlayer.durationController.add(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 50));

      fakePlayer.state = fakePlayer.state.copyWith(playing: true);
      fakePlayer.playingController.add(true);
      await tester.pump();

      // Under reduced motion, it waits _kImpact (300ms) then forwards.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.text('App Content'), findsOneWidget);
    });

    testWidgets('disposes player cleanly if unmounted while waiting for audio', (tester) async {
      final fakePlayer = _FakePlayer();

      await tester.pumpWidget(
        MaterialApp(
          home: PTSplash(
            playerFactory: () => fakePlayer,
            mediaOverride: _testMedia,
            child: const Text('App Content', textDirection: TextDirection.ltr),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));
      expect(fakePlayer.isDisposed, isFalse);

      // Unmount PTSplash by replacing root widget.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump();

      // Player must be disposed cleanly.
      expect(fakePlayer.isDisposed, isTrue);
    });
  });
}
