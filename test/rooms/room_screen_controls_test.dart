import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/av/livekit_service.dart';
import 'package:synctogether/mock/mock_dependencies.dart';
import 'package:synctogether/profile/entitlement_service.dart';
import 'package:synctogether/profile/profile_service.dart';
import 'package:synctogether/rooms/room_dependencies.dart';
import 'package:synctogether/rooms/room_models.dart';
import 'package:synctogether/rooms/room_screen.dart';
import 'package:synctogether/rooms/room_service.dart';
import 'package:synctogether/rooms/widgets/room_chat_panel.dart';
import 'package:synctogether/rooms/widgets/room_control_bar.dart';
import 'package:synctogether/sync/sync_service.dart';
import 'package:synctogether/ui/cinema_marquee_bar.dart';
import 'package:synctogether/ui/pt_motion.dart';

import '../layout/layout_support.dart';
import '../support/screen_matrix.dart';
import '../sync/fakes.dart';

const _file = 'Cosmic_Voyage_Directors_Cut_2160p_HDR10_Atmos.mkv';
const _kLocalMediaKey = 'pt.local_media_by_room';

class _FakePlayer implements Player {
  final playing = StreamController<bool>.broadcast();
  final position = StreamController<Duration>.broadcast();
  final duration = StreamController<Duration>.broadcast();

  @override
  PlayerState state = const PlayerState();

  @override
  late final PlayerStream stream = PlayerStream(
    const Stream.empty(),
    playing.stream,
    const Stream.empty(),
    position.stream,
    duration.stream,
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
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class _Rooms extends MockRoomService {
  _Rooms(this.room);
  final Room room;

  @override
  Future<Room?> fetchRoom(String roomId) async => room;

  @override
  Future<RoomMemberCosmetics> fetchMemberTiers(String roomId) async =>
      const RoomMemberCosmetics(tiers: {}, frames: {});
}

class _Harness {
  final player = _FakePlayer();
  final backend = FakeSyncBackend();
}

Room _room() => Room(
  id: 'room-1',
  code: 'X7K9P2',
  name: 'Cosmic Voyage Screening',
  createdBy: 'user-alex',
  createdAt: DateTime.now().subtract(const Duration(minutes: 30)),
  durationMinutes: 120,
  expiresAt: DateTime.now().add(const Duration(minutes: 90)),
  maxMembers: 8,
  mediaKind: .local,
  mediaName: _file,
  mediaDuration: const Duration(hours: 2, minutes: 49, seconds: 3),
  mediaUpdatedAt: DateTime.now().subtract(const Duration(minutes: 20)),
  mediaUploadState: 'none',
  avLevel: .video,
);

Future<_Harness> _pumpRoom(
  WidgetTester tester, {
  bool playing = true,
  bool chatOpen = true,
  bool fullscreen = false,
  Size size = const Size(1280, 800),
}) async {
  final h = _Harness();
  final r = _room();
  final dir = Directory('${Directory.systemTemp.path}/room_controls_test')
    ..createSync(recursive: true);
  final copy = File('${dir.path}/$_file')..writeAsStringSync('');
  SharedPreferences.setMockInitialValues({
    _kLocalMediaKey: jsonEncode({
      'room-1': {
        'name': _file,
        'path': copy.path,
        'touched_at': DateTime.now().millisecondsSinceEpoch,
      },
    }),
  });
  ProfileService.instance = MockProfileService();
  EntitlementService.instance = MockEntitlementService();
  RoomService.instance = _Rooms(r);
  mockMembersList
    ..clear()
    ..addAll([
      RoomMember(
        roomId: 'room-1',
        userId: 'user-alex',
        role: 'host',
        joinedAt: DateTime.now().subtract(const Duration(minutes: 60)),
        profile: mockCurrentProfile,
      ),
    ]);
  h.backend
    ..chatHistory = []
    ..roomRow = r
    ..membership = MembershipRow(
      role: 'host',
      joinedAt: DateTime.now().subtract(const Duration(minutes: 60)),
    );
  SyncService.defaultBackendOverride = h.backend;
  LiveKitService.isConfiguredOverride = false;
  LiveKitService.isMockMode = false;

  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('window_manager'),
    (call) async => call.method == 'isFullScreen' ? fullscreen : null,
  );
  addTearDown(() {
    SyncService.defaultBackendOverride = null;
    LiveKitService.isConfiguredOverride = null;
    LiveKitService.isMockMode = false;
  });

  final desktopCase = ScreenCase('desktop-theater', size, .macOS);
  await pumpAtSize(
    tester,
    RoomScreen(
      roomId: 'room-1',
      player: h.player,
      initialChatOpen: chatOpen,
      dependencies: RoomDependencies(videoView: (_, _) => const ColoredBox(color: Colors.black)),
    ),
    desktopCase,
    textScale: 1.0,
  );

  final channel = h.backend.channelInUse;
  channel.emitStatus(.subscribed);
  channel.syncPresence([
    {
      'user_id': 'user-alex',
      'display_name': 'Alex Rivers',
      'role': 'host',
      'joined_at': DateTime.now().subtract(const Duration(minutes: 60)).toIso8601String(),
      'ready_status': 'ready',
      'loaded_file_name': _file,
    },
  ]);
  await tester.pump();
  h.player.state = h.player.state.copyWith(duration: r.mediaDuration);
  h.player.duration.add(r.mediaDuration!);
  h.player.position.add(const Duration(minutes: 42, seconds: 7));
  if (playing) h.player.playing.add(true);
  await tester.pump(const Duration(milliseconds: 500));
  return h;
}

Future<void> _finish(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 2));
  await finishCase(tester);
  await tester.pump(const Duration(seconds: 11));
}

void main() {
  testWidgets('top bar spans full window width above video and docked chat in theater mode', (
    tester,
  ) async {
    try {
      await _pumpRoom(tester, playing: true, chatOpen: true);

      // Verify CinemaMarqueeBar exists and spans the full 1280 px width
      final marqueeFinder = find.byType(CinemaMarqueeBar);
      expect(marqueeFinder, findsOneWidget);
      final marqueeSize = tester.getSize(marqueeFinder);
      expect(marqueeSize.width, 1280.0);

      // Verify chat panel top begins below the top bar (>= 52px)
      final chatFinder = find.byType(RoomChatPanel);
      if (chatFinder.evaluate().isNotEmpty) {
        final chatRect = tester.getRect(chatFinder.first);
        expect(chatRect.top, greaterThanOrEqualTo(52.0));
      }

      await _finish(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  // The theatre is docked: a bar hides by collapsing its slot (the picture
  // grows into it), which is an AnimatedAlign's heightFactor going to 0.
  double slotOf(WidgetTester tester, Type bar) {
    final align = find.ancestor(of: find.byType(bar), matching: find.byType(AnimatedAlign));
    return tester.widget<AnimatedAlign>(align.first).heightFactor!;
  }

  testWidgets('H collapses the control bar but never the header in a window', (tester) async {
    try {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await _pumpRoom(tester, playing: true);
      expect(slotOf(tester, CinemaMarqueeBar), 1.0);
      expect(slotOf(tester, RoomControlBar), 1.0);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
      await tester.pump(const Duration(milliseconds: 300));
      // The traffic lights live in the header, so it stays.
      expect(slotOf(tester, CinemaMarqueeBar), 1.0);
      expect(slotOf(tester, RoomControlBar), 0.0);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
      await tester.pump(const Duration(milliseconds: 300));
      expect(slotOf(tester, RoomControlBar), 1.0);

      await _finish(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('H collapses header and control bar together in fullscreen', (tester) async {
    try {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await _pumpRoom(tester, playing: true, fullscreen: true);
      expect(slotOf(tester, CinemaMarqueeBar), 1.0, reason: 'header shows in fullscreen');

      await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
      await tester.pump(const Duration(milliseconds: 300));
      expect(slotOf(tester, CinemaMarqueeBar), 0.0);
      expect(slotOf(tester, RoomControlBar), 0.0);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
      await tester.pump(const Duration(milliseconds: 300));
      expect(slotOf(tester, CinemaMarqueeBar), 1.0);
      expect(slotOf(tester, RoomControlBar), 1.0);

      await _finish(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('the scrub preview chip is not clipped by the control bar', (tester) async {
    try {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await _pumpRoom(tester, playing: true);

      ClipRect barClip() => tester.widget<ClipRect>(
        find.ancestor(of: find.byType(RoomControlBar), matching: find.byType(ClipRect)).first,
      );
      // Open and settled: free to draw outside its slot.
      expect(barClip().clipBehavior, Clip.none);

      // Hover the seek bar: the chip rises above the bar, into the picture.
      final bar = tester.getRect(find.byType(RoomControlBar));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset(bar.center.dx, bar.top + 12));
      await mouse.moveTo(Offset(bar.center.dx, bar.top + 14));
      await tester.pump(const Duration(milliseconds: 300));
      final chip = find.descendant(
        of: find.byType(RoomControlBar),
        matching: find.byType(PTEntrance),
      );
      expect(chip, findsOneWidget);
      expect(tester.getRect(chip).bottom, lessThanOrEqualTo(bar.top + 14));
      expect(tester.getRect(chip).top, lessThan(bar.top), reason: 'it rises above the bar');
      await mouse.removePointer();

      // While the bar is sliding or hidden it clips, so it cannot draw over the picture.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
      await tester.pump(const Duration(milliseconds: 60));
      expect(barClip().clipBehavior, Clip.hardEdge);

      await _finish(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('clicking the picture toggles the control bar', (tester) async {
    try {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await _pumpRoom(tester, playing: true);

      await tester.tapAt(const Offset(400, 400));
      await tester.pump(const Duration(milliseconds: 300));
      expect(slotOf(tester, RoomControlBar), 0.0);

      await tester.tapAt(const Offset(400, 400));
      await tester.pump(const Duration(milliseconds: 300));
      expect(slotOf(tester, RoomControlBar), 1.0);

      await _finish(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('idle time does NOT automatically hide controls (manual only)', (tester) async {
    try {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await _pumpRoom(tester, playing: true, fullscreen: true);
      await tester.pump(const Duration(seconds: 5));
      expect(slotOf(tester, CinemaMarqueeBar), 1.0);
      expect(slotOf(tester, RoomControlBar), 1.0);
      await _finish(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  // Chat sits beside the header and the control bar, never under them.
  for (final fullscreen in [false, true]) {
    for (final size in const [Size(1280, 800), Size(1000, 700), Size(900, 600)]) {
      testWidgets('chat is not overlapped by header or controls (${size.width.toInt()}x'
          '${size.height.toInt()}${fullscreen ? ', fullscreen' : ''})', (tester) async {
        try {
          debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          await _pumpRoom(
            tester,
            playing: true,
            chatOpen: true,
            fullscreen: fullscreen,
            size: size,
          );

          final header = tester.getRect(find.byType(CinemaMarqueeBar));
          final controls = tester.getRect(find.byType(RoomControlBar));
          final chat = tester.getRect(find.byType(RoomChatPanel));
          expect(header.width, size.width, reason: 'header spans the window');
          expect(chat.top, greaterThanOrEqualTo(header.bottom - 0.5));
          expect(controls.right, lessThanOrEqualTo(chat.left + 0.5));
          expect(chat.bottom, lessThanOrEqualTo(size.height + 0.5));
          expect(chat.width, greaterThanOrEqualTo(280));
          expect(controls.width, greaterThan(500), reason: 'transport keeps room to breathe');

          await _finish(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }

  testWidgets('the header carries the back button and clears the traffic lights', (tester) async {
    try {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await _pumpRoom(tester, playing: true);
      final back = find.descendant(
        of: find.byType(CinemaMarqueeBar),
        matching: find.byTooltip('Back to the lobby'),
      );
      expect(back, findsOneWidget);
      expect(
        tester.getRect(back).left,
        greaterThanOrEqualTo(CinemaMarqueeBar.macOsTrafficLightInset),
      );
      await _finish(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('chat toggles from the header in fullscreen and unmounts at rest', (tester) async {
    try {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await _pumpRoom(tester, playing: true, chatOpen: false, fullscreen: true);
      expect(find.byType(RoomChatPanel), findsNothing);

      await tester.tap(find.byTooltip('Party chat (C)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(RoomChatPanel), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(CinemaMarqueeBar),
          matching: find.byTooltip('Close chat (C)'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 125));
      expect(find.byType(RoomChatPanel), findsOneWidget, reason: 'still sliding shut');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(RoomChatPanel), findsNothing);

      await _finish(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('every desktop size gets the docked theatre, down to the minimum window', (
    tester,
  ) async {
    try {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await _pumpRoom(tester, playing: true, size: const Size(900, 600));
      expect(find.byType(CinemaMarqueeBar), findsOneWidget);
      expect(find.byType(RoomControlBar), findsOneWidget);
      await _finish(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  group('layout transitions with chat open', () {
    Future<void> windowEvent(WidgetTester tester, String name) async {
      const codec = StandardMethodCodec();
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'window_manager',
        codec.encodeMethodCall(MethodCall('onEvent', {'eventName': name})),
        (_) {},
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> resize(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('entering and leaving fullscreen keeps chat and header intact', (tester) async {
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        await _pumpRoom(tester, playing: true, chatOpen: true);
        expect(tester.takeException(), isNull);

        await windowEvent(tester, 'enter-full-screen');
        expect(tester.takeException(), isNull, reason: 'entering fullscreen');
        expect(find.byType(RoomChatPanel), findsOneWidget);
        expect(find.text('Cosmic Voyage Screening'), findsOneWidget);

        await windowEvent(tester, 'leave-full-screen');
        expect(tester.takeException(), isNull, reason: 'leaving fullscreen');
        expect(find.byType(RoomChatPanel), findsOneWidget);

        await _finish(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a half-typed chat message survives a layout change', (tester) async {
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        await _pumpRoom(tester, playing: true, chatOpen: true);

        final field = find.descendant(
          of: find.byType(RoomChatPanel),
          matching: find.byType(EditableText),
        );
        await tester.enterText(field, 'save me a seat');

        await resize(tester, const Size(1000, 700));
        await windowEvent(tester, 'enter-full-screen');
        expect(tester.takeException(), isNull);

        final survivor = tester.widget<EditableText>(
          find.descendant(of: find.byType(RoomChatPanel), matching: find.byType(EditableText)),
        );
        expect(survivor.controller.text, 'save me a seat');

        await _finish(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('resizing across the theatre breakpoint keeps chat alive', (tester) async {
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        await _pumpRoom(tester, playing: true, chatOpen: true);

        await resize(tester, const Size(1000, 700));
        expect(tester.takeException(), isNull, reason: 'theatre -> roomy');
        expect(find.byType(RoomChatPanel), findsOneWidget);

        await resize(tester, const Size(1280, 800));
        expect(tester.takeException(), isNull, reason: 'roomy -> theatre');
        expect(find.byType(RoomChatPanel), findsOneWidget);

        await windowEvent(tester, 'enter-full-screen');
        await resize(tester, const Size(1000, 700));
        expect(tester.takeException(), isNull, reason: 'fullscreen, then narrow');
        expect(find.byType(RoomChatPanel), findsOneWidget);

        await _finish(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
