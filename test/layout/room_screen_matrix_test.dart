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
import 'package:synctogether/rooms/widgets/room_control_bar.dart';
import 'package:synctogether/sync/sync_service.dart';
import 'package:synctogether/ui/buttons.dart';

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

  screenMatrix('room readiness overlay', (tester, c, s) async {
    await _pumpRoom(tester, c, s, members: 7, allReady: false);
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

  for (final width in [360.0, 390.0]) {
    testWidgets('phone control bar renders 1:1 at $width with every control', (tester) async {
      try {
        await _pumpRoom(tester, ScreenCase('phone-$width', Size(width, 800), .iOS), 1.0, av: true);
        final bar = find.byType(RoomControlBar);
        expect(bar, findsOneWidget);
        // Rects are global, so a scaled-down row shows up as smaller targets.
        Rect rectOf(Finder f) => tester.getRect(find.descendant(of: bar, matching: f).first);
        expect(rectOf(find.byTooltip('Mic on')).width, closeTo(44, 0.5));
        expect(rectOf(find.byType(PTPlayButton)).width, closeTo(52, 0.5));
        expect(find.descendant(of: bar, matching: find.byTooltip('Subtitles')), findsNothing);
        await _finish(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
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
}

_FakePlayer? _lastPlayer;

Future<void> _playAndHideControls(WidgetTester tester) async {
  _lastPlayer!.playing.add(true);
  await tester.pump();
  await tester.tapAt(tester.getCenter(find.byType(_VideoProbe)));
  // Past the touch layouts' double-tap window, so the tap lands as a tap.
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}
