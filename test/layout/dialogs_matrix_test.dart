import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/analytics_disclosure_dialog.dart';
import 'package:synctogether/auth/turnstile_dialog.dart';
import 'package:synctogether/auth/webview_runtime.dart';
import 'package:synctogether/av/av_settings_dialog.dart';
import 'package:synctogether/av/device_preference_service.dart';
import 'package:synctogether/player/chooser_dialog.dart';
import 'package:synctogether/player/mode_selection_dialog.dart';
import 'package:synctogether/player/subtitles/subtitle_style_dialog.dart';
import 'package:synctogether/player/youtube_url_dialog.dart';
import 'package:synctogether/profile/entitlement_service.dart';
import 'package:synctogether/profile/media_quota_dialog.dart';
import 'package:synctogether/profile/profile_models.dart';
import 'package:synctogether/profile/profile_service.dart';
import 'package:synctogether/rewards/rewards_logic.dart';
import 'package:synctogether/rewards/rewards_service.dart';
import 'package:synctogether/rewards/widgets/recap_card.dart';
import 'package:synctogether/rewards/widgets/shared_recaps_dialog.dart';
import 'package:synctogether/rooms/reactions.dart';
import 'package:synctogether/rooms/room_models.dart';
import 'package:synctogether/rooms/widgets/emoji_quick_bar.dart';
import 'package:synctogether/rooms/widgets/ended_room_dialog.dart';
import 'package:synctogether/rooms/widgets/extend_room_dialog.dart';
import 'package:synctogether/rooms/widgets/kick_member_dialog.dart';
import 'package:synctogether/rooms/widgets/media_sharing_prompt_dialog.dart';
import 'package:synctogether/rooms/widgets/play_shared_video_dialog.dart';
import 'package:synctogether/rooms/widgets/reaction_overlay.dart';
import 'package:synctogether/rooms/widgets/reaction_strip.dart';
import 'package:synctogether/rooms/widgets/report_dialog.dart';
import 'package:synctogether/rooms/widgets/room_overflow_menu.dart';
import 'package:synctogether/rooms/widgets/shortcuts_dialog.dart';
import 'package:synctogether/sync/sync_service.dart';

import '../support/screen_matrix.dart';
import 'layout_support.dart';

final _room = Room(
  id: 'room-1',
  code: 'ABC123',
  name: 'A movie night with a name long enough to wrap twice',
  createdBy: 'user-1',
  createdAt: DateTime(2026, 9, 1),
  durationMinutes: 60,
  expiresAt: DateTime(2026, 9, 1, 1),
);

const _longName = 'Maximiliana Featherstonehaugh-Wolfeschlegel';

List<lk.MediaDevice> _devices(String kind, String label) => [
  for (var i = 0; i < 4; i++)
    lk.MediaDevice('$kind-$i', '$label $i with a very descriptive driver name', kind, null),
];

RoomMenuData _menuData() {
  final joined = DateTime(2026, 9, 1);
  final ids = ['user-host', 'u2', 'u3', 'u4', 'u5', 'u6'];
  return RoomMenuData(
    members: [
      for (final (i, id) in ids.indexed)
        RoomMember(
          roomId: 'room-1',
          userId: id,
          role: i == 0 ? 'host' : 'member',
          joinedAt: joined,
        ),
    ],
    present: [
      for (final (i, id) in ids.indexed)
        PresentMember(
          userId: id,
          displayName: i.isEven ? _longName : 'Sam $i',
          role: i == 0 ? 'host' : 'member',
          joinedAt: joined,
        ),
    ],
    media: RoomMedia.none,
    transportLock: false,
    selfId: 'user-host',
    selfIsHost: true,
  );
}

void main() {
  // livekit's `Hardware` singleton enumerates devices through flutter_webrtc
  // the first time anything touches it. With no plugin that throws
  // asynchronously, and a screenshot's `runAsync` gives the error room to
  // land inside whichever case got there first - so answer it with no devices.
  setUpAll(() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('FlutterWebRTC.Method'),
      (call) async => call.method == 'getSources' ? {'sources': <Object>[]} : null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('FlutterWebRTC.Event'),
      (_) async => null,
    );
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DevicePreferenceService.instance.init(await SharedPreferences.getInstance());
    ProfileService.instance.setProfileForTesting(
      const Profile(id: 'user-1', displayName: 'Alex', isGuest: false, email: 'a@b.co'),
    );
    EntitlementService.instance.setLimitsForTesting(TierLimits.fallback);
    RewardsService.instance = FakeRewardsService();
    PTWebView.runtimeMissing = true; // no platform webview in tests
  });
  tearDown(() {
    ProfileService.instance.setProfileForTesting(null);
    EntitlementService.instance.setLimitsForTesting(null);
    PTWebView.runtimeMissing = false;
  });

  void glass(String name, WidgetBuilder builder, {double width = 430}) {
    screenMatrix('dialog/$name', (tester, c, s) async {
      await pumpGlassDialog(tester, c, s, builder, width: width);
      await finishCase(tester);
    });
  }

  void opener(String name, void Function(BuildContext) open) {
    screenMatrix('dialog/$name', (tester, c, s) async {
      await pumpDialogOpener(tester, c, s, open);
      await finishCase(tester);
    });
  }

  glass('mode-selection', (_) => const ModeSelectionDialog());
  glass('youtube-url', (_) => const YouTubeUrlDialog());
  glass(
    'chooser',
    (_) => ChooserDialog<String>(
      type: 'Subtitles',
      values: const ['Off', 'English (SDH) - forced', 'Deutsch', 'Português (Brasil)', '日本語'],
      selected: 'Deutsch',
      onChosen: (_) {},
      onAddFromFile: () {},
      onStyle: () {},
    ),
  );
  opener('subtitle-style', (context) => showSubtitleStyleDialog(context));
  glass('shortcuts', (_) => const ShortcutsDialog(facecams: true), width: 520);
  glass('kick-member', (_) => const KickMemberDialog(displayName: _longName));
  glass(
    'extend-room',
    (_) => const ExtendRoomDialog(options: [15, 30, 60, 120, 240], headroomMinutes: 1200),
  );
  glass(
    'premium-tease',
    (_) => PremiumTeaseDialog(
      headline: 'Keep the party going longer',
      body: 'Premium rooms run for up to 24 hours and fit sixteen people.',
      perks: const [
        'Rooms that run for 24 hours',
        'Sixteen seats instead of eight',
        'Video facecams for everyone',
      ],
      onNotify: () {},
    ),
  );
  glass(
    'premium-tease-sign-in',
    (_) => PremiumTeaseDialog(
      headline: 'Sign in for more time',
      body: 'Guest rooms run for an hour and stop there.',
      perks: const ['Rooms that run for four hours, not one'],
      onSignIn: () {},
      onSignInApple: () {},
    ),
  );
  glass(
    'ended-room',
    (_) => EndedRoomDialog(room: _room, onStartFresh: () {}, onUpgrade: () {}, onDelete: () {}),
  );
  glass(
    'play-shared-video',
    (_) => const PlaySharedVideoDialog(videoId: 'J-95Mhipb98', sharedBy: _longName),
  );
  opener('quick-emoji-editor', (ctx) => showQuickBarEditor(ctx, initialSlot: 2));
  opener('media-quota', (ctx) => showMediaQuotaDialog(ctx));
  opener(
    'media-quota-blocked',
    (ctx) => showMediaQuotaDialog(
      ctx,
      quotaContext: const MediaQuotaContext(
        reason: .singleFileLimitExceeded,
        fileName: 'Cosmic_Voyage_4K.mkv',
        fileSize: 5368709120,
        maxBytes: 2147483648,
      ),
    ),
  );
  opener('analytics-disclosure', (ctx) => showAnalyticsDisclosure(ctx));
  opener(
    'report',
    (ctx) => showReportDialog(
      ctx,
      targetName: _longName,
      roomCode: 'ABC123',
      messageSnippet: 'A long-ish message that is being reported for moderation review by the team',
    ),
  );
  opener(
    'media-sharing-prompt',
    (ctx) => showMediaSharingPromptDialog(
      context: ctx,
      fileName: 'A_Very_Long_File_Name_For_The_Director_s_Cut_2160p_HDR10.mkv',
      fileSize: 4294967296,
    ),
  );
  opener('turnstile', (ctx) => showTurnstileDialog(ctx));
  opener(
    'av-settings',
    (ctx) => showAvSettingsDialog(
      ctx,
      enumerateAudioInputs: () async => _devices('audioinput', 'Microphone'),
      enumerateVideoInputs: () async => _devices('videoinput', 'Camera'),
      enumerateAudioOutputs: () async => _devices('audiooutput', 'Speakers'),
      onTestSound: (_) async {},
    ),
  );
  opener('shared-recaps', (ctx) => showSharedRecapsDialog(ctx));
  opener(
    'recap',
    (ctx) => showRecapDialog(
      context: ctx,
      selfId: 'user-1',
      people: const {
        'user-1': RecapPerson(userId: 'user-1', displayName: 'Alex'),
        'u2': RecapPerson(userId: 'u2', displayName: _longName),
        'u3': RecapPerson(userId: 'u3', displayName: 'Sam'),
      },
      recap: const SessionRecap(
        roomId: 'room-1',
        length: Duration(hours: 2, minutes: 49),
        peakMembers: 6,
        messages: 214,
        reactions: 1532,
        modes: {'local', 'youtube'},
        facecamUsed: true,
        cleanGate: true,
        participantIds: ['user-1', 'u2', 'u3'],
        topEmoji: '🍿',
        superlatives: [
          Superlative(key: SuperlativeKey.reactions, userId: 'u2', displayName: _longName),
          Superlative(key: SuperlativeKey.chat, userId: 'u3', displayName: 'Sam'),
          Superlative(key: SuperlativeKey.pauser, userId: 'user-1', displayName: 'Alex'),
        ],
      ),
    ),
  );
  // Opened the way RoomScreen._showReactionPicker opens it: a 420-wide glass
  // dialog, which supplies the gutter, keyboard-aware height and scrolling.
  glass(
    'reaction-picker',
    (_) => ReactionPickerDialog(reactions: kAllReactions, assets: ReactionAssets()),
    width: 420,
  );
  opener(
    'room-overflow-menu',
    (ctx) => showRoomOverflowMenu(
      context: ctx,
      data: ValueNotifier(_menuData()),
      onCopyInvite: () {},
      onLeave: () {},
      onEndRoom: () {},
      onExtendRoom: () {},
      onReportConcern: () {},
      onTransportLockChanged: (_) {},
      onKick: (_) {},
      onAssignHost: (_) {},
      onReportMember: (_) {},
    ),
  );
}
