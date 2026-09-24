// RoomScreen itself cannot be pumped in a widget test: it constructs a
// media_kit `Player` + `VideoController`, which need the native libmpv that
// `flutter test` does not load (probed: MediaKit.ensureInitialized/Player()
// throws). So this covers the room's constituent widgets, each given the space
// the room gives it: full width for the control bar, banners and reaction
// strip; the whole screen for the readiness overlay and the facecam layouts;
// and the chat panel both as a docked side panel and as the phone's embedded
// full-screen chat (the keyboard cases are the "chat keyboard mode").
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/av/livekit_service.dart';
import 'package:synctogether/rooms/reactions.dart';
import 'package:synctogether/rooms/room_models.dart';
import 'package:synctogether/rooms/widgets/facecam_rail.dart';
import 'package:synctogether/rooms/widgets/reaction_overlay.dart';
import 'package:synctogether/rooms/widgets/reaction_strip.dart';
import 'package:synctogether/rooms/widgets/readiness_overlay.dart';
import 'package:synctogether/rooms/widgets/room_chat_panel.dart';
import 'package:synctogether/rooms/widgets/room_control_bar.dart';
import 'package:synctogether/sync/sync_service.dart';
import 'package:synctogether/ui/banners.dart';

import '../support/screen_matrix.dart';
import '../sync/fakes.dart';
import 'layout_support.dart';

const _longName = 'Maximiliana Featherstonehaugh-Wolfeschlegel';
const _media = RoomMedia(
  kind: .local,
  name: 'Cosmic_Voyage_Directors_Cut_2160p_HDR10_Atmos.mkv',
  duration: Duration(hours: 2, minutes: 49, seconds: 3),
);

final _joined = DateTime(2026, 9, 1, 10);

List<PresentMember> _members(int n) => [
  for (var i = 0; i < n; i++)
    PresentMember(
      userId: i == 0 ? 'me' : 'u$i',
      displayName: i.isOdd ? _longName : 'Sam $i',
      role: i == 0 ? 'host' : 'member',
      joinedAt: _joined.add(Duration(minutes: i)),
      readyStatus: ReadyStatus.values[i % ReadyStatus.values.length],
      loadedFileName: i % 3 == 2 ? 'Some_Other_File_Entirely.mp4' : _media.name,
    ),
];

final _actions = RoomControlBarActions(
  onPlayPause: () {},
  onSeek: (_) {},
  onSkip: (_) {},
  onMicToggle: (_) {},
  onCamToggle: (_) {},
  onAudioTracks: () {},
  onSubtitles: () {},
  onSwitchSource: () {},
  onOpenFile: () {},
  onVolume: (_) {},
  onToggleMute: () {},
  onReact: () {},
  onHideControls: () {},
  onFullscreenToggle: () {},
);

bool _compact(ScreenCase c) => c.size.shortestSide < 600;

// The landscape room enters chat keyboard mode whenever the keyboard is up
// (the chat composer is the room's only text field) and removes the control
// bar entirely (`if (!keyboardMode)` in RoomScreen._landscape), so the bar is
// never laid out in a landscape-with-keyboard slot.
final _controlBarCases = [
  for (final c in kScreenMatrix)
    if (!(c.keyboard > 0 && c.size.width > c.size.height)) c,
];

Widget _bottom(Widget child) => Scaffold(
  body: SafeArea(
    child: Align(alignment: Alignment.bottomCenter, child: child),
  ),
);

List<ChatMessage> _chat() => [
  for (var i = 0; i < 30; i++)
    ChatMessage(
      senderId: i.isEven ? 'me' : 'u1',
      displayName: i.isEven ? 'me' : _longName,
      content: i % 5 == 0
          ? 'check this https://www.youtube.com/watch?v=J-95Mhipb98 out'
          : 'message number $i, which is long enough to wrap onto a second line in a narrow panel',
      sentAt: DateTime(2026, 9, 1, 10, i),
    ),
];

SyncService _sync() => SyncService(
  FakeSyncPlayer(),
  room: testRoom(),
  profile: testProfile('me'),
  role: 'host',
  backend: FakeSyncBackend(),
);

Widget _chatPanel(SyncService sync, {required bool embedded}) => RoomChatPanel(
  sync: sync,
  messages: _chat(),
  typingNames: const [_longName, 'Sam', 'Jo'],
  watchingCount: 6,
  onClose: () {},
  onSend: (_) {},
  onCopied: () {},
  onPlaySharedVideo: (_, _) {},
  onReportMessage: (_) {},
  embedded: embedded,
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LiveKitService.isConfiguredOverride = true;
    LiveKitService.isMockMode = true;
  });
  tearDown(() {
    LiveKitService.isConfiguredOverride = null;
    LiveKitService.isMockMode = false;
  });

  screenMatrix('room/control-bar-idle', (tester, c, s) async {
    await pumpAtSize(
      tester,
      _bottom(
        RoomControlBar(
          playing: false,
          position: Duration.zero,
          duration: Duration.zero,
          volume: 1,
          micOn: false,
          camOn: false,
          avAvailable: true,
          actions: _actions,
          compact: _compact(c),
          transportEnabled: false,
          transportHint: 'Waiting for everyone to load the file',
        ),
      ),
      c,
      textScale: s,
    );
    await finishCase(tester);
  }, cases: _controlBarCases);

  screenMatrix('room/control-bar-playing', (tester, c, s) async {
    await pumpAtSize(
      tester,
      _bottom(
        RoomControlBar(
          playing: true,
          position: const Duration(hours: 1, minutes: 23, seconds: 45),
          duration: _media.duration!,
          bufferedPosition: const Duration(hours: 1, minutes: 30),
          volume: 0.6,
          micOn: true,
          camOn: true,
          avAvailable: true,
          actions: _actions,
          compact: _compact(c),
          reactOpen: true,
        ),
      ),
      c,
      textScale: s,
    );
    await finishCase(tester);
  }, cases: _controlBarCases);

  screenMatrix('room/readiness-overlay', (tester, c, s) async {
    await pumpAtSize(
      tester,
      Scaffold(
        body: ReadinessOverlay(
          headline: 'Waiting for everyone to load $_longName',
          members: _members(8),
          media: _media,
          selfId: 'me',
          selfIsHost: true,
          onLocateFile: () {},
          onKick: (_) {},
          onStartWithout: () {},
          startWithoutLabel: 'Start without them',
          compact: _compact(c),
          premiumMembers: const {'u1', 'u3'},
        ),
      ),
      c,
      textScale: s,
    );
    await finishCase(tester);
  });

  for (final layout in FacecamLayout.values) {
    screenMatrix('room/facecams-${layout.name}', (tester, c, s) async {
      final av = LiveKitService(roomId: 'room-1', avLevel: .video);
      await av.connect();
      await pumpAtSize(
        tester,
        Scaffold(
          body: SafeArea(
            child: FacecamRail(
              av: av,
              present: _members(6),
              selfId: 'me',
              layout: layout,
              onHide: () {},
              premiumMembers: const {'u1'},
            ),
          ),
        ),
        c,
        textScale: s,
      );
      await finishCase(tester);
      av.dispose();
    });
  }

  screenMatrix('room/banners-stacked', (tester, c, s) async {
    await pumpAtSize(
      tester,
      Scaffold(
        // RoomScreen caps its banner stack and scrolls it (`_bannerStack`);
        // room_screen_matrix_test covers the real placement.
        body: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              spacing: 8,
              children: [
                const PTBanner(
                  kind: .warning,
                  icon: Symbols.wifi_off_rounded,
                  title: 'Reconnecting…',
                  subtitle: 'Hang tight, we lost the room for a second.',
                  spinIcon: true,
                  showActivity: true,
                ),
                PTBanner(
                  kind: .error,
                  icon: Symbols.movie_rounded,
                  title: 'That is not the same file as the host',
                  subtitle: 'The room is watching ${_media.name}; you opened Some_Other_File.mp4.',
                  trailing: TextButton(onPressed: () {}, child: const Text('Locate')),
                  onDismiss: () {},
                ),
                PTBanner(
                  kind: .info,
                  icon: Symbols.timer_rounded,
                  title: 'Five minutes left in this room',
                  subtitle: 'Extend it to keep watching together.',
                  trailing: TextButton(onPressed: () {}, child: const Text('Extend')),
                  onDismiss: () {},
                ),
              ],
            ),
          ),
        ),
      ),
      c,
      textScale: s,
    );
    await finishCase(tester);
  });

  screenMatrix('room/reaction-strip', (tester, c, s) async {
    await pumpAtSize(
      tester,
      _bottom(
        ReactionStrip(
          open: true,
          assets: ReactionAssets(),
          onPick: (_) {},
          reactions: kReactions,
          hasMore: true,
          onMore: () {},
          compact: _compact(c),
        ),
      ),
      c,
      textScale: s,
    );
    await finishCase(tester);
  });

  screenMatrix('room/chat-docked', (tester, c, s) async {
    final sync = _sync();
    await pumpAtSize(
      tester,
      Scaffold(
        body: SafeArea(
          child: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(width: 340, child: _chatPanel(sync, embedded: false)),
          ),
        ),
      ),
      c,
      textScale: s,
    );
    await finishCase(tester);
    sync.dispose();
  });

  screenMatrix('room/chat-embedded', (tester, c, s) async {
    final sync = _sync();
    await pumpAtSize(
      tester,
      Scaffold(body: SafeArea(child: _chatPanel(sync, embedded: true))),
      c,
      textScale: s,
    );
    await finishCase(tester);
    sync.dispose();
  });

  // The picker in each presentation: inline under the composer on touch (in
  // the keyboard's place), a popover above it on pointer.
  for (final embedded in [false, true]) {
    screenMatrix('room/chat-emoji-picker-${embedded ? 'embedded' : 'docked'}', (
      tester,
      c,
      s,
    ) async {
      final sync = _sync();
      final panel = _chatPanel(sync, embedded: embedded);
      await pumpAtSize(
        tester,
        Scaffold(
          body: SafeArea(
            child: embedded
                ? panel
                : Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(width: 340, child: panel),
                  ),
          ),
        ),
        c,
        textScale: s,
      );
      await tester.tap(
        find.byWidgetPredicate((w) => w is Tooltip && (w.message?.startsWith('Emoji (') ?? false)),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await finishCase(tester);
      sync.dispose();
    });
  }
}
