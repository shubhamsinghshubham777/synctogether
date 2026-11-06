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
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/av/livekit_service.dart';
import 'package:synctogether/mock/mock_dependencies.dart';
import 'package:synctogether/profile/entitlement_service.dart';
import 'package:synctogether/profile/profile_service.dart';
import 'package:synctogether/player/mode_selection_dialog.dart';
import 'package:synctogether/player/youtube_url_dialog.dart';
import 'package:synctogether/rooms/room_dependencies.dart';
import 'package:synctogether/rooms/room_models.dart';
import 'package:synctogether/rooms/room_screen.dart';
import 'package:synctogether/rooms/room_service.dart';
import 'package:synctogether/rooms/widgets/emoji_picker.dart';
import 'package:synctogether/rooms/widgets/facecam_rail.dart';
import 'package:synctogether/rooms/widgets/reaction_strip.dart';
import 'package:synctogether/rooms/widgets/readiness_overlay.dart';
import 'package:synctogether/rooms/widgets/room_chat_panel.dart';
import 'package:synctogether/rooms/widgets/room_control_bar.dart';
import 'package:synctogether/rooms/widgets/room_roster.dart';
import 'package:synctogether/sync/sync_service.dart';
import 'package:synctogether/ui/booth_icons.g.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/identity.dart';
import 'package:synctogether/ui/inputs.dart';
import 'package:synctogether/ui/pt_motion.dart';
import 'package:synctogether/ui/responsive.dart';

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

  /// Makes `open` throw, the way a file the decoder cannot read does.
  bool failOpen = false;

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    if (failOpen) throw StateError('could not open');
  }

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

/// A room with nothing chosen yet: the host's empty state.
Room _emptyRoom() => Room(
  id: 'room-1',
  code: 'X7K9P2',
  name: 'Friday Horror Club',
  createdBy: 'user-alex',
  createdAt: DateTime.now().subtract(const Duration(minutes: 30)),
  durationMinutes: 120,
  expiresAt: DateTime.now().add(const Duration(minutes: 90)),
  maxMembers: 8,
  avLevel: .video,
);

/// Who holds the host role: the viewer (`user-alex`), or - when [selfHost] is
/// false - the second member, leaving the viewer as an ordinary member.
String _roleOf(int i, bool selfHost) => (selfHost ? i == 0 : i == 1) ? 'host' : 'member';

List<RoomMember> _roomMembers(int n, {bool selfHost = true}) => [
  for (var i = 0; i < n; i++)
    RoomMember(
      roomId: 'room-1',
      userId: i == 0 ? 'user-alex' : 'u$i',
      role: _roleOf(i, selfHost),
      joinedAt: DateTime.now().subtract(Duration(minutes: 60 - i)),
      profile: mockCurrentProfile,
    ),
];

List<Map<String, dynamic>> _presence(int n, {required bool allReady, bool selfHost = true}) => [
  for (var i = 0; i < n; i++)
    {
      'user_id': i == 0 ? 'user-alex' : 'u$i',
      'display_name': i == 0 ? 'Alex Rivers' : (i.isOdd ? _longName : 'Sam $i'),
      'role': _roleOf(i, selfHost),
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
  bool selfHost = true,
  bool remembered = true,
  bool openFails = false,
}) async {
  final h = _Harness();
  h.player.failOpen = openFails;
  _lastPlayer = h.player;
  final r = room ?? _room();
  // A remembered copy of the room's file, so the room reopens it on entry and
  // we are not the one holding the gate.
  final dir = Directory('${Directory.systemTemp.path}/room_matrix')..createSync(recursive: true);
  final copy = File('${dir.path}/$_file')..writeAsStringSync('');
  SharedPreferences.setMockInitialValues({
    if (remembered)
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
    ..addAll(_roomMembers(members, selfHost: selfHost));
  h.backend
    ..chatHistory = chat
    ..roomRow = r
    ..membership = MembershipRow(
      role: selfHost ? 'host' : 'member',
      joinedAt: DateTime.now().subtract(const Duration(minutes: 60)),
    );
  SyncService.defaultBackendOverride = h.backend;
  LiveKitService.isConfiguredOverride = av;
  // Mock AV also fakes an opened file; a room whose open fails must resume the
  // real way, so the mock only turns on once it has tried.
  LiveKitService.isMockMode = av && !openFails;
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
  if (av && openFails) LiveKitService.isMockMode = true;
  channel.emitStatus(.subscribed);
  channel.syncPresence(_presence(members, allReady: allReady, selfHost: selfHost));
  await tester.pump();
  if (allReady && r.mediaDuration != null) {
    h.player.state = h.player.state.copyWith(duration: r.mediaDuration);
    h.player.duration.add(r.mediaDuration!);
    h.player.position.add(const Duration(minutes: 42, seconds: 7));
  }
  if (playing) h.player.playing.add(true);
  await tester.pump(const Duration(milliseconds: 500));
  // The failed open is reported (as it is in production); it is the premise of
  // the case, not a finding of it.
  if (openFails) tester.takeException();
  return h;
}

/// [finishCase], then outlasts the room's 10 s "announce the file without a
/// duration" fallback, a `timeout` that is not tied to the widget's life.
Future<void> _finish(WidgetTester tester) async {
  // Let entrances (roster stagger, banner slides) land before the capture, so
  // the screenshot is the settled screen rather than a mid-animation frame.
  await tester.pump(const Duration(seconds: 2));
  if (_lastPlayer?.failOpen ?? false) tester.takeException();
  await finishCase(tester);
  await tester.pump(const Duration(seconds: 11));
  if (_lastPlayer?.failOpen ?? false) tester.takeException();
}

Finder tiles() => find.descendant(
  of: find.byType(FacecamRail),
  matching: find.byWidgetPredicate((w) => w.runtimeType.toString() == '_FacecamTile'),
);

/// Boards 47/48: the readiness / empty-state card rests at the bottom of the
/// picture, a gutter above its edge (or above the floating control bar), never
/// centred, and never over the control bar, the chat or the facecam rail.
void expectCardBottomAnchored(WidgetTester tester, ScreenCase c, double s) {
  final label = '${c.name} x$s';
  final overlayFinder = find.byType(ReadinessOverlay);
  expect(overlayFinder, findsOneWidget, reason: label);
  final overlay = tester.widget<ReadinessOverlay>(overlayFinder);
  final box = tester.getRect(overlayFinder);
  final system = MediaQuery.paddingOf(tester.element(overlayFinder));
  final card = tester.getRect(
    find.descendant(of: overlayFinder, matching: find.byType(GlassPanel)).first,
  );
  expect(card.bottom, lessThanOrEqualTo(box.bottom + 0.5), reason: '$label: $card below $box');
  // The gap under the card: the gutter plus whatever chrome/system inset
  // reaches it - or, when height runs out, the 4 px tight form.
  final inset = overlay.chromeInsets.bottom + system.bottom;
  final gutter = overlay.compact ? 12.0 : 16.0;
  final tight = system.bottom + overlay.chromeInsets.bottom + 4;
  final gap = box.bottom - card.bottom;
  final matches = [inset + gutter, tight].any((e) => (gap - e).abs() <= 2);
  // A card taller than the gap scrolls with its bottom pinned instead.
  final scrolls = card.top <= box.top + 0.5;
  expect(
    matches || scrolls,
    isTrue,
    reason: '$label: gap $gap, wanted ${inset + gutter} (or tight $tight) in $box, card $card',
  );
  expect(card.left, greaterThanOrEqualTo(box.left), reason: label);
  expect(card.right, lessThanOrEqualTo(box.right), reason: label);
  for (final other in [RoomControlBar, RoomChatPanel, FacecamRail]) {
    for (final e in find.byType(other).evaluate()) {
      final r = tester.getRect(find.byElementPredicate((x) => x == e));
      expect(
        r.intersect(card).isEmpty || r.intersect(card).width <= 0 || r.intersect(card).height <= 0,
        isTrue,
        reason:
            '$label: card $card overlaps $other $r (overlay $box, chrome ${overlay.chromeInsets}, system $system)',
      );
    }
  }
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
    await expectTapAwayClosesKeyboard(tester, c);
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

  /// Pumps the host-less-room case: nothing chosen yet, the picker already
  /// dismissed (the way a user who backs out of the chooser lands here).
  Future<void> pumpEmptyRoom(
    WidgetTester tester,
    ScreenCase c,
    double s, {
    bool host = true,
    bool av = false,
  }) async {
    await _pumpRoom(
      tester,
      c,
      s,
      room: _emptyRoom(),
      av: av,
      members: 2,
      selfHost: host,
      remembered: false,
    );
    final dialog = find.byType(ModeSelectionDialog);
    if (dialog.evaluate().isNotEmpty) {
      Navigator.of(tester.element(dialog)).pop();
    }
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 1));
    // A member has no source to wait for: the room answers "idle" after the
    // state-request retry window (2 x 2 s), and only then does the waiting card
    // replace the "Setting up the room" spinner.
    if (!host) await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 1));
  }

  const emptyScales = [1.0, 1.5, 2.0];
  final emptyCases = kScreenMatrix.where((c) => c.keyboard == 0).toList();

  screenMatrix(
    'room empty state, host',
    (tester, c, s) async {
      await pumpEmptyRoom(tester, c, s);
      final pick = find.text('Choose a video');
      expect(pick, findsOneWidget, reason: '${c.name} x$s: no way to choose');
      expect(
        pick.hitTestable(),
        findsOneWidget,
        reason: '${c.name} x$s: choose button not hittable',
      );
      final visible = Rect.fromLTWH(0, 0, c.size.width, c.size.height - c.keyboard);
      final button = find.ancestor(of: pick, matching: find.byType(PTButton));
      final r = tester.getRect(button);
      expect(
        visible.contains(r.topLeft) && visible.contains(r.bottomRight),
        isTrue,
        reason: '${c.name} x$s: $r outside $visible',
      );
      expect(r.height, greaterThanOrEqualTo(44), reason: '${c.name} x$s: primary under 44 px');
      expectShownWhole(tester, 'Choose a video');
      expectCardBottomAnchored(tester, c, s);
      await _finish(tester);
    },
    textScales: emptyScales,
    cases: emptyCases,
  );

  screenMatrix(
    'room empty state, host, with the facecam rail',
    (tester, c, s) async {
      await pumpEmptyRoom(tester, c, s, av: true);
      expect(find.text('Choose a video').hitTestable(), findsOneWidget, reason: '${c.name} x$s');
      expectCardBottomAnchored(tester, c, s);
      await _finish(tester);
    },
    textScales: [1.0, 2.0],
    cases: emptyCases,
  );

  screenMatrix(
    'room empty state, member sees no dead-end button',
    (tester, c, s) async {
      await pumpEmptyRoom(tester, c, s, host: false);
      expect(find.textContaining('Waiting for the host'), findsOneWidget);
      expect(find.text('Choose a video'), findsNothing);
      expect(find.text('Use a YouTube link instead'), findsNothing);
      expectCardBottomAnchored(tester, c, s);
      await _finish(tester);
    },
    textScales: emptyScales,
    cases: emptyCases,
  );

  testWidgets('empty state: the host can switch source from the overlay', (tester) async {
    final c = kScreenMatrix.firstWhere((c) => c.name == 'phone');
    try {
      await pumpEmptyRoom(tester, c, 1.0);
      final other = find.text('YouTube link');
      expect(other, findsOneWidget);
      await tester.tap(other);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(YouTubeUrlDialog), findsOneWidget);
      Navigator.of(tester.element(find.byType(YouTubeUrlDialog))).pop();
      await tester.pump(const Duration(milliseconds: 500));
      await _finish(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  // One participant is one tile at a 16:9 frame, never a banner across the
  // screen with the face cropped away.
  screenMatrix(
    'room facecam strip, one participant',
    (tester, c, s) async {
      await _pumpRoom(tester, c, s, av: true, members: 1);
      final all = tiles();
      expect(all, findsOneWidget, reason: '${c.name} x$s: expected a single tile');
      final r = tester.getRect(all);
      expect(r.width / r.height, inInclusiveRange(1.5, 2.0), reason: '${c.name} x$s: $r');
      expect(r.width, lessThanOrEqualTo(kStripTileMaxWidth + 0.5));
      await _finish(tester);
    },
    textScales: [1.0, 2.0],
    cases: kScreenMatrix.where((c) {
      return c.name.startsWith('phone') && c.size.height > c.size.width && c.keyboard == 0;
    }).toList(),
  );

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

  // Foldables: every posture that splits the window (book, dual screen,
  // tabletop, half-opened either way), at every text scale.
  final splitCases = kScreenMatrix.where((c) => hingeRectOf(c) != null).toList();

  screenMatrix('room on a fold: transport in one pane, nothing under the hinge', (
    tester,
    c,
    s,
  ) async {
    await _pumpRoom(tester, c, s, playing: true, chatOpen: true, chat: mockChatMessagesList);
    expectTransportReachable(tester, c);
    final bar = find.byType(RoomControlBar);
    final play = tester.getRect(find.descendant(of: bar, matching: find.byType(PTPlayButton)));
    final seek = tester.getRect(find.descendant(of: bar, matching: find.byType(PTSlider)).first);
    expectInOnePane(tester.getRect(bar), c, 'control bar');
    expectInOnePane(play, c, 'play/pause');
    expectInOnePane(seek, c, 'seek bar');
    expectClearOfHinge(tester, c);
    await _finish(tester);
  }, cases: splitCases);

  screenMatrix('room on a fold: the empty-state card sits in one pane', (tester, c, s) async {
    await pumpEmptyRoom(tester, c, s);
    final pick = find.text('Choose a video');
    expect(pick.hitTestable(), findsOneWidget, reason: '${c.name} x$s: choose button not hittable');
    expectInOnePane(tester.getRect(pick), c, 'Choose a video');
    expectClearOfHinge(tester, c);
    await _finish(tester);
  }, cases: splitCases);

  screenMatrix(
    'room on a fold: a hinge keeps every pane on its own metrics',
    (tester, c, s) async {
      await _pumpRoom(tester, c, s, playing: true, chatOpen: true, chat: mockChatMessagesList);
      final fold = foldFromFeatures(c.features);
      final panes = panesOf(c.size, fold);
      // The chat composer lives in the second pane; its MediaQuery must be that
      // pane's, and carry no display features, so nothing inside re-splits it.
      final ctx = tester.element(find.byType(EditableText).first);
      final mq = MediaQuery.of(ctx);
      expect(mq.displayFeatures, isEmpty, reason: '${c.name}: a pane still sees the hinge');
      final bar = tester.element(find.byType(RoomControlBar).first);
      final barQ = MediaQuery.of(bar);
      // A soft keyboard shrinks the lower pane's height, never its width.
      bool isAPane(Size q) => panes.any((p) => p.width == q.width && q.height <= p.height + 0.5);
      expect(
        isAPane(barQ.size) || isAPane(mq.size),
        isTrue,
        reason: '${c.name}: pane sizes $panes vs bar ${barQ.size} / chat ${mq.size}',
      );
      await _finish(tester);
    },
    cases: splitCases,
    textScales: const [1.0],
  );

  // Folding and unfolding mid-session: the picture is never recreated, the
  // transport stays reachable on every frame, and the half-typed message
  // survives, whatever posture the window passes through - the Fold's, and the
  // iPhone Duo's (closed, opened, book-folded, turned to tabletop, flat portrait,
  // closed again), each with the insets that posture really has.
  for (final (name, sequence) in <(String, List<String>)>[
    ('Fold', ['fold-cover', 'fold-unfolded', 'fold-book', 'fold-unfolded', 'fold-cover']),
    (
      'iPhone Duo',
      [
        'iphone-duo-outer',
        'iphone-duo-inner-land',
        'iphone-duo-book',
        'iphone-duo-tabletop',
        'iphone-duo-inner-portrait',
        'iphone-duo-outer',
      ],
    ),
  ]) {
    testWidgets('$name posture sequence keeps one video surface and the draft', (tester) async {
      final cases = [for (final n in sequence) kScreenMatrix.firstWhere((c) => c.name == n)];
      try {
        await _pumpRoom(
          tester,
          cases.first,
          1.0,
          playing: true,
          chatOpen: true,
          chat: mockChatMessagesList,
        );
        final video = tester.state(find.byType(_VideoProbe));
        expect(_VideoProbe.mounts, 1);
        await tester.enterText(find.byType(EditableText).first, 'half typed');
        Future<void> go(ScreenCase to, {int frames = 12}) async {
          final from = tester.view.physicalSize;
          for (var i = 1; i <= frames; i++) {
            final t = i / frames;
            tester.view.physicalSize = Size(
              from.width + (to.size.width - from.width) * t,
              from.height + (to.size.height - from.height) * t,
            );
            // The fold and the insets arrive with the last frame, as the OS
            // reports them.
            tester.view.displayFeatures = i == frames ? to.features : const [];
            if (i == frames) {
              tester.view
                ..padding = FakeViewPadding(
                  left: to.padding.left,
                  top: to.padding.top,
                  right: to.padding.right,
                  bottom: to.padding.bottom,
                )
                ..viewPadding = FakeViewPadding(
                  left: to.padding.left,
                  top: to.padding.top,
                  right: to.padding.right,
                  bottom: to.padding.bottom,
                );
            }
            await tester.pump(const Duration(milliseconds: 16));
            expectNoOverflow(tester);
            expect(
              find.byType(PTPlayButton).hitTestable(),
              findsOneWidget,
              reason: 'transport lost at frame $i toward ${to.name}',
            );
          }
          await tester.pump(const Duration(milliseconds: 400));
          expectNoOverflow(tester);
        }

        for (final to in cases.skip(1)) {
          await go(to);
          expect(
            find.text('half typed'),
            findsOneWidget,
            reason: 'the draft was lost at ${to.name}',
          );
        }
        expect(tester.state(find.byType(_VideoProbe)), same(video));
        expect(_VideoProbe.mounts, 1, reason: 'the picture was recreated by a posture change');
        await _finish(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  // Inside one composition a resize is continuous: dragging a Split View handle
  // or an unfold animation across the deck's range moves the transport and chat
  // a few pixels a frame, never a pop.
  testWidgets('resizing inside the deck moves the transport smoothly', (tester) async {
    final flat = kScreenMatrix.firstWhere((c) => c.name == 'fold-unfolded');
    try {
      await _pumpRoom(tester, flat, 1.0, playing: true, chatOpen: true, chat: mockChatMessagesList);
      Rect rect(Finder f) => tester.getRect(f.first);
      final play = find.byType(PTPlayButton);
      final chat = find.byType(RoomChatPanel);
      var prevPlay = rect(play);
      var prevChat = rect(chat);
      const frames = 24;
      for (var i = 1; i <= frames; i++) {
        // 1104 down to 1010 tall at 882 wide: still near-square (under 1.3).
        tester.view.physicalSize = Size(882, 1104 - 94 * i / frames);
        await tester.pump(const Duration(milliseconds: 16));
        expectNoOverflow(tester);
        final nowPlay = rect(play);
        final nowChat = rect(chat);
        expect(
          (nowPlay.center - prevPlay.center).distance,
          lessThan(14),
          reason: 'transport jumped at frame $i',
        );
        expect(
          (nowChat.height - prevChat.height).abs(),
          lessThan(14),
          reason: 'chat popped at frame $i',
        );
        prevPlay = nowPlay;
        prevChat = nowChat;
      }
      await _finish(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

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
      // Portrait: the facecam strip and the reaction strip are separate surfaces with air
      // between them, not two borders touching.
      final strip = find.byType(ReactionStrip);
      if (c.size.height > c.size.width &&
          strip.evaluate().isNotEmpty &&
          tiles().evaluate().isNotEmpty) {
        final stripTop = tester.getRect(strip).top;
        var tilesBottom = double.negativeInfinity;
        for (var i = 0; i < tiles().evaluate().length; i++) {
          final r = tester.getRect(tiles().at(i));
          if (r.bottom <= stripTop + 0.5 && r.bottom > tilesBottom) tilesBottom = r.bottom;
        }
        if (tilesBottom.isFinite) {
          expect(stripTop - tilesBottom, greaterThanOrEqualTo(6), reason: 'cams crammed on strip');
        }
      }
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

  // The phone room's "In the room" strip folds to one slim row. It is the first
  // thing the stack hides when height runs short, so a case where it is hidden
  // has nothing to fold; everywhere it shows it must fold without moving the
  // transport and keep a 44 px target.
  final rosterCases = kScreenMatrix
      .where((c) => c.size.height > c.size.width && c.keyboard == 0 && c.features.isEmpty)
      .toList();
  final rosterToggle = find.textContaining('IN THE ROOM');

  screenMatrix('room roster expanded, someone still getting ready', (tester, c, s) async {
    await _pumpRoom(tester, c, s, allReady: false, members: 4, chat: mockChatMessagesList);
    if (rosterToggle.evaluate().isNotEmpty) {
      expect(find.byType(FoldableRoster), findsOneWidget);
      expect(find.byType(RosterRings), findsOneWidget);
    }
    await _finish(tester);
  }, cases: rosterCases);

  screenMatrix('room roster folded by hand', (tester, c, s) async {
    await _pumpRoom(tester, c, s, allReady: false, members: 4, chat: mockChatMessagesList);
    if (rosterToggle.evaluate().isNotEmpty) {
      await tester.tap(rosterToggle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }
    await _finish(tester);
  }, cases: rosterCases);

  screenMatrix('room roster fold: slimmer, 44 px target, transport and chat do not move', (
    tester,
    c,
    s,
  ) async {
    await _pumpRoom(tester, c, s, allReady: false, members: 4, chat: mockChatMessagesList);
    if (c.name == 'phone' && s == 1.0) {
      expect(rosterToggle, findsOneWidget, reason: 'a plain phone has room for the strip');
    }
    if (rosterToggle.evaluate().isEmpty) {
      await _finish(tester);
      return;
    }
    final roster = find.byType(FoldableRoster);
    final open = tester.getSize(roster).height;
    final bar = tester.getRect(find.byType(RoomControlBar));
    final panel = tester.getRect(find.byType(RoomChatPanel));
    final target = find.ancestor(of: rosterToggle, matching: find.byType(PTPressable));
    expect(tester.getSize(target).height, greaterThanOrEqualTo(44), reason: '${c.name} x$s');

    await tester.tap(rosterToggle);
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.getRect(find.byType(RoomControlBar)), bar, reason: 'transport moved mid-fold');
    await tester.pump(const Duration(milliseconds: 500));
    final slim = tester.getSize(roster).height;
    expect(slim, lessThan(open), reason: '${c.name} x$s: folded $slim, open $open');
    expect(slim, lessThanOrEqualTo(max(46.0, 46.0 * s)), reason: 'the folded row is slim');
    expect(tester.getRect(find.byType(RoomControlBar)), bar);
    expect(tester.getRect(find.byType(RoomChatPanel)), panel, reason: 'the chat slot is fixed');
    expectTransportReachable(tester, c);
    // The composer still sits at the bottom, where the thumb expects it.
    final input = tester.getRect(find.byType(EditableText).first);
    expect(input.bottom, lessThanOrEqualTo(c.size.height));

    await tester.tap(rosterToggle);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.getSize(roster).height, open, reason: 'opening restores the same height');
    await _finish(tester);
  }, cases: rosterCases);

  // The outlined mic, camera and react squares read as three buttons: equal
  // gaps between neighbours, never the ~1 px that merged two hairlines.
  for (final variant in ['camera on', 'camera locked', 'video trial tag']) {
    screenMatrix(
      'phone bar left keys evenly spaced, $variant',
      (tester, c, s) async {
        // Both the case's own width (portrait forms keep two keys or fewer)
        // and a wide slot, where mic, camera and react are all inline.
        for (final width in [c.size.width, 600.0]) {
          await pumpAtSize(
            tester,
            Scaffold(
              body: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: width,
                maxWidth: width,
                child: SizedBox(
                  width: width,
                  child: RoomControlBar(
                    playing: true,
                    position: const Duration(minutes: 42),
                    duration: const Duration(hours: 2, minutes: 49),
                    volume: 0.7,
                    micOn: false,
                    camOn: variant == 'camera on',
                    avAvailable: true,
                    camAvailable: variant != 'camera locked',
                    camTrialMinutes: variant == 'video trial tag' ? 10 : null,
                    compact: true,
                    actions: RoomControlBarActions(
                      onPlayPause: () {},
                      onSeek: (_) {},
                      onSkip: (_) {},
                      onMicToggle: (_) {},
                      onCamToggle: (_) {},
                      onCamLocked: () {},
                      onAudioTracks: () {},
                      onSubtitles: () {},
                      onSwitchSource: () {},
                      onOpenFile: () {},
                      onVolume: (_) {},
                      onToggleMute: () {},
                      onReact: () {},
                    ),
                  ),
                ),
              ),
            ),
            c,
            textScale: s,
          );
          await tester.pump(const Duration(milliseconds: 300));
          final keys = <Rect>[];
          for (final element
              in find
                  .descendant(of: find.byType(RoomControlBar), matching: find.byType(PTIconButton))
                  .evaluate()) {
            final tip = (element.widget as PTIconButton).tooltip ?? '';
            if (tip.startsWith('Mic') ||
                tip.startsWith('Camera') ||
                tip.startsWith('Try video') ||
                tip.startsWith('Video facecams') ||
                tip.startsWith('React')) {
              keys.add(tester.getRect(find.byWidget(element.widget)));
            }
          }
          keys.sort((a, b) => a.left.compareTo(b.left));
          if (width >= 600) expect(keys, hasLength(3), reason: '${c.name} wide slot');
          for (final k in keys) {
            expect(k.width, 44, reason: 'touch target stays 44');
          }
          final gaps = [for (var i = 1; i < keys.length; i++) keys[i].left - keys[i - 1].right];
          for (final gap in gaps) {
            expect(gap, greaterThanOrEqualTo(6), reason: '${c.name} $variant gaps $gaps');
            expect(gap, closeTo(gaps.first, 0.01), reason: '${c.name} $variant gaps $gaps');
          }
        }
        await finishCase(tester);
      },
      cases: kScreenMatrix.where((c) => c.name.startsWith('phone')).toList(),
      textScales: [1.0, 2.0],
      checkInsets: false,
    );
  }

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

  group('busy portrait room with the soft keyboard', () {
    // Exactly what a TestFlight recording showed: the host's file would not
    // open, our camera is on, the reaction strip is open, one chat bubble and
    // the keyboard up.
    final busyCases = [
      kScreenMatrix.firstWhere((c) => c.name == 'phone-keyboard'),
      kScreenMatrix.firstWhere((c) => c.name == 'phone-android-keyboard'),
      const ScreenCase(
        'phone-small-keyboard',
        Size(320, 568),
        .iOS,
        padding: EdgeInsets.only(top: 20),
        keyboard: 260,
      ),
    ];

    Future<_Harness> pumpBusy(WidgetTester tester, ScreenCase c, double s) async {
      final h = await _pumpRoom(
        tester,
        c,
        s,
        av: true,
        members: 4,
        allReady: false,
        selfHost: false,
        openFails: true,
        chat: [mockChatMessagesList.first],
      );
      // Open the reaction strip with the keyboard down, then raise it - the
      // order a person does it in.
      tester.view
        ..viewInsets = FakeViewPadding.zero
        ..padding = FakeViewPadding(
          left: c.padding.left,
          top: c.padding.top,
          right: c.padding.right,
          bottom: c.padding.bottom,
        );
      await tester.pump(const Duration(milliseconds: 400));
      await _tapReact(tester);
      tester.view
        ..viewInsets = FakeViewPadding(bottom: c.keyboard)
        ..padding = FakeViewPadding(
          left: c.padding.left,
          top: c.padding.top,
          right: c.padding.right,
          bottom: (c.padding.bottom - c.keyboard).clamp(0, double.infinity),
        );
      await tester.showKeyboard(find.byType(EditableText).first);
      // Past the "couldn't open that file" toast, which is its own transient
      // layer over the room.
      await tester.pump(const Duration(seconds: 6));
      return h;
    }

    screenMatrix(
      'transport and composer stay clear of the keyboard',
      (tester, c, s) async {
        await pumpBusy(tester, c, s);
        final visible = Rect.fromLTWH(0, 0, c.size.width, c.size.height - c.keyboard);
        final bar = find.byType(RoomControlBar);
        expect(bar, findsOneWidget);
        for (final f in [
          find.descendant(of: bar, matching: find.byType(PTPlayButton)),
          find.descendant(of: bar, matching: find.byType(PTSlider)).first,
        ]) {
          expect(f.hitTestable(), findsOneWidget, reason: '${c.name}: transport not hittable');
          final r = tester.getRect(f);
          expect(visible.inflate(0.5).contains(r.topLeft), isTrue, reason: '${c.name}: $r');
          expect(visible.inflate(0.5).contains(r.bottomRight), isTrue, reason: '${c.name}: $r');
        }
        // Whatever keys the bar still shows are whole.
        for (final tip in ['React (R)', 'Mute', 'Camera']) {
          for (final e in find.byTooltip(RegExp(tip)).evaluate()) {
            final r = tester.getRect(find.byElementPredicate((x) => x == e));
            if (r.height <= 0) continue;
            expect(r.bottom, lessThanOrEqualTo(visible.bottom + 0.5), reason: '$tip clipped');
          }
        }
        // The newest chat bubble is whole: nothing of the list clips it.
        final panel = tester.getRect(find.byType(RoomChatPanel).first);
        final bubble = find.textContaining('Audio and video are locked in');
        expect(bubble, findsOneWidget);
        final b = tester.getRect(bubble);
        expect(b.top, greaterThanOrEqualTo(panel.top - 0.5), reason: 'newest bubble clipped');
        expect(b.bottom, lessThanOrEqualTo(panel.bottom + 0.5));
        // The composer is under the bar and above the keyboard.
        final input = tester.getRect(find.byType(EditableText).first);
        expect(input.bottom, lessThanOrEqualTo(visible.bottom + 0.5));
        expect(input.top, greaterThanOrEqualTo(tester.getRect(bar).bottom - 0.5));
        await _finish(tester);
      },
      cases: busyCases,
      textScales: const [1.0, 1.5],
    );

    // The keyboard slides in and out frame by frame, the way the OS does it.
    // Whatever the layout hides or shows on the way (strips, facecams, quick
    // bar, header) must fold with it, never pop: no slot may change height by
    // more than a keyboard step plus a fold's share in one 16 ms frame.
    screenMatrix(
      'keyboard open and close animates every slot without a pop',
      (tester, c, s) async {
        await pumpBusy(tester, c, s);
        FakeViewPadding insets(double k) => FakeViewPadding(bottom: k);
        Rect rect(Finder f) => tester.getRect(f.first);
        final bar = find.byType(RoomControlBar);
        final chat = find.byType(RoomChatPanel);
        final input = find.byType(EditableText);
        final play = find.descendant(of: bar, matching: find.byType(PTPlayButton));
        const names = ['bar', 'chat', 'input'];
        List<Rect> snap() => [rect(bar), rect(chat), rect(input)];
        final settled = snap();
        for (final k in [0, 1]) {
          final from = k == 0 ? c.keyboard : 0.0;
          final to = k == 0 ? 0.0 : c.keyboard;
          var prev = snap();
          const frames = 16;
          for (var i = 1; i <= frames; i++) {
            final inset = from + (to - from) * i / frames;
            tester.view
              ..viewInsets = insets(inset)
              ..padding = FakeViewPadding(
                top: c.padding.top,
                bottom: inset > 0 ? 0 : c.padding.bottom,
              );
            await tester.pump(const Duration(milliseconds: 16));
            final now = snap();
            final step = c.keyboard / frames;
            for (var j = 0; j < names.length; j++) {
              final dh = (now[j].height - prev[j].height).abs();
              expect(
                dh,
                lessThanOrEqualTo(step + 48),
                reason: '${c.name} x$s: ${names[j]} height popped by $dh px at frame $i',
              );
              final dy = (now[j].top - prev[j].top).abs();
              expect(
                dy,
                lessThanOrEqualTo(step + 90),
                reason: '${c.name} x$s: ${names[j]} jumped by $dy px at frame $i',
              );
            }
            expect(play.hitTestable(), findsOneWidget, reason: '${c.name}: transport lost');
            prev = now;
          }
          // Folds started on the last frame run on their own clock.
          for (var i = 0; i < 30; i++) {
            await tester.pump(const Duration(milliseconds: 16));
            final now = snap();
            for (var j = 0; j < names.length; j++) {
              expect(
                (now[j].height - prev[j].height).abs(),
                lessThanOrEqualTo(48),
                reason: '${c.name} x$s: ${names[j]} popped while settling',
              );
            }
            expect(play.hitTestable(), findsOneWidget);
            prev = now;
          }
        }
        // Back where it started, exactly as the unanimated layout puts it.
        final now = snap();
        for (var j = 0; j < names.length; j++) {
          expect(now[j].height, closeTo(settled[j].height, 0.5), reason: names[j]);
          expect(now[j].top, closeTo(settled[j].top, 0.5), reason: names[j]);
        }
        await _finish(tester);
      },
      cases: busyCases,
      textScales: const [1.0, 1.5],
    );

    testWidgets('the header folds away with the keyboard instead of cutting', (tester) async {
      final c = kScreenMatrix.firstWhere((c) => c.name == 'phone-keyboard');
      try {
        await _pumpRoom(
          tester,
          c,
          1.0,
          av: true,
          allReady: false,
          selfHost: false,
          openFails: true,
          chat: [mockChatMessagesList.first],
        );
        // Start from keyboard down.
        tester.view
          ..viewInsets = FakeViewPadding.zero
          ..padding = FakeViewPadding(top: c.padding.top, bottom: c.padding.bottom);
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump(const Duration(milliseconds: 600));
        // The chat's top edge sits under everything the header pushes.
        final video = find.byType(RoomChatPanel);
        final before = tester.getRect(video).top;
        // The keyboard starts to rise: one frame in, the picture may not have
        // jumped by the header's whole height.
        tester.view
          ..viewInsets = const FakeViewPadding(bottom: 24)
          ..padding = FakeViewPadding(top: c.padding.top);
        await tester.pump(const Duration(milliseconds: 16));
        final moved = (tester.getRect(video).top - before).abs();
        expect(moved, lessThan(25), reason: 'the header cut away in one frame ($moved px)');
        // And it does go: collapsed once the motion has run.
        tester.view
          ..viewInsets = FakeViewPadding(bottom: c.keyboard)
          ..padding = FakeViewPadding(top: c.padding.top);
        // Two frames: the first starts the strips' folds, the second runs them.
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump(const Duration(milliseconds: 600));
        expect(tester.getRect(video).top, lessThan(before - 30));
        // Hidden means out of reach, not just out of sight.
        expect(find.byTooltip('Room menu').hitTestable(), findsNothing);
        await _finish(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('emoji picker and keyboard are never on screen together', (tester) async {
      final c = kScreenMatrix.firstWhere((c) => c.name == 'phone-keyboard');
      try {
        await pumpBusy(tester, c, 1.0);
        final composerTop = tester.getRect(find.byType(EditableText).first).top;
        await tester.tap(find.byTooltip(RegExp('Emoji')).first);
        // The OS slides the keyboard away over ~250 ms.
        for (var k = 336.0; k >= 0; k -= 56) {
          tester.view.viewInsets = FakeViewPadding(bottom: k);
          tester.view.padding = FakeViewPadding(bottom: k == 0 ? 34 : 0);
          await tester.pump(const Duration(milliseconds: 16));
          final picker = find.byType(EmojiPicker);
          if (picker.evaluate().isNotEmpty) {
            // The picker is revealed through its clip: that is what shows.
            final clip = find.ancestor(of: picker.first, matching: find.byType(ClipRect)).first;
            final box = tester.renderObject<RenderBox>(clip);
            final revealed = (box as RenderClipRect).clipper!.getClip(box.size);
            final top = box.localToGlobal(Offset.zero).dy;
            expect(
              top + revealed.height,
              lessThanOrEqualTo(c.size.height - k + 0.5),
              reason: 'picker overlaps the keyboard at $k',
            );
          }
          expect(
            tester.getRect(find.byType(EditableText).first).top,
            closeTo(composerTop, 1),
            reason: 'composer jumped during the hand-off at $k',
          );
        }
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('SMILEYS & EMOTION').hitTestable(), findsOneWidget);
        await _finish(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('inline emoji picker with no keyboard to trade places with', () {
    // Tapping the chat smiley with the keyboard down (a hardware keyboard, the
    // simulator, or after the user closed it). The picker's strip used to
    // appear and vanish in one frame: the composer jumped a quarter of the
    // screen and the picture resized at once. It now folds in and out.
    final cases = [
      kScreenMatrix.firstWhere((c) => c.name == 'phone'),
      kScreenMatrix.firstWhere((c) => c.name == 'phone-android'),
      kScreenMatrix.firstWhere((c) => c.name == 'phone-small'),
    ];

    screenMatrix(
      'opens and closes by folding, not popping',
      (tester, c, s) async {
        await _pumpRoom(
          tester,
          c,
          s,
          av: true,
          members: 4,
          allReady: false,
          selfHost: false,
          openFails: true,
          chat: [mockChatMessagesList.first],
        );
        await tester.pump(const Duration(seconds: 6));
        final bar = find.byType(RoomControlBar);
        final chat = find.byType(RoomChatPanel);
        final input = find.byType(EditableText);
        final play = find.descendant(of: bar, matching: find.byType(PTPlayButton));
        Rect rect(Finder f) => tester.getRect(f.first);
        List<Rect> snap() => [rect(bar), rect(chat), rect(input)];
        final settled = snap();
        // 16 ms frames: the fold is 250 ms, ~15 frames. The composer moves the
        // picker's height (~280 px) in total, eased, so its fastest frame is
        // ~1.5x the mean; a pop would be the whole strip in one.
        const maxStep = 48.0;
        var prevTop = rect(input).top;

        void step(String phase, int i) {
          final top = rect(input).top;
          expect(
            (top - prevTop).abs(),
            lessThanOrEqualTo(maxStep),
            reason: '${c.name} x$s: composer jumped by ${top - prevTop} px at $phase frame $i',
          );
          prevTop = top;
          expect(play.hitTestable(), findsOneWidget, reason: '${c.name}: transport lost');
          final picker = find.byType(EmojiPicker);
          if (picker.evaluate().isNotEmpty) {
            final clip = find.ancestor(of: picker.first, matching: find.byType(ClipRect)).first;
            final box = tester.renderObject<RenderBox>(clip);
            final shown = (box as RenderClipRect).clipper!.getClip(box.size).height;
            final pickerTop = box.localToGlobal(Offset.zero).dy;
            // The composer sits above whatever part of the picker is shown, and
            // the picker never hangs off the screen.
            expect(
              rect(input).bottom,
              lessThanOrEqualTo(pickerTop + 0.5),
              reason: '${c.name} x$s: composer overlaps the picker at $phase frame $i',
            );
            expect(pickerTop + shown, lessThanOrEqualTo(c.size.height + 0.5));
          }
        }

        await tester.tap(find.byTooltip(RegExp('[Ee]moji')).first);
        for (var i = 1; i <= 40; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          step('open', i);
        }
        // Open: the picker is whole, usable, and nothing is cut.
        expect(find.text('SMILEYS & EMOTION').hitTestable(), findsOneWidget);
        expect(play.hitTestable(), findsOneWidget);
        expect(rect(input).top, lessThan(settled[2].top - 100), reason: 'composer made room');

        await tester.tap(find.byTooltip(RegExp('[Ee]moji')).first);
        for (var i = 1; i <= 40; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          step('close', i);
        }
        expect(find.byType(EmojiPicker), findsNothing);
        final now = snap();
        for (var j = 0; j < now.length; j++) {
          expect(now[j].height, closeTo(settled[j].height, 0.5), reason: 'item $j height');
          expect(now[j].top, closeTo(settled[j].top, 0.5), reason: 'item $j top');
        }
        await _finish(tester);
      },
      cases: cases,
      textScales: const [1.0, 1.5],
    );

    testWidgets('a tap on empty space folds the picker shut; a tap in its gaps does not', (
      tester,
    ) async {
      final c = kScreenMatrix.firstWhere((c) => c.name == 'phone');
      try {
        await _pumpRoom(
          tester,
          c,
          1.0,
          av: true,
          allReady: false,
          selfHost: false,
          openFails: true,
          chat: [mockChatMessagesList.first],
        );
        await tester.pump(const Duration(seconds: 6));
        await tester.tap(find.byTooltip(RegExp('[Ee]moji')).first);
        // The first frame starts the fold's ticker, the second runs it.
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.byType(EmojiPicker), findsOneWidget);
        // The picker's own surface (its header strip) is not empty space.
        await tester.tapAt(tester.getTopLeft(find.byType(EmojiPicker)) + const Offset(2, 2));
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.byType(EmojiPicker), findsOneWidget, reason: 'closed by a tap on itself');
        // Empty space: the room's header strip area beside the title.
        await tester.tapAt(Offset(c.size.width - 2, c.padding.top + 2));
        await tester.pump(const Duration(milliseconds: 40));
        await tester.pump(const Duration(milliseconds: 40));
        expect(find.byType(EmojiPicker), findsOneWidget, reason: 'it folds, it does not pop');
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.byType(EmojiPicker), findsNothing);
        await _finish(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('empty-tap sweep', () {
    testWidgets('every empty point of the chat area closes the picker; controls do not', (
      tester,
    ) async {
      final c = kScreenMatrix.firstWhere((c) => c.name == 'phone');
      try {
        await _pumpRoom(
          tester,
          c,
          1.0,
          av: true,
          allReady: false,
          selfHost: false,
          openFails: true,
          chat: mockChatMessagesList.take(6).toList(),
        );
        await tester.pump(const Duration(seconds: 6));
        Future<void> openPicker() async {
          await tester.tap(find.byTooltip(RegExp('[Ee]moji')).first);
          await tester.pump(const Duration(milliseconds: 600));
          await tester.pump(const Duration(milliseconds: 600));
          expect(find.byType(EmojiPicker), findsOneWidget);
        }

        await openPicker();
        final pickerTop = tester.getTopLeft(find.byType(EmojiPicker)).dy;
        final chat = tester.getRect(
          find.descendant(of: find.byType(RoomChatPanel), matching: find.byType(ListView)).first,
        );
        final misses = <Offset>[];
        for (var y = chat.top + 4; y < chat.bottom - 4; y += 24) {
          for (var x = 6.0; x < c.size.width - 4; x += 24) {
            final at = Offset(x, y);
            // A message bubble is left to selection: a tap there is not empty.
            if (find
                .byWidgetPredicate((w) => w.runtimeType.toString() == '_MessageRow')
                .evaluate()
                .any((e) => tester.getRect(find.byWidget(e.widget)).contains(at))) {
              continue;
            }
            // Anything a control or text sits under is not empty space.
            final hit = tester.hitTestOnBinding(at);
            final onControl = hit.path.any((e) {
              final t = e.target;
              return t is RenderParagraph ||
                  t is RenderEditable ||
                  t is RenderSemanticsGestureHandler && t.onTap != null && false;
            });
            if (onControl) continue;
            await tester.tapAt(at);
            await tester.pump(const Duration(milliseconds: 600));
            await tester.pump(const Duration(milliseconds: 600));
            if (find.byType(EmojiPicker).evaluate().isNotEmpty) {
              misses.add(at);
              continue;
            }
            if (find.byTooltip(RegExp('[Ee]moji')).evaluate().isEmpty) {
              misses.add(Offset(-1, -1) + at);
              break;
            }
            await tester.pump(const Duration(milliseconds: 600));
            await tester.tap(find.byTooltip(RegExp('[Ee]moji')).first);
            await tester.pump(const Duration(milliseconds: 600));
            await tester.pump(const Duration(milliseconds: 600));
            if (find.byType(EmojiPicker).evaluate().isEmpty) {
              misses.add(Offset(-2, -2) + at);
              break;
            }
          }
        }
        expect(misses, isEmpty, reason: 'taps that left the picker open');
        // What is not empty keeps it open: the picker's surface, a bubble.
        expect(pickerTop, greaterThan(chat.bottom - 1));
        await tester.tapAt(tester.getCenter(find.byType(EmojiPicker)));
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.byType(EmojiPicker), findsOneWidget, reason: 'a tap in the grid');
        final bubble = tester.getCenter(
          find.byWidgetPredicate((w) => w.runtimeType.toString() == '_MessageRow').first,
        );
        await tester.tapAt(bubble);
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.byType(EmojiPicker), findsOneWidget, reason: 'a tap on a message');
        await _finish(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('a file that failed to open', () {
    testWidgets('offers a different video, not the same bad copy', (tester) async {
      final c = kScreenMatrix.firstWhere((c) => c.name == 'phone');
      try {
        await _pumpRoom(tester, c, 1.0, allReady: false, selfHost: false, openFails: true);
        expect(find.text('Choose a different video'), findsOneWidget);
        expect(find.textContaining('Locate'), findsNothing);
        await _finish(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a member who simply lacks the file still gets Locate copy', (tester) async {
      final c = kScreenMatrix.firstWhere((c) => c.name == 'phone');
      try {
        await _pumpRoom(tester, c, 1.0, allReady: false, selfHost: false, remembered: false);
        expect(find.textContaining('Locate'), findsOneWidget);
        expect(find.text('Choose a different video'), findsNothing);
        await _finish(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
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
