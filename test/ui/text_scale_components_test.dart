import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/rewards/rewards_models.dart';
import 'package:synctogether/rewards/widgets/unlock_toast.dart';
import 'package:synctogether/rooms/room_models.dart';
import 'package:synctogether/rooms/widgets/reaction_overlay.dart';
import 'package:synctogether/rooms/widgets/reaction_strip.dart';
import 'package:synctogether/rooms/widgets/readiness_overlay.dart';
import 'package:synctogether/rooms/widgets/room_chat_panel.dart';
import 'package:synctogether/rooms/widgets/room_control_bar.dart';
import 'package:synctogether/rooms/widgets/room_overflow_menu.dart';
import 'package:synctogether/sync/sync_service.dart';
import 'package:synctogether/ui/buttons.dart';

import '../support/screen_matrix.dart';
import '../sync/fakes.dart';

/// The three shapes §2D names: the smallest phone, phone landscape, desktop.
final _cases = [
  for (final name in ['phone-small', 'phone-land', 'desktop'])
    kScreenMatrix.firstWhere((c) => c.name == name),
];

bool _compact(ScreenCase c) => c.size.width < 840 || c.size.height < 480;

final _members = [
  for (final (i, name) in ['Alexandria Montgomery-Smythe', 'Bo', 'Riya Chakraborty'].indexed)
    PresentMember(
      userId: 'u$i',
      displayName: name,
      role: i == 0 ? 'host' : 'member',
      joinedAt: DateTime(2026, 1, 1, 10, i),
    ),
];

RoomControlBarActions _actions() => RoomControlBarActions(
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
);

Widget _bottom(Widget child) => Scaffold(
  body: Align(
    alignment: .bottomCenter,
    child: Padding(padding: const EdgeInsets.all(8), child: child),
  ),
);

/// The harness resets the platform override in a tear-down, which runs after
/// the binding's invariant check; clear it inside the body instead.
void _matrix(
  String name,
  Future<void> Function(WidgetTester, ScreenCase, double) body, {
  List<ScreenCase>? cases,
}) => screenMatrix(name, cases: cases, (t, c, s) async {
  await body(t, c, s);
  debugDefaultTargetPlatformOverride = null;
});

void _touch(String name, Future<void> Function(WidgetTester) body) => testWidgets(name, (t) async {
  await body(t);
  debugDefaultTargetPlatformOverride = null;
});

void main() {
  _matrix('RoomControlBar', cases: _cases, (tester, c, s) async {
    await pumpAtSize(
      tester,
      _bottom(
        RoomControlBar(
          playing: true,
          position: const Duration(hours: 1, minutes: 2, seconds: 3),
          duration: const Duration(hours: 2, minutes: 14, seconds: 55),
          volume: 0.5,
          micOn: false,
          camOn: false,
          avAvailable: true,
          camAvailable: true,
          compact: _compact(c),
          transportEnabled: false,
          transportHint: 'Waiting for everyone to load Movie.2005.1080p.BluRay.x264.mkv',
          actions: _actions(),
        ),
      ),
      c,
      textScale: s,
    );
    expectNoOverflow(tester);
  });

  _matrix('ReactionStrip', cases: _cases, (tester, c, s) async {
    await pumpAtSize(
      tester,
      _bottom(
        ReactionStrip(
          open: true,
          assets: ReactionAssets(),
          onPick: (_) {},
          hasMore: true,
          onMore: () {},
          compact: _compact(c),
        ),
      ),
      c,
      textScale: s,
    );
    expectNoOverflow(tester);
    expect(tester.getSize(find.byType(ReactionStrip)).width, lessThanOrEqualTo(c.size.width));
  });

  _matrix('RoomChatPanel', cases: _cases, (tester, c, s) async {
    final sync = SyncService(
      FakeSyncPlayer(),
      room: testRoom(),
      profile: testProfile('me'),
      role: 'host',
      backend: FakeSyncBackend(),
    );
    await pumpAtSize(
      tester,
      Scaffold(
        body: RoomChatPanel(
          sync: sync,
          messages: [
            ChatMessage(
              senderId: 'other',
              displayName: 'Alexandria Montgomery-Smythe',
              content: 'This is a long message that has to wrap over several lines at 2x',
              sentAt: DateTime.utc(2026, 7, 31, 16),
            ),
            ChatMessage(
              senderId: 'me',
              displayName: 'Me',
              content: 'Supercalifragilisticexpialidociouswordwithoutanyspaces',
              sentAt: DateTime.utc(2026, 7, 31, 16, 1),
            ),
          ],
          typingNames: const ['Alexandria Montgomery-Smythe', 'Riya Chakraborty', 'Bo'],
          watchingCount: 12,
          onClose: () {},
          onSend: (_) {},
          onCopied: () {},
        ),
      ),
      c,
      textScale: s,
    );
    expectNoOverflow(tester);

    // The composer grows with its text, but stops at four lines.
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.maxLines, 4);
    sync.dispose();
  });

  _matrix('ReadinessOverlay', cases: _cases, (tester, c, s) async {
    await pumpAtSize(
      tester,
      Scaffold(
        body: ReadinessOverlay(
          headline: 'Waiting for everyone to load Movie.2005.1080p.BluRay.x264.mkv',
          members: _members,
          media: RoomMedia.none,
          selfId: 'u0',
          selfIsHost: true,
          onLocateFile: () {},
          onKick: (_) {},
          onStartWithout: () {},
          compact: _compact(c),
        ),
      ),
      c,
      textScale: s,
    );
    expectNoOverflow(tester);
  });

  _matrix('Overflow menu', cases: _cases, (tester, c, s) async {
    final data = ValueNotifier<RoomMenuData?>(
      RoomMenuData(
        members: [
          for (final m in _members)
            RoomMember(roomId: 'r', userId: m.userId, role: m.role, joinedAt: m.joinedAt),
        ],
        present: _members,
        media: RoomMedia.none,
        transportLock: false,
        selfId: 'u0',
        selfIsHost: true,
      ),
    );
    await pumpAtSize(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showRoomOverflowMenu(
              context: context,
              data: data,
              onCopyInvite: () {},
              onLeave: () {},
              onEndRoom: () {},
              onExtendRoom: () {},
              onTransportLockChanged: (_) {},
              onKick: (_) {},
            ),
            child: const Text('open'),
          ),
        ),
      ),
      c,
      textScale: s,
    );
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 400));
    expectNoOverflow(tester);
  });

  _matrix('UnlockCard', cases: _cases, (tester, c, s) async {
    await pumpAtSize(
      tester,
      Scaffold(
        body: Center(
          child: UnlockCard(
            achievement: const Achievement(
              id: 'marathon',
              title: 'Marathon Night Champion',
              description: 'Watched together for four hours in one sitting without a break',
              icon: 'bolt',
              grade: RewardGrade.gold,
              metric: 'x',
              threshold: 1,
              unlocked: true,
            ),
          ),
        ),
      ),
      c,
      textScale: s,
    );
    expectNoOverflow(tester);
    expect(
      tester.getSize(find.byType(UnlockCard)).width,
      lessThanOrEqualTo(c.size.width - 32 + 0.01),
    );
  });

  group('touch targets', () {
    Widget small() => Center(
      child: PTIconButton(icon: Icons.close, size: 32, onPressed: () {}),
    );

    _touch('a 32px icon button hit-tests at 44 on touch', (tester) async {
      var taps = 0;
      await pumpAtSize(
        tester,
        Center(
          child: PTIconButton(icon: Icons.close, size: 32, onPressed: () => taps++),
        ),
        _cases.first,
      );
      expect(tester.getSize(find.byType(PTIconButton)), const Size(44, 44));
      // A tap 5px outside the 32px disc, inside the 44px target, still lands.
      final centre = tester.getCenter(find.byType(PTIconButton));
      await tester.tapAt(centre + const Offset(20, 0));
      expect(taps, 1);
    });

    _touch('pointer layout metrics are unchanged', (tester) async {
      await pumpAtSize(tester, small(), _cases.last);
      expect(tester.getSize(find.byType(PTIconButton)), const Size(32, 32));
    });

    _touch('a short PTButton is 44 tall on touch, its own height on pointer', (tester) async {
      Widget b() => Center(
        child: PTButton(label: 'Go', height: 34, expand: false, onPressed: () {}),
      );
      await pumpAtSize(tester, b(), _cases.first);
      expect(tester.getSize(find.byType(PTButton)).height, 44);
      await pumpAtSize(tester, b(), _cases.last);
      expect(tester.getSize(find.byType(PTButton)).height, 34);
    });
  });
}
