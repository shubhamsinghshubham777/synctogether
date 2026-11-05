// Pumps the real RoomScreen - every layout builder (desktop, tablet, portrait,
// landscape, folded) - over the screen matrix. Possible because of three
// seams, all defaulted to production: `RoomDependencies.videoView` replaces
// media_kit's `Video` (whose controller needs native libmpv), the service
// singletons are swapped the way `installMockDependencies` swaps them, and
// sync runs over `SyncService.defaultBackendOverride`. The Player is a fake
// implementing media_kit's interface, since `MainApp` passes it in anyway.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
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
import 'package:synctogether/rooms/widgets/facecam_rail.dart';
import 'package:synctogether/rooms/widgets/reaction_strip.dart';
import 'package:synctogether/rooms/widgets/room_chat_panel.dart';
import 'package:synctogether/rooms/widgets/room_control_bar.dart';
import 'package:synctogether/sync/sync_service.dart';
import 'package:synctogether/ui/booth_icons.g.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/identity.dart';
import 'package:synctogether/ui/inputs.dart';

import '../support/screen_matrix.dart';
import '../sync/fakes.dart';
import 'layout_support.dart';

const _file = 'Cosmic_Voyage_Directors_Cut_2160p_HDR10_Atmos.mkv';
const _kLocalMediaKey = 'pt.local_media_by_room'; // LocalMediaStore's key
const _longName = 'Maximiliana Featherstonehaugh-Wolfeschlegel';

/// media_kit's Player surface, driven by hand. Every other method is a
/// `Future<void>` command (open, play, pause, seek, stop...) and no-ops.
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

/// Counts mounts, so a layout-class change that remounts the video shows up.
class _VideoProbe extends StatefulWidget {
  const _VideoProbe();
  static int mounts = 0;

  @override
  State<_VideoProbe> createState() => _VideoProbeState();
}

class _VideoProbeState extends State<_VideoProbe> {
  @override
  void initState() {
    super.initState();
    _VideoProbe.mounts++;
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.black);
}

Room _room({DateTime? expiresAt, String uploadState = 'none'}) => Room(
  id: 'room-1',
  code: 'X7K9P2',
  name: 'Cosmic Voyage Screening With An Unreasonably Long Room Name',
  createdBy: 'user-alex',
  createdAt: DateTime.now().subtract(const Duration(minutes: 30)),
  durationMinutes: 120,
  expiresAt: expiresAt ?? DateTime.now().add(const Duration(minutes: 90)),
  maxMembers: 8,
  mediaKind: .local,
  mediaName: _file,
  mediaDuration: const Duration(hours: 2, minutes: 49, seconds: 3),
  mediaUpdatedAt: DateTime.now().subtract(const Duration(minutes: 20)),
  mediaUploadState: uploadState,
  avLevel: .video,
);

List<RoomMember> _roomMembers(int n) => [
  for (var i = 0; i < n; i++)
    RoomMember(
      roomId: 'room-1',
      userId: i == 0 ? 'user-alex' : 'u$i',
      role: i == 0 ? 'host' : 'member',
      joinedAt: DateTime.now().subtract(Duration(minutes: 60 - i)),
      profile: mockCurrentProfile,
    ),
];

List<Map<String, dynamic>> _presence(int n, {required bool allReady}) => [
  for (var i = 0; i < n; i++)
    {
      'user_id': i == 0 ? 'user-alex' : 'u$i',
      'display_name': i == 0 ? 'Alex Rivers' : (i.isOdd ? _longName : 'Sam $i'),
      'role': i == 0 ? 'host' : 'member',
      'joined_at': DateTime.now().subtract(Duration(minutes: 60 - i)).toIso8601String(),
      'ready_status': allReady || i % 3 == 0 ? 'ready' : (i.isOdd ? 'loading' : 'selecting'),
      'loaded_file_name': allReady || i % 3 == 0 ? _file : (i % 3 == 2 ? 'Other_File.mp4' : null),
    },
];

class _Harness {
  final player = _FakePlayer();
  final backend = FakeSyncBackend();
}

Future<_Harness> _pumpRoom(
  WidgetTester tester,
  ScreenCase c,
  double scale, {
  Room? room,
  int members = 4,
  bool allReady = true,
  bool playing = false,
  bool chatOpen = false,
  bool av = false,
  List<ChatMessage> chat = const [],
}) async {
  final h = _Harness();
  _lastPlayer = h.player;
  final r = room ?? _room();
  // A remembered copy of the room's file, so the room reopens it on entry and
  // we are not the one holding the gate.
  final dir = Directory('${Directory.systemTemp.path}/room_matrix')..createSync(recursive: true);
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
  final rooms = _Rooms(r);
  RoomService.instance = rooms;
  mockMembersList
    ..clear()
    ..addAll(_roomMembers(members));
  h.backend
    ..chatHistory = chat
    ..roomRow = r
    ..membership = MembershipRow(
      role: 'host',
      joinedAt: DateTime.now().subtract(const Duration(minutes: 60)),
    );
  SyncService.defaultBackendOverride = h.backend;
  LiveKitService.isConfiguredOverride = av;
  LiveKitService.isMockMode = av;
  // Phone cases hold the screen awake while playing; answer the pigeon call.
  tester.binding.defaultBinaryMessenger.setMockMessageHandler(
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
    (_) async => const StandardMessageCodec().encodeMessage(<Object?>[null]),
  );
  // Facecam cases enumerate devices through flutter_webrtc, which has no plugin here.
  for (final name in [
    'FlutterWebRTC.Method',
    'FlutterWebRTC.Event',
    'app.synctogether/background_call',
  ]) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      MethodChannel(name),
      (call) async => call.method == 'getSources' ? <String, Object?>{'sources': []} : null,
    );
  }
  // Desktop cases reach window_manager, which has no plugin under test.
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('window_manager'),
    (call) async => call.method == 'isFullScreen' ? false : null,
  );
  addTearDown(() {
    SyncService.defaultBackendOverride = null;
    LiveKitService.isConfiguredOverride = null;
    LiveKitService.isMockMode = false;
  });

  await pumpAtSize(
    tester,
    RoomScreen(
      roomId: 'room-1',
      player: h.player,
      initialChatOpen: chatOpen,
      dependencies: RoomDependencies(videoView: (_, _) => const _VideoProbe()),
    ),
    c,
    textScale: scale,
  );
  final channel = h.backend.channelInUse;
  channel.emitStatus(.subscribed);
  channel.syncPresence(_presence(members, allReady: allReady));
  await tester.pump();
  if (allReady) {
    h.player.state = h.player.state.copyWith(duration: r.mediaDuration);
    h.player.duration.add(r.mediaDuration!);
    h.player.position.add(const Duration(minutes: 42, seconds: 7));
  }
  if (playing) h.player.playing.add(true);
  await tester.pump(const Duration(milliseconds: 500));
  return h;
}

/// [finishCase], then outlasts the room's 10 s "announce the file without a
/// duration" fallback, a `timeout` that is not tied to the widget's life.
Future<void> _finish(WidgetTester tester) async {
  // Let entrances (roster stagger, banner slides) land before the capture, so
  // the screenshot is the settled screen rather than a mid-animation frame.
  await tester.pump(const Duration(seconds: 2));
  await finishCase(tester);
  await tester.pump(const Duration(seconds: 11));
}

void main() {
  setUp(() => _VideoProbe.mounts = 0);

  screenMatrix('room local idle', (tester, c, s) async {
    await _pumpRoom(tester, c, s);
    await _finish(tester);
  });

  screenMatrix('room playing, chat open', (tester, c, s) async {
    await _pumpRoom(tester, c, s, playing: true, chatOpen: true, chat: mockChatMessagesList);
    await _finish(tester);
  });

  screenMatrix('room chat focused with keyboard', (tester, c, s) async {
    await _pumpRoom(tester, c, s, chatOpen: true);
    final field = find.byType(EditableText);
    if (field.evaluate().isNotEmpty) {
      await tester.showKeyboard(field.first);
      await tester.pump(const Duration(milliseconds: 400));
    }
    await _finish(tester);
  }, cases: kScreenMatrix.where((c) => c.keyboard > 0).toList());

  screenMatrix(
    'room facecams, six in the room',
    (tester, c, s) async {
      await _pumpRoom(tester, c, s, av: true, members: 6);
      await _finish(tester);
    },
    cases: kScreenMatrix.where((c) => c.name.startsWith('phone')).toList(),
  );

  screenMatrix('room readiness overlay', (tester, c, s) async {
    await _pumpRoom(tester, c, s, members: 7, allReady: false);
    // The roster stagger's delays are real-zone timers here, so give the real
    // clock a moment or every row after the first captures invisible.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pump(const Duration(seconds: 1));
    await _finish(tester);
  });

  screenMatrix('room stacked banners', (tester, c, s) async {
    final h = await _pumpRoom(
      tester,
      c,
      s,
      room: _room(expiresAt: DateTime.now().add(const Duration(minutes: 3)), uploadState: 'failed'),
    );
    // Drop the connection: the reconnecting banner joins T-5 + upload failed.
    h.backend.channelInUse.emitStatus(.channelError);
    await tester.pump(const Duration(milliseconds: 500));
    await _finish(tester);
  });

  testWidgets('desktop video tap has no double-tap recognizer', (tester) async {
    final desktop = kScreenMatrix.firstWhere((c) => c.name == 'desktop');
    try {
      await _pumpRoom(tester, desktop, 1.0);
      final gesture = tester.widget<GestureDetector>(
        find.ancestor(of: find.byType(_VideoProbe), matching: find.byType(GestureDetector)).first,
      );
      expect(gesture.onTap, isNotNull);
      expect(gesture.onDoubleTap, isNull);
      await _finish(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  Finder tiles() => find.descendant(
    of: find.byType(FacecamRail),
    matching: find.byWidgetPredicate((w) => w.runtimeType.toString() == '_FacecamTile'),
  );

  Rect chatPanelRect(WidgetTester tester) => tester.getRect(find.byType(RoomChatPanel).first);

  group('phone defects', () {
    testWidgets('portrait + keyboard keeps play and the reaction bar reachable', (tester) async {
      final c = kScreenMatrix.firstWhere((c) => c.name == 'phone-keyboard');
      try {
        await _pumpRoom(tester, c, 1.0, chatOpen: true);
        final field = find.byType(EditableText);
        if (field.evaluate().isNotEmpty) {
          await tester.showKeyboard(field.first);
          await tester.pump(const Duration(milliseconds: 400));
        }
        final visibleBottom = c.size.height - c.keyboard;
        await _tapReact(tester);
        final play = tester.getRect(find.byType(PTPlayButton));
        expect(play.bottom, lessThanOrEqualTo(visibleBottom), reason: 'play under keyboard');
        // The transport is pinned, never inside a scroll area it could be
        // scrolled out of; the strip opens whole above it.
        expect(
          find.ancestor(of: find.byType(PTPlayButton), matching: find.byType(Scrollable)),
          findsNothing,
        );
        final strip = find.byType(ReactionStrip);
        expect(strip, findsOneWidget);
        final sr = tester.getRect(strip);
        expect(sr.height, greaterThan(20));
        expect(sr.bottom, lessThanOrEqualTo(play.top + 0.5), reason: 'strip overlaps the bar');
        expect(sr.top, greaterThanOrEqualTo(0));
        await _finish(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    for (final name in ['phone-land', 'phone-android-land', 'phone-se-land']) {
      final c = kScreenMatrix.firstWhere((c) => c.name == name);
      testWidgets('$name facecams clear the control bar and keep +N', (tester) async {
        try {
          await _pumpRoom(tester, c, 1.0, av: true, members: 6);
          final bar = tester.getRect(find.byType(RoomControlBar));
          final all = tiles().evaluate().length;
          expect(all, greaterThan(0));
          for (var i = 0; i < all; i++) {
            final r = tester.getRect(tiles().at(i));
            expect(r.overlaps(bar), isFalse, reason: 'tile $i $r under bar $bar');
          }
          final pill = find.text('+${6 - all}');
          expect(pill, findsOneWidget);
          expect(tester.getRect(pill).overlaps(bar), isFalse, reason: '+N under the bar');
          await _finish(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });

      testWidgets('$name hidden controls: +N clears the show-controls chevron', (tester) async {
        try {
          await _pumpRoom(tester, c, 1.0, av: true, members: 6);
          await _playAndHideControls(tester);
          await tester.pump(const Duration(seconds: 1));
          final chevron = tester.getRect(find.byTooltip('Show controls (H)'));
          final all = tiles().evaluate().length;
          for (var i = 0; i < all; i++) {
            expect(tester.getRect(tiles().at(i)).overlaps(chevron), isFalse, reason: 'tile $i');
          }
          final pill = find.text('+${6 - all}');
          expect(pill, findsOneWidget);
          expect(tester.getRect(pill).overlaps(chevron), isFalse, reason: '+N on the chevron');
          await _finish(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });

      testWidgets('$name chat open does not cover the control bar', (tester) async {
        try {
          await _pumpRoom(tester, c, 1.0, chatOpen: true, chat: mockChatMessagesList);
          final bar = tester.getRect(find.byType(RoomControlBar));
          final panel = chatPanelRect(tester);
          expect(panel.overlaps(bar), isFalse, reason: 'chat $panel covers bar $bar');
          await _finish(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  });

  // The docked chat is a floating panel above the control stack, so it has to
  // leave room for that stack - which is taller on touch (44px targets).
  group('landscape tablet and desktop: docked chat', () {
    for (final name in ['ipad-land', 'desktop-min', 'desktop', 'desktop-wide']) {
      final c = kScreenMatrix.firstWhere((c) => c.name == name);
      testWidgets('$name chat open keeps its input clear of the control bar', (tester) async {
        try {
          await _pumpRoom(tester, c, 1.0, chatOpen: true, chat: mockChatMessagesList);
          final bar = tester.getRect(find.byType(RoomControlBar));
          final panel = chatPanelRect(tester);
          expect(panel.overlaps(bar), isFalse, reason: 'chat $panel covers bar $bar');
          final input = tester.getRect(
            find.descendant(
              of: find.byType(RoomChatPanel).first,
              matching: find.byType(EditableText),
            ),
          );
          expect(input.overlaps(bar), isFalse, reason: 'chat input $input under bar $bar');
          await _finish(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  });

  testWidgets('phone -> tablet keeps the same video surface', (tester) async {
    final phone = kScreenMatrix.firstWhere((c) => c.name == 'phone');
    try {
      await _pumpRoom(tester, phone, 1.0);
      final before = tester.state(find.byType(_VideoProbe));
      expect(_VideoProbe.mounts, 1);
      tester.view.physicalSize = const Size(1180, 820);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.state(find.byType(_VideoProbe)), same(before));
      expect(_VideoProbe.mounts, 1);
      await _finish(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  // Board 46's forms, drawn in a real room: which controls a portrait phone's
  // bar still shows inline at each width. Targets stay 44/52 (nothing scales).
  for (final entry in {
    332.0: 'F5',
    360.0: 'F5',
    390.0: 'F4',
    412.0: 'F4',
    436.0: 'F3',
    480.0: 'F3',
  }.entries) {
    testWidgets('portrait bar at ${entry.key} is ${entry.value}, unscaled', (tester) async {
      try {
        await _pumpRoom(
          tester,
          ScreenCase('phone-${entry.key}', Size(entry.key, 800), .iOS),
          1.0,
          av: true,
        );
        final bar = find.byType(RoomControlBar);
        expect(bar, findsOneWidget);
        // Rects are global, so a scaled-down row shows up as smaller targets.
        Rect rectOf(Finder f) => tester.getRect(find.descendant(of: bar, matching: f).first);
        expect(rectOf(find.byType(PTPlayButton)).width, closeTo(52, 0.5));
        Finder inBar(String tooltip) =>
            find.descendant(of: bar, matching: find.byTooltip(tooltip)).hitTestable();
        final more = _barMore();
        expect(more.hitTestable(), findsOneWidget, reason: 'every portrait form has folded');
        expect(tester.getRect(more).width, lessThanOrEqualTo(44.5));
        // Never in the bar once folded; the source group goes first of all.
        expect(find.descendant(of: bar, matching: find.byTooltip('Subtitles')), findsNothing);
        expect(find.descendant(of: bar, matching: find.byTooltip('Back 10 seconds')), findsNothing);
        final mic = inBar('Mic on (D)');
        final react = inBar('React (R)');
        switch (entry.value) {
          case 'F5':
            expect(mic, findsNothing);
            expect(react, findsNothing);
          case 'F4':
            expect(mic, findsOneWidget);
            expect(rectOf(find.byTooltip('Mic on (D)')).width, closeTo(44, 0.5));
            expect(react, findsNothing);
          case 'F3':
            expect(mic, findsOneWidget);
            expect(react, findsNothing);
        }
        // The scrubber and play are never folded.
        expect(find.descendant(of: bar, matching: find.byType(PTSlider)), findsOneWidget);
        await _finish(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  /// The seek bar and play/pause, hittable and inside the visible window.
  void expectTransportReachable(WidgetTester tester, ScreenCase c) {
    final bar = find.byType(RoomControlBar);
    expect(bar, findsOneWidget, reason: '${c.name}: no control bar');
    final play = find.descendant(of: bar, matching: find.byType(PTPlayButton));
    final seek = find.descendant(of: bar, matching: find.byType(PTSlider)).first;
    expect(play.hitTestable(), findsOneWidget, reason: '${c.name}: play/pause not hittable');
    expect(seek.hitTestable(), findsOneWidget, reason: '${c.name}: seek bar not hittable');
    final visible = Rect.fromLTWH(0, 0, c.size.width, c.size.height - c.keyboard);
    for (final f in [play, seek]) {
      final r = tester.getRect(f);
      expect(
        visible.contains(r.topLeft) && visible.contains(r.bottomRight),
        isTrue,
        reason: '${c.name}: $r outside $visible',
      );
    }
  }

  screenMatrix('room transport reachable, chat closed', (tester, c, s) async {
    await _pumpRoom(tester, c, s);
    expectTransportReachable(tester, c);
    await _finish(tester);
  });

  screenMatrix('room transport reachable, chat open', (tester, c, s) async {
    await _pumpRoom(tester, c, s, playing: true, chatOpen: true, chat: mockChatMessagesList);
    // A keyboard-up landscape chat takes the bar's slot until it is dismissed;
    // everywhere else the transport stays.
    final keyboardLandscape = c.keyboard > 0 && c.size.width > c.size.height;
    if (!keyboardLandscape) expectTransportReachable(tester, c);
    await _finish(tester);
  });

  screenMatrix(
    'room transport reachable with facecams and the reaction strip open',
    (tester, c, s) async {
      await _pumpRoom(tester, c, s, av: true, members: 6);
      await _tapReact(tester);
      expectTransportReachable(tester, c);
      await _finish(tester);
    },
    cases: kScreenMatrix.where((c) => c.name.startsWith('phone') && c.keyboard == 0).toList(),
  );

  // Board 46, frames A-E, drawn in the real room: the form the landscape bar
  // takes beside the chat, and the facecam rail beside both. The boards have no
  // system insets, so these two windows have none either.
  group('board 46: landscape forms and the rail', () {
    const wide = ScreenCase('board-844x390', Size(844, 390), .iOS);
    final se = kScreenMatrix.firstWhere((c) => c.name == 'phone-se-land');

    Finder inline(String tooltip) => find
        .descendant(of: find.byType(RoomControlBar), matching: find.byTooltip(tooltip))
        .hitTestable();

    Future<void> settle(WidgetTester tester) => tester.pump(const Duration(seconds: 1));

    List<Rect> tileRects(WidgetTester tester) => [
      for (var i = 0; i < tiles().evaluate().length; i++) tester.getRect(tiles().at(i)),
    ];

    void expectRailClear(WidgetTester tester, {required bool chatOpen}) {
      final bar = tester.getRect(find.byType(RoomControlBar));
      final chat = chatOpen ? chatPanelRect(tester) : null;
      for (final tile in tileRects(tester)) {
        expect(tile.overlaps(bar), isFalse, reason: 'tile $tile under the bar $bar');
        if (chat != null) {
          expect(tile.overlaps(chat), isFalse, reason: 'tile $tile under the chat $chat');
          // Beside the chat: the rail's right edge is the chat width + 12 in.
          expect(tile.right, lessThanOrEqualTo(chat.left - 12 + 0.5), reason: 'rail hugs chat');
        }
      }
      final pill = find.textContaining('+').hitTestable();
      for (var i = 0; i < pill.evaluate().length; i++) {
        final r = tester.getRect(pill.at(i));
        expect(r.overlaps(bar), isFalse, reason: '+N under the bar');
        if (chat != null) expect(r.overlaps(chat), isFalse, reason: '+N under the chat');
      }
    }

    screenMatrix(
      'board 46 A: chat closed -> F1, two tiles and +N',
      (tester, c, s) async {
        await _pumpRoom(tester, wide, 1.0, av: true, members: 6);
        await settle(tester);
        expect(tester.getSize(find.byType(RoomControlBar)).height, 112);
        expect(inline('Switch source'), findsOneWidget);
        expect(inline('Back 10 seconds'), findsOneWidget);
        expect(_barMore(), findsNothing);
        expect(tiles(), findsNWidgets(2));
        for (final r in tileRects(tester)) {
          expect(r.size, const Size(104, 58));
        }
        expect(find.text('+4'), findsOneWidget);
        expectRailClear(tester, chatOpen: false);
        await _finish(tester);
      },
      cases: [wide],
      textScales: [1.0],
    );

    screenMatrix(
      'board 46 B: chat open -> F3, two large tiles left of the chat',
      (tester, c, s) async {
        await _pumpRoom(
          tester,
          wide,
          1.0,
          av: true,
          members: 6,
          chatOpen: true,
          chat: mockChatMessagesList,
        );
        await settle(tester);
        expect(tester.getSize(find.byType(RoomControlBar)).height, 64);
        expect(tester.getSize(find.byType(RoomControlBar)).width, closeTo(442, 1));
        expect(inline('Mic on (D)'), findsOneWidget);
        expect(inline('React (R)'), findsNothing);
        expect(_barMore(), findsOneWidget);
        expect(tiles(), findsNWidgets(2));
        for (final r in tileRects(tester)) {
          expect(r.size, const Size(136, 77));
        }
        expectRailClear(tester, chatOpen: true);
        await _finish(tester);
      },
      cases: [wide],
      textScales: [1.0],
    );

    screenMatrix(
      'board 46 C: chat closed -> F2 by the height rule',
      (tester, c, s) async {
        await _pumpRoom(tester, se, 1.0, av: true, members: 6);
        await settle(tester);
        expect(tester.getSize(find.byType(RoomControlBar)).width, closeTo(555, 1));
        expect(tester.getSize(find.byType(RoomControlBar)).height, 64);
        expect(inline('React (R)'), findsOneWidget);
        expect(inline('Switch source'), findsNothing);
        expect(tiles(), findsNWidgets(2));
        expectRailClear(tester, chatOpen: false);
        await _finish(tester);
      },
      cases: [se],
      textScales: [1.0],
    );

    screenMatrix(
      'board 46 D and E: chat open -> F5, two small tiles, More lists all ten',
      (tester, c, s) async {
        await _pumpRoom(
          tester,
          c,
          1.0,
          av: true,
          members: 6,
          chatOpen: true,
          chat: mockChatMessagesList,
        );
        await settle(tester);
        final bar = tester.getRect(find.byType(RoomControlBar));
        expect(bar.width, closeTo(332, 1));
        expect(bar.height, 64);
        expect(inline('Mic on (D)'), findsNothing);
        expect(find.byType(PTPlayButton).hitTestable(), findsOneWidget);
        expect(tiles(), findsNWidgets(2));
        for (final r in tileRects(tester)) {
          expect(r.size, const Size(104, 58));
        }
        expectRailClear(tester, chatOpen: true);
        // E: the list, anchored above the bar, taller than nothing and shorter
        // than the room above it.
        await tester.tap(_barMore().hitTestable());
        await tester.pump(const Duration(milliseconds: 400));
        for (final label in [
          'Microphone',
          'Camera',
          'React',
          'Back 10 s',
          'Forward 10 s',
          'Source',
          'Open file',
          'Audio track',
          'Subtitles',
          'Hide controls',
        ]) {
          expect(find.text(label), findsOneWidget, reason: label);
        }
        final panel = tester.getRect(
          find.ancestor(of: find.text('Source'), matching: find.byType(GlassPanel)).first,
        );
        expect(panel.height, closeTo(236, 2));
        expect(panel.bottom, lessThanOrEqualTo(bar.top));
        expect(panel.top, greaterThanOrEqualTo(16));
        await _finish(tester);
      },
      cases: [se],
      textScales: [1.0],
    );

    testWidgets('a short window at 2x text gives the chat the column and keeps the bar', (
      tester,
    ) async {
      try {
        await _pumpRoom(tester, se, 2.0, chatOpen: true, chat: mockChatMessagesList);
        await settle(tester);
        final bar = tester.getRect(find.byType(RoomControlBar));
        expect(find.byType(PTPlayButton).hitTestable(), findsOneWidget);
        expect(chatPanelRect(tester).overlaps(bar), isFalse);
        await _finish(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('the invite code pill is hidden at 2x, and the room menu still copies it', (
      tester,
    ) async {
      try {
        await _pumpRoom(tester, se, 2.0);
        await settle(tester);
        expect(find.byType(RoomCodeChip), findsNothing);
        await tester.tap(find.byTooltip('Room menu'));
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('Copy invite link'), findsOneWidget);
        await _finish(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  /// Records the system-UI modes the room asks for.
  List<String> recordUiModes(WidgetTester tester) {
    final modes = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
      call,
    ) async {
      if (call.method == 'SystemChrome.setEnabledSystemUIMode') modes.add('${call.arguments}');
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    return modes;
  }

  testWidgets('phone landscape goes immersive while playing with hidden controls', (tester) async {
    final modes = recordUiModes(tester);
    try {
      await _pumpRoom(tester, kScreenMatrix.firstWhere((c) => c.name == 'phone-land'), 1.0);
      expect(modes, isEmpty);
      // Play, then tap the video to hide the chrome.
      await _playAndHideControls(tester);
      expect(modes, ['SystemUiMode.immersiveSticky']);
      // A tap on the video brings the controls, and the bars, back.
      await tester.tapAt(tester.getCenter(find.byType(_VideoProbe)));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(modes.last, 'SystemUiMode.edgeToEdge');
      await _finish(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('tablets never go immersive', (tester) async {
    final modes = recordUiModes(tester);
    try {
      await _pumpRoom(tester, kScreenMatrix.firstWhere((c) => c.name == 'ipad-land'), 1.0);
      await _playAndHideControls(tester);
      expect(modes, isEmpty);
      await _finish(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

_FakePlayer? _lastPlayer;

/// The bar's own More button (the header carries a room-menu one with the
/// same glyph).
Finder _barMore() =>
    find.descendant(of: find.byType(RoomControlBar), matching: find.byIcon(BoothIcons.moreHoriz));

/// Opens the reaction strip: its key when the bar still shows one, otherwise
/// its row in the bar's More list (react folds early on a narrow bar).
Future<void> _tapReact(WidgetTester tester) async {
  final key = find.byTooltip('React (R)').hitTestable();
  if (key.evaluate().isNotEmpty) {
    await tester.tap(key.first);
  } else {
    await tester.tap(_barMore().hitTestable());
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('React').hitTestable().first);
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> _playAndHideControls(WidgetTester tester) async {
  _lastPlayer!.playing.add(true);
  await tester.pump();
  await tester.tapAt(tester.getCenter(find.byType(_VideoProbe)));
  // Past the touch layouts' double-tap window, so the tap lands as a tap.
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}
