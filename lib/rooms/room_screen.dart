import 'dart:async';

import '../ui/booth_icons.g.dart';

import 'dart:io';
import 'dart:math' as math;

import 'package:fast_file_picker/fast_file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as p;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:synctogether/env.dart';
import 'package:synctogether/feedback/capture/media_details.dart';
import 'package:synctogether/feedback/capture/media_probe.dart';
import 'package:synctogether/feedback/capture/probes.dart';
import 'package:synctogether/feedback/shake_to_report.dart';
import 'package:synctogether/feedback/discovery/discovery_logic.dart' show NudgeReason;
import 'package:synctogether/feedback/discovery/discovery_triggers.dart';
import 'package:synctogether/feedback/discovery/review_prompt.dart';
import 'package:synctogether/analytics.dart';
import 'package:synctogether/auth/auth_service.dart';

import 'package:synctogether/av/device_preference_service.dart';
import 'package:synctogether/av/background_call.dart';
import 'package:synctogether/av/livekit_service.dart';
import 'package:synctogether/av/video_trial.dart';
import 'package:synctogether/diagnostics.dart';
import 'package:synctogether/pairing/pair_logic.dart';
import 'package:synctogether/pairing/pair_service.dart';
import 'package:synctogether/platform.dart';
import 'package:synctogether/player/local_video.dart';
import 'package:synctogether/player/local_video_chooser.dart';
import 'package:synctogether/player/media_file_types.dart';
import 'package:synctogether/player/photo_exports.dart';
import 'package:synctogether/rooms/our_room_media.dart';
import 'package:synctogether/rooms/widgets/shared_copy_expired_banner.dart';
import 'package:synctogether/rooms/widgets/streaming_fallback_banner.dart';
import 'package:synctogether/player/photo_picker.dart';
import 'package:synctogether/player/recent_format.dart';
import 'package:synctogether/player/recent_videos.dart';
import 'package:synctogether/player/mode_selection_dialog.dart';
import 'package:synctogether/player/subtitles/subtitle_applier.dart';
import 'package:synctogether/player/track_label.dart';
import 'package:synctogether/player/video_surface.dart';
import 'package:synctogether/player/youtube/pt_youtube_controller.dart';
import 'package:synctogether/player/youtube/pt_youtube_embed.dart';
import 'package:synctogether/player/youtube/youtube_links.dart';
import 'package:synctogether/player/youtube_url_dialog.dart';
import 'package:synctogether/profile/entitlement_service.dart';
import 'package:synctogether/profile/media_quota_dialog.dart';
import 'package:synctogether/profile/profile_models.dart';
import 'package:synctogether/profile/profile_service.dart';
import 'package:synctogether/rooms/local_media_store.dart';
import 'package:synctogether/rooms/media_sharing_cache.dart';
import 'package:synctogether/rooms/media_sharing_service.dart';
import 'package:synctogether/player/stream/stream_health.dart' show formatMbps;
import 'package:synctogether/player/stream/stream_notice.dart' show StreamNotice;
import 'package:synctogether/player/stream/stream_session.dart';
import 'package:synctogether/player/stream/stream_tuning.dart';
import 'package:synctogether/rooms/reactions.dart';
import 'package:synctogether/rooms/room_dependencies.dart';
import 'package:synctogether/rewards/rewards_logic.dart';
import 'package:synctogether/rewards/rewards_models.dart';
import 'package:synctogether/rewards/rewards_service.dart';
import 'package:synctogether/rewards/widgets/recap_card.dart';
import 'package:synctogether/rooms/room_models.dart';
import 'package:synctogether/rooms/moderation_service.dart';
import 'package:synctogether/rooms/widgets/report_dialog.dart';
import 'package:synctogether/rooms/room_service.dart';
import 'package:synctogether/rooms/roster_fold.dart';
import 'package:synctogether/rooms/upload_source.dart';
import 'package:synctogether/rooms/widgets/extend_room_dialog.dart';
import 'package:synctogether/rooms/widgets/facecam_rail.dart';
import 'package:synctogether/rooms/widgets/kick_member_dialog.dart';
import 'package:synctogether/rooms/widgets/media_sharing_prompt_dialog.dart';
import 'package:synctogether/rooms/widgets/play_shared_video_dialog.dart';
import 'package:synctogether/rooms/widgets/reaction_overlay.dart';
import 'package:synctogether/rooms/widgets/reaction_strip.dart';
import 'package:synctogether/rooms/widgets/readiness_overlay.dart';
import 'package:synctogether/rooms/widgets/room_av_device_selector.dart';
import 'package:synctogether/rooms/widgets/room_banner_stack.dart';
import 'package:synctogether/rooms/widgets/room_chat_overlay.dart';
import 'package:synctogether/rooms/widgets/room_chat_panel.dart';
import 'package:synctogether/rooms/widgets/room_control_bar.dart';
import 'package:synctogether/rooms/widgets/room_desktop_layout.dart';
import 'package:synctogether/rooms/widgets/room_ended_dialog.dart';
import 'package:synctogether/rooms/widgets/room_pill.dart';
import 'package:synctogether/rooms/widgets/room_bar_form.dart';
import 'package:synctogether/rooms/widgets/room_mobile_layout.dart';
import 'package:synctogether/rooms/widgets/room_overflow_menu.dart';
import 'package:synctogether/rooms/widgets/room_track_chooser_dialog.dart';
import 'package:synctogether/rooms/widgets/room_video_surface.dart';
import 'package:synctogether/rooms/widgets/sharing_progress_indicator.dart';
import 'package:synctogether/rooms/widgets/shortcuts_dialog.dart';
import 'package:synctogether/sync/sync_events.dart';
import 'package:synctogether/sync/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/ui/banners.dart';
import 'package:synctogether/ui/booth.dart';
import 'package:synctogether/ui/coach_target.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/feedback/bug_report.dart';
import 'package:synctogether/feedback/ui/bug_report_button.dart';
import 'package:synctogether/ui/cinema_marquee_bar.dart';
import 'package:synctogether/ui/error_boundary.dart';
import 'package:synctogether/ui/popover.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/identity.dart';
import 'package:synctogether/ui/loader.dart';
import 'package:synctogether/ui/marquee.dart';
import 'package:synctogether/ui/logo.dart';
import 'package:synctogether/ui/pt_motion.dart';
import 'package:synctogether/ui/pt_theme.dart';
import 'package:synctogether/ui/responsive.dart';
import 'package:synctogether/ui/system_ui.dart';
import 'package:synctogether/window/app_window.dart';

const bool kDemoMode = bool.fromEnvironment('DEMO_MODE', defaultValue: false);

/// Height of the dark band behind the floating controls: the bar (24 margin +
/// ~110) plus a fade. Capped at 30% of the video on small surfaces.
const kControlScrimHeight = 180.0;

/// How far libass's subtitles rise while the control bar shows over the
/// picture: the bar plus its margin, in logical pixels.
const kSubtitleLiftPx = 104.0;

class RoomScreen extends StatefulWidget {
  const RoomScreen({
    super.key,
    required this.roomId,
    this.player,
    this.initialChatOpen = false,
    this.initialDialogOpen,
    this.dependencies = RoomDependencies.real,
  });

  final String roomId;
  final Player? player;
  final bool initialChatOpen;
  final String? initialDialogOpen;

  /// Test seam; see [RoomDependencies]. Production always uses the default.
  final RoomDependencies dependencies;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

/// ", or email <address>" when this build has a support address, else nothing.
String _orEmailSupport() {
  final email = Env.supportEmail;
  return email == null ? '' : ', or email $email';
}

class _RoomScreenState extends State<RoomScreen> with AppWindowListener, TickerProviderStateMixin {
  Player? _ownedPlayer;
  Player get _player => widget.player ?? _ownedPlayer!;

  /// Hoists the video surface (and with it the YouTube platform view) across
  /// layout builders: phone↔tablet, fold↔unfold and rotation all change the
  /// tree shape around it, and a remounted webview restarts playback.
  final _videoKey = GlobalKey(debugLabel: 'room-video');

  /// The chat draft lives here, not in the panel. The panel is deliberately
  /// *not* hoisted under a GlobalKey like the video: its composer owns an
  /// OverlayPortal (the emoji popover), and reparenting that subtree between
  /// layouts trips `_attachTarget == this` / `_elements.contains(element)`.
  /// Remounting is cheap; losing a half-typed message is not.
  final _chatDraft = TextEditingController();

  /// Whether the phone roster strip is folded; owned here so it outlives the
  /// chat panel, which remounts when the layout class changes.
  final _rosterFold = RosterFold();

  /// The chat's inline emoji picker holds the soft keyboard's place (touch).
  bool _chatPickerUp = false;
  final _keyboardMemory = SoftKeyboardMemory();

  /// Whether the system bars are hidden for immersive playback; see
  /// [_wantsImmersive].
  bool _immersive = false;
  bool _immersiveCheckPending = false;

  PTLayout? _lastLayout;
  PTFoldAxis? _lastFoldAxis;

  /// Null only when [RoomDependencies.videoView] replaces the default view,
  /// which is the only reader.
  VideoController? _controller;
  SubtitleStyleApplier? _subtitleStyle;
  VideoController get controller => _controller!;

  Room? _room;
  SyncService? _sync;
  void Function()? _unregisterFeedbackProbes;
  LiveKitService? _av;
  final _backgroundCall = BackgroundCall();

  /// The room's video trial (free rooms only). The end is the room row's
  /// `video_trial_ends_at`, adopted from the row and the broadcast alike.
  DateTime? _videoTrialEndsAt;
  Timer? _videoTrialTimer;
  bool _videoTrialRefused = false;
  bool _startingVideoTrial = false;
  bool _videoTrialEndedNote = false;
  Timer? _videoTrialNoteTimer;
  List<RoomMember> _members = const [];
  List<PresentMember> _present = const [];
  Set<String> _premiumMembers = const {};
  Map<String, AvatarFrame> _memberFrames = const {};
  Set<String> _resolvedTierIds = const {};
  bool _tierFetchInFlight = false;
  bool _loading = true;

  PlaybackMode _mode = .local;
  String? _youtubeUrl;
  PTYouTubeController? _youtubeController;
  bool _youtubeWasPlaying = false;
  bool _youtubeWasAdPlaying = false;
  bool _isCatchingUp = false;
  Timer? _catchUpTimeoutTimer;
  // YT sync uses an *intent* model: iframe state transitions land 200-500 ms
  // after commands, far outside SyncService's 100 ms settle window.
  // `_ytIntendedPlaying` is the agreed play state; the player listener only
  // broadcasts transitions that DIVERGE from it (i.e. the user acted on the
  // iframe directly).
  bool _ytIntendedPlaying = false;
  // Remote commands that arrive before the iframe is ready are queued and
  // flushed on the first ready event (late-joiner state_response).
  Duration? _pendingYtSeek;
  bool? _pendingYtPlay;
  // Ignore the transient playing-blip caused by seekTo-then-pause.
  DateTime _ytEventSuppressUntil = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isModeSelectionDialogOpen = false;
  bool _isYouTubeUrlDialogOpen = false;
  // A remote mode_switch popping the URL dialog must not trip the
  // "cancelled and still idle: re-ask" fallback.
  bool _urlDialogDismissedRemotely = false;

  bool _playing = false;
  bool _buffering = false;

  /// The playhead. A notifier rather than state: the local player reports
  /// several times a second, and a `setState` per report rebuilt this entire
  /// screen - chat, facecams, overlays - for a value only the control bar
  /// draws. The bar listens to it directly (see [_controlBar]).
  final _positionNotifier = ValueNotifier<Duration>(Duration.zero);
  Duration get _position => _positionNotifier.value;
  set _position(Duration value) => _positionNotifier.value = value;
  Duration _duration = Duration.zero;
  double _volume = 1.0;

  final _messages = <ChatMessage>[];

  /// Blocks are account-scoped and live on [ModerationService]; this screen
  /// only reads them. Keying on the user id rather than the display name
  /// matters: two people can share a name, and a blocked person could
  /// otherwise walk straight back into the feed by renaming themselves.
  Set<String> get _blockedUsers => ModerationService.instance.blockedIds;

  List<ChatMessage> get _visibleMessages => _blockedUsers.isEmpty
      ? _messages
      : _messages.where((m) => !_blockedUsers.contains(m.senderId)).toList();

  /// Presence minus anyone blocked - keeps a blocked person's facecam tile and
  /// roster entry out of sight too, not just their chat.
  List<PresentMember> get _visiblePresent => _blockedUsers.isEmpty
      ? _present
      : _present.where((m) => !_blockedUsers.contains(m.userId)).toList();
  List<String> _typingNames = const [];
  bool _chatOpen = false;
  int _unread = 0;
  bool _camsVisible = true;
  bool _privacyHidden = false;
  bool _chatOpenBeforePrivacy = false;
  bool _micBeforePrivacy = false;
  bool _camBeforePrivacy = false;
  // ignore: unused_field, prefer_final_fields
  bool _micBeforeSolo = false;
  // ignore: unused_field, prefer_final_fields
  bool _camBeforeSolo = false;

  final _reactionAssets = ReactionAssets();
  bool _reactOpen = false;
  Stream<ReactionEvent>? _reactionStream;

  // Drives the chat panel's slide+fade in the overlay layouts *and* the
  // cross-fade of what it covers (facecam rail, floating bubbles), so the two
  // halves of the swap stay in lockstep. `_chatOpen` flips immediately; the
  // panel is what lags behind it.
  static const _chatMotion = Durations.medium1;
  late final AnimationController _chatAnim = AnimationController(
    vsync: this,
    duration: _chatMotion,
  );
  late final CurvedAnimation _chatCurve = CurvedAnimation(
    parent: _chatAnim,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeOutCubic,
  );

  // Attribution toast for remote play/pause/seek ("«name» jumped to 12:40") so
  // playback jumps don't read as glitches. Kept mounted (text persists) while
  // it fades so the fade-out actually renders.
  String _actionToastText = '';
  bool _actionToastVisible = false;
  bool _actionToastArrival = false;
  Timer? _actionToastTimer;

  // Floating chat bubbles (last 3) shown over the video while the panel is
  // closed (desktop/landscape only - portrait chat is always visible). Each
  // self-expires; timers are tracked so they can be cancelled on dispose, and
  // on open (where the bubbles instead fade out under the arriving panel).
  final _overlayChat = <ChatMessage>[];
  final _overlayChatTimers = <Timer>{};

  /// Bubbles that have timed out and are playing their exit. They stay in
  /// [_overlayChat] until the fade finishes - removing them on the timer alone
  /// is what made them vanish mid-sentence.
  final _expiringChat = <ChatMessage>{};

  // Double-tap skip feedback (touch layouts): -1 flashes the left −10s label,
  // 1 the right +10s, 0 none.
  int _skipFlash = 0;
  Timer? _skipFlashTimer;

  // OS-window fullscreen (desktop only). Kept in sync with the actual window
  // via WindowListener so Esc/toggle never desync from a native fullscreen.
  bool _fullscreen = false;

  // Floating chrome (topbar + control bar) in overlay layouts (desktop/landscape).
  // Controls stay visible deterministically until manually collapsed (H or collapse button).
  bool _controlsVisible = true;
  bool _cursorVisible = true;
  Timer? _controlsHideTimer;
  Timer? _cursorHideTimer;

  /// Portrait with the keyboard (or the inline emoji picker) up: the transport
  /// leaves its row and floats over the picture's bottom edge, so the picture
  /// keeps the height the bar took. It shows when the keys rise, hides itself a
  /// few seconds into playback, and stays up while paused.
  bool _kbBarVisible = true;
  bool _kbBarWasUp = false;
  Timer? _kbBarTimer;
  double _volumeBeforeMute = 1.0;
  final _shortcutFocus = FocusNode();

  Timer? _countdownTimer;
  Duration _timeLeft = Duration.zero;
  bool _warningDismissed = false;
  bool _dateNightBannerDismissed = false;
  bool _connected = true;
  bool _ended = false;
  Timer? _idleSourceTimer;
  // True until the first source decision lands (the chooser opens, or a remote
  // mode_switch beats it): keeps the video area in its loading state instead of
  // showing an empty black frame for the whole state-sync window. One-shot.
  bool _awaitingFirstSource = true;
  bool _hasPromptedInitialSource = false;

  RoomMedia _canonicalMedia = RoomMedia.none;
  String? _localFileName;
  bool _mismatchDismissed = false;

  /// A rejoin found the remembered local copy gone and fell back to streaming
  /// the host's shared copy: say so once, quietly (info banner, never error).
  bool _streamingFallbackNotice = false;

  /// The "shared copy was removed" note (Our Room) was dismissed for this visit.
  bool _copyExpiredDismissed = false;

  bool _resumeAttempted = false;

  /// A shared-copy stream is being opened, so a second "it is ready" signal does not start another.
  bool _startingSharedStream = false;
  bool _extending = false;
  final _resuming = ValueNotifier<bool>(false);
  String? _evictionReason;
  Timer? _positionWriteTimer;
  Duration? _lastWrittenPosition;
  int _positionWriteFailures = 0;
  static const _kPositionWriteFailureReport = 3;

  // Own readiness inputs. `_updateReadiness` derives a ReadyStatus from these
  // and pushes it onto presence, which is what the gate reads.
  bool _isFilePickerOpen = false;
  bool _ytBufferReady = false;
  Timer? _ytBufferFallbackTimer;
  Timer? _localLoadWatchdog;
  bool _localLoadStalled = false;

  int? _ytErrorShownFor;

  // Media Sharing state
  final _mediaSharingService = MediaSharingService();
  bool _isStreamingRemoteSharedMedia = false;
  bool _isUploadingSharedMedia = false;

  /// File/codec pairs already explained, so one file does not snack twice.
  final _unsupportedCodecNoted = <String>{};
  bool _audioDeviceNoted = false;

  /// Bumped by every upload start. A newer start makes the server abort the
  /// older multipart as orphaned, so the older pipeline's parts 404 - that
  /// failure is the supersession working, not an upload that failed.
  int _uploadGeneration = 0;
  double _uploadFraction = 0.0;
  double _uploadSpeedBps = 0.0;
  int _uploadEtaSeconds = 0;
  String _uploadState = 'none';
  bool _recoveringStream403 = false;
  final _streamCache = MediaSharingCache();
  SharedStreamSession? _stream;

  /// The video this device has open in the player, with whatever platform
  /// access it holds (an iOS security scope). Released when it is replaced and
  /// when the room is left.
  LocalVideo? _localVideo;

  /// What the running (or last) upload reads from, to refuse the same source twice.
  String? _uploadingRef;

  /// The Recent entry for the open file, so its duration can be filled in once
  /// the player knows it, and the newest entry for the empty room's Reopen line.
  String? _recentId;
  RecentVideo? _lastRecent;
  StreamSubscription<bool>? _thumbWait;
  bool _localReadyPromptDismissed = false;
  Duration? _bufferPosition;
  StreamSubscription<List<lk.MediaDevice>>? _deviceChangeSub;

  GateState _gateState = GateState.indeterminate;

  // Readiness-overlay reveal. Driven only by `closed` - `indeterminate` must
  // render as usable, or the overlay flashes on every room entry. Out is
  // quicker than in on purpose: the payoff of the gate opening is *seeing the
  // video*, so don't make people wait for it.
  late final AnimationController _gateAnim = AnimationController(
    vsync: this,
    duration: PTMotion.panel,
    reverseDuration: PTMotion.state,
  );
  late final CurvedAnimation _gateCurve = CurvedAnimation(
    parent: _gateAnim,
    curve: PTMotion.enter,
    reverseCurve: PTMotion.exit,
  );

  /// The overlay is suppressed until the first source decision lands, so
  /// clearing that flag is also a gate-visibility edge.
  void _resolveFirstSource() {
    setState(() => _awaitingFirstSource = false);
    _syncGateReveal();
  }

  bool get _gateOverlayUp =>
      !_ended && (_gateState == GateState.closed || _selfBlocksGate) && !_awaitingFirstSource;

  void _syncGateReveal() {
    // `_selfBlocksGate` keeps the panel up for someone the host started
    // without: the room is playing, the gate is open, and they still have
    // nothing loaded - which is exactly when they need the locate button.
    if (_gateOverlayUp) {
      _gateAnim.forward();
    } else {
      _gateAnim.reverse();
    }
  }

  // The overflow menu is a Navigator route - a sibling subtree - so setState
  // here can never rebuild it. Everything it shows is pushed through this
  // notifier instead; null means "close now" (the room is over for us).
  final _menuData = ValueNotifier<RoomMenuData?>(null);

  /// The open overflow menu, if any. It is an overlay entry outside this
  /// page's PopScope, so back and dispose have to close it by hand.
  PTPopoverHandle? _overflowMenu;

  /// The room's canonical local file. Derived from [_canonicalMedia] rather
  /// than from whoever last broadcast `file_info`, so it survives host
  /// succession and is already correct for a late joiner.
  ({String name, Duration duration})? get _roomFile {
    if (_canonicalMedia.kind != .local) return null;
    final name = _canonicalMedia.name;
    if (name == null) return null;
    return (name: name, duration: _canonicalMedia.duration ?? Duration.zero);
  }

  final _subscriptions = <StreamSubscription>[];

  DateTime? _sessionStart;
  int _peakMembers = 0;
  int _messagesSent = 0;
  int _reactionsSent = 0;
  bool _facecamUsed = false;
  final _modesUsed = <String>{};
  bool _sessionReported = false;
  bool _playbackTracked = false;

  /// Per-member counters for the end-of-session recap.
  ///
  /// Everything here is already flowing past this screen - chat, reactions and
  /// user-initiated transport all carry a sender id - so the awards cost one
  /// increment each rather than any new traffic. Nothing about *what* was
  /// watched is kept, and none of it leaves the device unless the user shares.
  final _tallies = <String, MemberTally>{};

  /// Anyone who has held the readiness gate shut at least once this session.
  /// "Rock Solid" is the absence of a name from this set.
  final _gateBlockers = <String>{};

  final _emojiCounts = <String, int>{};

  /// Set by the heartbeat when it fires in the small hours, so the award is
  /// keyed to the user's own clock rather than the server's.
  bool _crossedTwoAm = false;

  bool _recapOffered = false;
  SessionRecap? _pendingRecap;
  Map<String, RecapPerson> _recapPeople = const {};
  String _recapSelfId = '';
  bool _firstPresenceSeen = false;

  /// Time the two partners spent in Our Room together, for the pair's history
  /// and streak. Only ever ticks in a room that belongs to a pair.
  final _together = TogetherClock();
  HeartbeatOutcome? _lastHeartbeatOutcome;

  MemberTally _tally(String userId, String displayName) {
    final tally = _tallies.putIfAbsent(
      userId,
      () => MemberTally(userId: userId, displayName: displayName),
    );
    if (displayName.isNotEmpty) tally.displayName = displayName;
    return tally;
  }

  /// Blocking has to take effect on the frame it happens - the guideline's
  /// word is "instantly" - so the screen rebuilds off the service rather than
  /// waiting for the next presence or chat event to bring it round.
  void _onBlocksChanged() {
    if (!mounted) return;
    // The overflow menu reads a published snapshot rather than this State, so
    // a block taken while it is open has to be pushed to it too.
    _publishMenuData();
    setState(() {});
  }

  void _toggleFacecam(String kind, bool on) {
    final av = _av;
    if (av == null) return;
    if (kind == 'cam' && on && !av.canPublishCamera) {
      if (_videoTrialPhase == .available) {
        unawaited(_startVideoTrial());
        return;
      }
      if (_startingVideoTrial) return;
      _snack('Cameras are a premium thing. This room is voice only.', kind: .info);
      return;
    }
    if (on && av.state == .unavailable) {
      // The wish is kept, so it applies by itself when AV comes back.
      _snack(kAvRestingMessage, kind: .info);
    }
    if (on) _facecamUsed = true;
    Analytics.instance.track('facecam_toggled', {'kind': kind, 'on': on});
    unawaited(kind == 'mic' ? av.setMicEnabled(on) : av.setCamEnabled(on));
  }

  VideoTrialPhase get _videoTrialPhase => videoTrialPhase(
    avLevel: _room?.avLevel ?? .none,
    endsAt: _videoTrialEndsAt,
    now: RoomService.instance.serverNow,
    refused: _videoTrialRefused,
  );

  /// The camera key offers the trial: a free room nobody has started it in,
  /// with AV up. Never offered to a guest room (no AV) or a video room.
  bool get _videoTrialOnOffer =>
      _av != null && !(_av!.canPublishCamera) && _videoTrialPhase == .available;

  /// The countdown chip shows only while this client can actually publish:
  /// a room that failed over to an endpoint without trials is voice-only, and
  /// a clock there would promise a camera the key cannot give.
  DateTime? get _trialChipEndsAt {
    final phase = _videoTrialPhase;
    if (phase != .running && phase != .finalStretch) return null;
    return (_av?.canPublishCamera ?? false) && !(_room?.avLevel.allowsVideo ?? false)
        ? _videoTrialEndsAt
        : null;
  }

  /// A human pressed the camera in a free room: start the trial, then the
  /// camera. Refusals map to copy; only an unexpected answer is reported.
  Future<void> _startVideoTrial() async {
    final av = _av;
    if (av == null || _startingVideoTrial) return;
    setState(() => _startingVideoTrial = true);
    try {
      final result = await RoomService.instance.startVideoTrial(widget.roomId);
      if (!mounted) return;
      trace(
        'video trial start answered',
        category: 'av',
        data: {'room_id': widget.roomId, 'status': result.status.name},
      );
      if (result.status.running && result.endsAt != null) {
        if (result.status == .started) {
          Analytics.instance.track('video_trial_started', {'room_id': widget.roomId});
        }
        _adoptVideoTrial(result.endsAt!, _sync?.userId ?? '', announce: false);
        await av.beginVideoTrial();
        if (!mounted) return;
        _facecamUsed = true;
        Analytics.instance.track('facecam_toggled', {'kind': 'cam', 'on': true});
        await av.setCamEnabled(true);
        if (mounted && result.status == .started) {
          final mins = (result.endsAt!.difference(RoomService.instance.serverNow).inSeconds / 60)
              .ceil();
          _snack(
            "Video's on for $mins minutes. Everyone here can turn their camera on.",
            kind: .info,
          );
        }
        return;
      }
      if (result.status == .dailyCap) {
        Analytics.instance.track('limit_hit', {'which': 'video_trial'});
      }
      if (result.status == .unknown) {
        reportNonFatal(
          StateError('start_video_trial returned an unknown status'),
          StackTrace.current,
          during: 'starting the video trial in room ${widget.roomId}',
        );
      }
      setState(() => _videoTrialRefused = true);
      _snack(result.status.message, kind: .info);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'starting the video trial in room ${widget.roomId}');
      if (mounted) _snack(VideoTrialStart.unknown.message, kind: .info);
    } finally {
      if (mounted) setState(() => _startingVideoTrial = false);
    }
  }

  /// A trial is running - from our own press, the broadcast, or the room row
  /// on (re)entry. Repeats of the same end are ignored.
  void _adoptVideoTrial(DateTime endsAt, String startedBy, {bool announce = true}) {
    if (!mounted || _videoTrialEndsAt == endsAt) return;
    final wasOffered = _videoTrialEndsAt == null;
    setState(() => _videoTrialEndsAt = endsAt);
    if (!endsAt.isAfter(RoomService.instance.serverNow)) return;
    _scheduleVideoTrialEnd();
    if (startedBy == (_sync?.userId ?? '')) return;
    unawaited(_av?.beginVideoTrial());
    if (announce && wasOffered && startedBy.isNotEmpty) {
      final who = _present.where((m) => m.userId == startedBy).firstOrNull?.displayName;
      _snack(
        '${who ?? 'Someone'} switched video on for $kVideoTrialOfferMinutes minutes.',
        kind: .info,
      );
    }
  }

  /// Arms the cutoff. At the end the camera goes off locally - the server's
  /// revocation is only the backstop - and the "faces off" note shows, with
  /// the upsell for the host. A trial that already ended arms nothing.
  void _scheduleVideoTrialEnd() {
    _videoTrialTimer?.cancel();
    final ends = _videoTrialEndsAt;
    if (ends == null) return;
    final left = ends.difference(RoomService.instance.serverNow);
    if (left <= Duration.zero) return;
    _videoTrialTimer = Timer(left, () {
      if (!mounted) return;
      final hadCamera = _av?.canPublishCamera ?? false;
      unawaited(_av?.endVideoTrial());
      trace('video trial ended', category: 'av', data: {'room_id': widget.roomId});
      if (!hadCamera) {
        setState(() {});
        return;
      }
      if (_offersKeepFaces) {
        Analytics.instance.track('upgrade_cta_shown', {'surface': 'video_trial'});
      }
      setState(() => _videoTrialEndedNote = true);
      _videoTrialNoteTimer?.cancel();
      _videoTrialNoteTimer = Timer(kVideoTrialEndedNoteFor, () {
        if (mounted) setState(() => _videoTrialEndedNote = false);
      });
    });
  }

  /// The trial's end note offers Premium to the host only, and never on a
  /// build that may not sell it (Google Play) - there it is the member note.
  bool get _offersKeepFaces => canSellPremium && (_sync?.isHost ?? false);

  void _keepFacesOn() {
    Analytics.instance.track('upgrade_cta_clicked', {
      'surface': 'video_trial',
      'action': 'subscribe',
    });
    context.push('/lobby/subscribe?source=video_trial');
  }

  void _registerFeedbackProbes(SyncService sync) {
    final mediaProbe = MediaProbe(
      player: _player,
      facts: () {
        final tracks = _player.state.tracks;
        bool real(String id) => id != 'auto' && id != 'no';
        final subs = tracks.subtitle.where((t) => real(t.id)).toList();
        return MediaFacts(
          mode: _mode.name,
          source: _mode == .youtube
              ? 'youtube'
              : (_isStreamingRemoteSharedMedia ? 'uploaded' : 'local'),
          nameOrUri: _mode == .youtube ? null : (_localFileName ?? _room?.mediaName),
          position: _position,
          duration: _duration,
          playing: _playing,
          buffering: _buffering,
          subtitleFormats: [for (final t in subs) t.codec ?? 'unknown'],
          externalSubtitles: subs.where((t) => t.uri || t.data).length,
          audioTrackCount: tracks.audio.where((t) => real(t.id)).length,
          uploadState: sync.mediaUploadState,
        );
      },
    )..start();
    final undo = [
      FeedbackProbes.register(
        'sync',
        () => {
          'role': sync.isHost ? 'host' : 'member',
          'authority': '${sync.isAuthority}',
          'room_playing': '${sync.roomPlaying}',
          'gate': _gateState.name,
          'seats': '${_present.length}',
          'connected': '$_connected',
          'drift_ms': sync.measuredDrift.value?.inMilliseconds.toString() ?? 'n/a',
        },
      ),
      // The film's technical facts, never its name (see MediaProbe).
      mediaProbe.register(),
      FeedbackProbes.register(
        'av',
        () => {'mic': '${_av?.micEnabled ?? false}', 'cam': '${_av?.camEnabled ?? false}'},
      ),
      // A phone moves while someone watches fullscreen; a shake then must not
      // cover the film with the report sheet.
      ShakeToReport.instance.registerBlocker(() => _immersive && _playing),
    ];
    _unregisterFeedbackProbes = () {
      for (final u in undo) {
        u();
      }
      mediaProbe.dispose();
    };
  }

  void _trackPlaybackStarted() {
    if (_playbackTracked) return;
    _playbackTracked = true;
    Analytics.instance.track('playback_started', {
      'mode': _mode.name,
      'members_present': _present.length,
      'room_id': widget.roomId,
    });
  }

  void _trackWatchSessionEnded() {
    final start = _sessionStart;
    if (_sessionReported || start == null) return;
    _sessionReported = true;
    // Presence still says who was here: this is the last moment it does.
    _logTogether();
    // Captured here, not at the exit: this is the one point both `_leaveRoom`
    // and `_evictSelf` funnel through *before* the sync channel is torn down,
    // so it is the last moment presence still says who was in the room.
    _captureRecap(DateTime.now().difference(start));
    Analytics.instance.track('watch_session_ended', {
      'minutes': DateTime.now().difference(start).inSeconds / 60,
      'peak_members': _peakMembers,
      'modes': _modesUsed.toList()..sort(),
      'messages_sent': _messagesSent,
      'reactions_sent': _reactionsSent,
      'facecam_used': _facecamUsed,
      'room_id': widget.roomId,
    });
  }

  /// Feeds the together-clock from who is present. Our Room only: in any other
  /// room "together" means nothing. When the partner drops out, what has been
  /// accrued so far is written straight away - so a closed laptop or a killed app
  /// costs at most the minutes since, not the whole night. The server keeps the
  /// longest report for a sitting, so the final write on exit simply supersedes.
  void _trackTogether(List<PresentMember> present) {
    if (_room?.isOurRoom != true) return;
    final partnerId = PairService.instance.pair?.partner.id;
    if (partnerId == null) return;
    final myId = AuthService.instance.user?.id;
    if (myId == null) return;
    final ids = {for (final m in present) m.userId};
    final together = ids.contains(partnerId) && ids.contains(myId);
    final wasTogether = _togetherNow;
    _together.update(DateTime.now(), together: together);
    _togetherNow = together;
    if (wasTogether && !together) _logTogether();
  }

  bool _togetherNow = false;

  void _logTogether() {
    final startedAt = _together.startedAt;
    if (_room?.isOurRoom != true || startedAt == null) return;
    final total = _together.total(DateTime.now());
    if (!isLoggableSitting(total)) return;
    unawaited(
      PairService.instance.logSession(
        title: sittingTitle(_canonicalMedia.name),
        startedAt: startedAt,
        together: total,
      ),
    );
  }

  void _captureRecap(Duration length) {
    final sync = _sync;
    if (sync == null) return;
    if (!sessionWorthRecapping(
      length: length,
      peakMembers: _peakMembers,
      isGuest: ProfileService.instance.profile?.isGuest ?? true,
    )) {
      return;
    }

    final selfId = sync.userId;
    for (final member in _present) {
      _tally(member.userId, member.displayName).presentAtEnd = true;
    }
    for (final tally in _tallies.values) {
      tally.gateHolds = _gateBlockers.contains(tally.userId) ? 1 : 0;
    }
    // Only self's camera is knowable from here - LiveKit publication state for
    // other members is not mirrored onto presence, and putting it there would
    // burn the presence budget for a joke award.
    if (_tallies[selfId] case final self?) self.cameraOn = _facecamUsed;

    final people = <String, RecapPerson>{};
    for (final member in _members) {
      people[member.userId] = RecapPerson(
        userId: member.userId,
        displayName: member.displayName,
        avatarUrl: member.profile?.avatarUrl,
      );
    }
    for (final member in _present) {
      people[member.userId] = RecapPerson(
        userId: member.userId,
        displayName: member.displayName,
        avatarUrl: member.avatarUrl,
      );
    }

    final participants = <String>{
      ..._members.map((m) => m.userId),
      ..._present.map((m) => m.userId),
      ..._tallies.keys,
    }..remove(selfId);

    _recapSelfId = selfId;
    _recapPeople = people;
    _pendingRecap = SessionRecap(
      roomId: widget.roomId,
      length: length,
      peakMembers: _peakMembers,
      messages: _messagesSent,
      reactions: _reactionsSent,
      modes: _modesUsed,
      facecamUsed: _facecamUsed,
      cleanGate: !_gateBlockers.contains(selfId),
      participantIds: participants.toList(),
      superlatives: superlativesFor(
        tallies: _tallies.values,
        sessionLength: length,
        crossedTwoAm: _crossedTwoAm,
        hostId: _members.where((m) => m.isHost).firstOrNull?.userId,
      ),
      topEmoji: _topEmoji,
    );
  }

  /// The one moment this feature actually asks for a share. Shown on the way out
  /// rather than over the video, and only for a session worth talking about -
  /// offering a card for four minutes alone is how a delightful thing becomes
  /// an annoying one.
  Future<void> _maybeShowRecap() async {
    final recap = _pendingRecap;
    if (recap == null || _recapOffered || !mounted) return;
    _recapOffered = true;
    _pendingRecap = null;
    Analytics.instance.track('recap_shown', {
      'room_id': recap.roomId,
      'minutes': recap.length.inSeconds / 60,
      'peak_members': recap.peakMembers,
    });
    final shared = await showRecapDialog(
      context: context,
      recap: recap,
      people: _recapPeople,
      selfId: _recapSelfId,
    );
    if (shared) Analytics.instance.track('recap_shared', {'surface': 'room_exit'});
  }

  /// Rides the existing 60 s position-write tick rather than adding a timer.
  /// Everything that decides whether a second is earned happens server-side;
  /// this only reports the user's own calendar day and hour, both of which the
  /// RPC range-checks.
  Future<void> _recordWatchProgress() async {
    if (_ended || !mounted) return;
    final now = DateTime.now();
    if (now.hour >= 2 && now.hour < 5) _crossedTwoAm = true;
    final result = await RewardsService.instance.recordProgress(widget.roomId, now: now);
    if (result.outcome == _lastHeartbeatOutcome) return;
    // A transition, never a tick: the reason a room stopped earning is exactly
    // the breadcrumb worth having, and repeating it every minute would evict
    // the trail that matters.
    _lastHeartbeatOutcome = result.outcome;
    if (!result.credited) {
      trace(
        'watch progress not credited',
        category: 'rewards',
        data: {'room_id': widget.roomId, 'reason': result.outcome.name},
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _rosterFold.load();
    if (widget.player == null) {
      // libass on every platform: the Flutter subtitle view only receives
      // plain text, so ASS/SSA styling and older files' tracks came out
      // unstyled or blank. Android's libass cannot see system fonts, hence
      // the bundled fallback.
      _ownedPlayer = Player(
        configuration: const PlayerConfiguration(
          logLevel: MPVLogLevel.warn,
          libass: true,
          libassAndroidFont: kAndroidSubtitleFontAsset,
          libassAndroidFontName: kAndroidSubtitleFontName,
        ),
      );
    }
    RecentVideos.instance.addListener(_onRecentsChanged);
    unawaited(_onRecentsChanged());
    if (widget.dependencies.videoView == null) {
      _controller = VideoController(_player);
      _subtitleStyle = SubtitleStyleApplier(_player);
      unawaited(applyVideoQualityOptions(_player));
    }
    if (isDesktop) {
      AppWindow.instance.addListener(this);
      // Seed the fullscreen state in case the window was put into fullscreen
      // (e.g. via keyboard shortcut or OS controls), as WindowListener only
      // reports subsequent transitions.
      AppWindow.instance.isFullScreen().then((value) {
        if (mounted && value != _fullscreen) setState(() => _fullscreen = value);
      });
    }
    // Bubbles are kept alive (fading) until the panel has fully covered them.
    _chatAnim.addStatusListener((status) {
      if (status == AnimationStatus.completed && _overlayChat.isNotEmpty) {
        setState(() {
          _overlayChat.clear();
          _expiringChat.clear();
        });
      }
    });
    if (widget.initialChatOpen) {
      _chatOpen = true;
      _chatAnim.value = 1.0;
    }
    ModerationService.instance.addListener(_onBlocksChanged);
    unawaited(_init());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery (size, display features) is a dependency of build, so this
    // runs on every window resize/fold. The comparison happens post-frame and
    // only a *transition* is traced - never the build itself.
    WidgetsBinding.instance.addPostFrameCallback((_) => _noteLayoutClass());
  }

  void _noteLayoutClass() {
    if (!mounted) return;
    final layout = layoutOf(context);
    final fold = foldOf(context).axis;
    final from = _lastLayout;
    final fromFold = _lastFoldAxis;
    if (layout == from && fold == fromFold) return;
    _lastLayout = layout;
    _lastFoldAxis = fold;
    if (from == null) return; // first frame is not a transition
    final size = MediaQuery.sizeOf(context);
    trace(
      'layout class changed',
      category: 'room',
      data: {
        'from': from.name,
        'to': layout.name,
        'size': '${size.width.round()}x${size.height.round()}',
        'fold': fold.name,
        'from_fold': fromFold?.name,
      },
    );
  }

  /// Phone landscape only (never desktop, tablets or folds): while playing
  /// with the controls hidden, the video gets the whole screen and the system
  /// bars come back with a swipe (`immersiveSticky`). Showing the controls,
  /// pausing, leaving or rotating restores the app's edge-to-edge style.
  bool _wantsImmersive(BuildContext context) =>
      !isDesktop &&
      !_ended &&
      _playing &&
      !_controlsVisible &&
      !foldOf(context).isSplit &&
      layoutOf(context) == PTLayout.landscape;

  /// Called from build; defers the platform call to after the frame, and only
  /// when the wanted state differs from the current one.
  void _scheduleImmersiveSync(BuildContext context) {
    if (_immersiveCheckPending || _wantsImmersive(context) == _immersive) return;
    _immersiveCheckPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _immersiveCheckPending = false;
      if (mounted) _setImmersive(_wantsImmersive(context));
    });
  }

  void _setImmersive(bool on) {
    if (on == _immersive) return;
    _immersive = on;
    trace(
      on ? 'immersive playback on' : 'immersive playback off',
      category: 'room',
      data: {'room_id': widget.roomId},
    );
    unawaited(_applySystemUi(immersive: on));
  }

  static Future<void> _applySystemUi({required bool immersive}) async {
    try {
      if (immersive) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        SystemChrome.setSystemUIOverlayStyle(kSystemUiStyle);
      }
    } catch (e, s) {
      reportNonFatal(e, s, during: 'switching immersive playback ${immersive ? 'on' : 'off'}');
    }
  }

  @override
  void onWindowEnterFullScreen() {
    _togglingFullscreen = false;
    setState(() => _fullscreen = true);
  }

  @override
  void onWindowLeaveFullScreen() {
    _togglingFullscreen = false;
    setState(() => _fullscreen = false);
  }

  Future<void> _init() async {
    // The Player is app-wide and outlives this screen, so it still holds
    // whatever the previous room opened. Unload before anything subscribes to
    // its streams. Done on entry, not in dispose(): swapping /room/A for
    // /room/B runs the new State's initState *before* the old one's dispose,
    // so clearing on the way out would wipe the room being entered.
    await _player.stop();

    final profile = ProfileService.instance.profile ?? await ProfileService.instance.load();
    if (profile == null) {
      if (mounted) context.go('/login');
      return;
    }

    // A transient fetch failure must NOT be misread as "room ended" -
    // only a missing/expired room gets the "House lights up." treatment.
    Room? room;
    var loadFailed = false;
    try {
      room = await RoomService.instance.fetchRoom(widget.roomId);
      await RoomService.instance.syncServerTime();
    } catch (e, s) {
      loadFailed = true;
      // The user gets a deliberately vague "check your connection"; the log is
      // the only place the actual cause (RLS, expiry, network) survives.
      reportNonFatal(e, s, during: 'loading room ${widget.roomId}');
    }
    if (!mounted) return;
    if (loadFailed) {
      _snack("Couldn't load the room. Check your connection and try again.");
      context.go('/lobby');
      return;
    }
    if (room == null ||
        room.endedAt != null ||
        room.expiresAt.isBefore(RoomService.instance.serverNow)) {
      _room = room;
      _showEndedDialog();
      return;
    }
    _videoTrialEndsAt = room.videoTrialEndsAt;
    _scheduleVideoTrialEnd();

    try {
      _members = await RoomService.instance.fetchMembers(widget.roomId);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'loading members of room ${widget.roomId}');
      if (mounted) {
        _snack("Couldn't load the room. Check your connection and try again.");
        context.go('/lobby');
      }
      return;
    }
    final selfMembership = _members.where((m) => m.userId == profile.id).firstOrNull;
    if (selfMembership == null) {
      // RLS would have hidden the room if we weren't a member; defensive.
      if (mounted) context.go('/lobby');
      return;
    }

    trace(
      'entered room',
      category: 'room',
      data: {'room_id': widget.roomId, 'role': selfMembership.role, 'members': _members.length},
    );

    unawaited(_refreshMemberTiers());

    final sync = SyncService(
      MediaKitSyncPlayer(_player),
      room: room,
      profile: profile,
      role: selfMembership.role,
    );
    await sync.loadMembership();

    setState(() {
      _uploadState = room?.mediaUploadState ?? 'none';
    });

    sync.onRemotePlay = _remotePlay;
    sync.onRemotePause = _remotePause;
    sync.onRemoteSeek = _remoteSeek;
    sync.onRemoteDriftCorrect = _remoteDriftCorrect;
    sync.currentPosition = () => _position;
    sync.isPlaying = () => _playing;
    sync.isBuffering = () => _buffering;
    sync.serverNow = () => RoomService.instance.serverNow;
    sync.entitlementTier = EntitlementService.instance.tier;

    _subscriptions.addAll([
      sync.chatMessages.listen((message) {
        _tally(message.senderId, message.displayName).messages++;
        setState(() {
          _messages.add(message);
          if (!_chatOpen) _unread++;
        });
        if (!_chatOpen && !_privacyHidden) _pushOverlayChat(message);
      }),
      // A second listener on the same broadcast stream. Subscribed here rather
      // than in build for the reason the overlay's own capture documents: the
      // getter hands out a fresh view object per call.
      sync.reactionsStream.listen(_tallyReaction),
      sync.typingStream.listen((names) => setState(() => _typingNames = names)),
      sync.presenceStream.listen(_onPresenceChanged),
      sync.remoteActions.listen(_onRemoteAction),
      sync.catchUpStream.listen(_onCatchUpResponse),
      sync.modeSwitchStream.listen(_onRemoteModeSwitch),
      sync.canonicalMediaStream.listen(_onCanonicalMedia),
      sync.uploadProgressStream.listen((event) {
        if (!mounted) return;
        setState(() {
          _uploadFraction = event.fraction;
          _uploadSpeedBps = event.speedBps;
          _uploadEtaSeconds = event.etaSeconds;
          _uploadState = event.state;
        });
        if (event.state == 'ready') _streamSharedMediaIfNeeded(_canonicalMedia.name);
      }),
      sync.sharingToggledStream.listen((event) {
        if (!mounted) return;
        if (event.uploadState != null) {
          setState(() => _uploadState = event.uploadState!);
        }
        // Whoever did not upload the file streams it. That is not "everyone who is not
        // the host": in Our Room both people are hosts, and the partner has to
        // stream what the other shared. The uploader already has the file open.
        if (event.uploadState == 'ready' || _sync?.mediaUploadState == 'ready') {
          _streamSharedMediaIfNeeded(event.fileName ?? _canonicalMedia.name);
        }
      }),
      sync.avEndpointStream.listen((endpoint) => _av?.followEndpoint(endpoint)),
      sync.videoTrialStream.listen((event) => _adoptVideoTrial(event.endsAt, event.startedBy)),
      sync.roomExtendedStream.listen((event) {
        if (!mounted) return;
        final parsed = DateTime.tryParse(event.expiresAt);
        if (parsed != null) {
          setState(() {
            if (_room != null) {
              _room = _room!.copyWith(expiresAt: parsed, durationMinutes: event.durationMinutes);
            }
            _warningDismissed = false;
          });
          _tickCountdown();
          _snack('The host added more time to this room!', kind: .info);
        }
      }),
      sync.gateStream.listen((state) {
        if (_ended || !mounted) return;
        setState(() => _gateState = state);
        _syncGateReveal();
      }),
      sync.roomEndedStream.listen(_onRoomEndedRemotely),
      sync.hostAssignedStream.listen(_onHostAssignedRemotely),
      sync.kickedStream.listen((_) => _onKicked()),
      sync.transportLockStream.listen((_) {
        setState(() {});
        _publishMenuData();
      }),
      sync.gateResumedStream.listen(
        (_) => _showActionToast("Curtain up. Everyone's in", arrival: true),
      ),
      sync.connectionStream.listen((up) {
        final wasConnected = _connected;
        setState(() => _connected = up);
        // Backfill anything said during the outage - broadcasts don't replay.
        if (up && !wasConnected) _reloadChatHistory();
      }),
      _player.stream.playing.listen((playing) {
        if (_mode == .local) {
          setState(() => _playing = playing);
          _stream?.onPlaying(playing);
          _onPlayingChangedForControls(playing);
        }
      }),
      _player.stream.position.listen((position) {
        if (_mode == .local) _position = playablePosition(position);
      }),
      _player.stream.duration.listen((duration) {
        if (_mode != .local) return;
        final wasResolved = _duration != Duration.zero;
        setState(() => _duration = duration);
        if (_isStreamingRemoteSharedMedia) _stream?.onDuration(duration);
        if (wasResolved != (duration != Duration.zero)) {
          trace(
            'local duration ${duration == Duration.zero ? 'cleared' : 'resolved'}',
            category: 'media',
            data: {'ms': duration.inMilliseconds, 'ext': mediaExtension(_localFileName)},
          );
        }
        if (duration != Duration.zero) {
          _localLoadWatchdog?.cancel();
          final recentId = _recentId;
          if (recentId != null && !_isStreamingRemoteSharedMedia) {
            unawaited(RecentVideos.instance.updateDuration(recentId, duration));
          }
        }
        // A non-zero duration is what "the file is actually open" means, so
        // this is the local-mode loading -> ready edge.
        _updateReadiness();
      }),
      _player.stream.log.listen(_onPlayerLog),
      _player.stream.error.listen(_onPlayerError),
      _player.stream.buffering.listen((buffering) {
        if (_mode != .local) return;
        setState(() => _buffering = buffering);
        _stream?.onBuffering(buffering);
        _sync?.noteBuffering(buffering);
      }),
      _player.stream.width.listen((w) {
        if (w != null && w > 0 && _isStreamingRemoteSharedMedia) _stream?.onFirstFrame();
      }),
      _player.stream.buffer.listen((buffer) {
        if (_isStreamingRemoteSharedMedia && _mode == .local) {
          setState(() => _bufferPosition = buffer);
        }
      }),
      _player.stream.volume.listen((volume) => setState(() => _volume = volume / 100)),
      // The SUBS / AUDIO keys name the selected tracks.
      _player.stream.track.listen((_) {
        if (_mode == .local) setState(() {});
      }),
      _player.stream.completed.listen((done) {
        if (done && _mode == .local && mounted) unawaited(maybeAskForReview(context));
      }),
    ]);

    setState(() {
      _room = room;
      _sync = sync;
      _reactionStream = sync.reactionsStream;
      _canonicalMedia = sync.canonicalMedia;
      _loading = false;
    });
    _sessionStart = DateTime.now();
    _peakMembers = _members.length;
    _registerFeedbackProbes(sync);
    unawaited(DiscoveryTriggers.instance.noteRoomVisited());

    unawaited(_reactionAssets.preload());

    await sync.connect();
    _updateReadiness();
    unawaited(_reloadChatHistory());

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tickCountdown());
    _tickCountdown();
    _positionWriteTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      unawaited(_persistPosition());
      unawaited(_recordWatchProgress());
    });

    unawaited(
      EntitlementService.instance.load().then((_) {
        if (mounted) _sync?.entitlementTier = EntitlementService.instance.tier;
      }),
    );

    unawaited(_resumeFromCanonicalMedia());

    final isHost = sync.isHost;
    final hasMedia =
        _player.state.duration != Duration.zero || _youtubeUrl != null || _canonicalMedia.isSet;

    // `?dialog=media` is the screenshot hook, so it opens the chooser even
    // over the demo room's pre-set film.
    final forceChooser = widget.initialDialogOpen == 'media';
    if ((forceChooser || (isHost && !hasMedia)) && !_hasPromptedInitialSource) {
      _hasPromptedInitialSource = true;
      // Host in an empty room: prompt immediately rather than making the user
      // stare at "Setting up the room…" for the 4.5s late-joiner sync window.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _ended) return;
        if (!_isModeSelectionDialogOpen && !_isYouTubeUrlDialogOpen) {
          _showModeSelectionDialog();
        }
      });
    } else if (!_hasPromptedInitialSource) {
      // If the state-sync window closes with no media, we're first in - ask
      // what to watch.
      _idleSourceTimer = Timer(const Duration(milliseconds: 4500), () {
        if (!mounted) return;
        _resolveFirstSource();
        if (_ended) return;
        // Members are never auto-prompted for a source - the readiness overlay
        // tells them the host is still choosing.
        if (!(_sync?.isHost ?? false)) return;
        if (_hasPromptedInitialSource) return;
        final hasMediaNow =
            _player.state.duration != Duration.zero || _youtubeUrl != null || _canonicalMedia.isSet;
        if (!hasMediaNow && !_isModeSelectionDialogOpen && !_isYouTubeUrlDialogOpen) {
          _hasPromptedInitialSource = true;
          _showModeSelectionDialog();
        }
      });
    }

    if (LiveKitService.isAvailableFor(room.avLevel)) {
      final av = LiveKitService(roomId: widget.roomId, avLevel: room.avLevel);
      av.addListener(_onAvChanged);
      _subscriptions.add(
        av.trackFailures.listen((kind) {
          if (!mounted) return;
          _snack(
            kind == 'mic'
                ? "Couldn't start your microphone - check it isn't in use or blocked."
                : "Couldn't start your camera - check it isn't in use or blocked.",
            kind: .info,
          );
        }),
      );
      setState(() => _av = av);
      // Started while the app is in the foreground (Android 14 insists), and
      // held until the room is left or disposed.
      _syncBackgroundCall();
      av
          .connect()
          .then((_) {
            if (mounted) _applyPreferredDevices();
          })
          .catchError((_) {});

      _deviceChangeSub = DevicePreferenceService.instance.onDeviceChange.listen((_) {
        if (mounted) _applyPreferredDevices();
      });
    }
  }

  void _onAvChanged() {
    if (mounted) setState(() {});
    _syncBackgroundCall();
  }

  /// Mobile only: keeps the call alive in the background, re-typing the
  /// Android service as the mic and camera come and go. Cheap when nothing
  /// changed - [BackgroundCall] dedupes.
  void _syncBackgroundCall() {
    final av = _av;
    if (!mounted || av == null || !isMobile) return;
    unawaited(
      _backgroundCall.update(
        mic: av.micEnabled,
        cam: av.camEnabled,
        title: _room?.name ?? 'SyncTogether',
      ),
    );
  }

  /// Holds the phone's screen awake only while the picture is playing.
  void _syncScreenAwake() {
    unawaited(
      setScreenAwake(shouldHoldScreenAwake(mobile: isMobile, inRoom: mounted, playing: _playing)),
    );
  }

  Future<void> _applyPreferredDevices() async {
    final av = _av;
    if (av == null || !mounted) return;

    try {
      final prefService = DevicePreferenceService.instance;
      await prefService.init();

      // 1. Microphone
      final audioInputs = await av.audioInputDevices();
      final resolvedMic = prefService.resolveDevice(audioInputs, prefService.preferredMic);
      if (resolvedMic != null && resolvedMic.deviceId != av.selectedAudioInputId) {
        await av.setAudioInputDevice(resolvedMic);
      }

      // 2. Camera
      final videoInputs = await av.videoInputDevices();
      final resolvedCam = prefService.resolveDevice(videoInputs, prefService.preferredCam);
      if (resolvedCam != null && resolvedCam.deviceId != av.selectedVideoInputId) {
        await av.setVideoInputDevice(resolvedCam);
      }

      // 3. Audio Output (routes to LiveKit and media_kit player in local mode)
      final audioOutputs = await av.audioOutputDevices();
      final resolvedOutput = prefService.resolveDevice(audioOutputs, prefService.preferredOutput);
      if (resolvedOutput != null) {
        if (resolvedOutput.deviceId != av.selectedAudioOutputId) {
          await av.setAudioOutputDevice(resolvedOutput);
        }
        if (_mode == .local) {
          final playerDevices = _player.state.audioDevices;
          final match = playerDevices.where((d) {
            final devDesc = d.description.trim().toLowerCase();
            final targetLabel = resolvedOutput.label.trim().toLowerCase();
            final devName = d.name.trim().toLowerCase();
            final targetId = resolvedOutput.deviceId.trim().toLowerCase();
            return (devDesc.isNotEmpty &&
                    (devDesc == targetLabel ||
                        targetLabel.contains(devDesc) ||
                        devDesc.contains(targetLabel))) ||
                (targetId.isNotEmpty && devName.contains(targetId));
          }).firstOrNull;
          if (match != null) {
            unawaited(_player.setAudioDevice(match));
            trace(
              'applied default player audio device',
              category: 'media',
              data: {'device': match.name, 'label': resolvedOutput.label},
            );
          }
        }
      }
    } catch (e, s) {
      reportNonFatal(e, s, during: 'applying preferred AV devices');
    }
  }

  @override
  void dispose() {
    _unregisterFeedbackProbes?.call();
    _subtitleStyle?.dispose();
    _chatDraft.dispose();
    _rosterFold.dispose();
    ModerationService.instance.removeListener(_onBlocksChanged);
    if (_immersive) unawaited(_applySystemUi(immersive: false));
    if (isDesktop) AppWindow.instance.removeListener(this);
    for (final s in _subscriptions) {
      s.cancel();
    }
    _countdownTimer?.cancel();
    _videoTrialTimer?.cancel();
    _videoTrialNoteTimer?.cancel();
    _positionWriteTimer?.cancel();
    _idleSourceTimer?.cancel();
    _controlsHideTimer?.cancel();
    _cursorHideTimer?.cancel();
    _kbBarTimer?.cancel();
    _actionToastTimer?.cancel();
    _skipFlashTimer?.cancel();
    _ytBufferFallbackTimer?.cancel();
    _catchUpTimeoutTimer?.cancel();
    _localLoadWatchdog?.cancel();
    _thumbWait?.cancel();
    unawaited(_stream?.dispose());
    RecentVideos.instance.removeListener(_onRecentsChanged);
    unawaited(_localVideo?.release());
    for (final t in _overlayChatTimers) {
      t.cancel();
    }
    _shortcutFocus.dispose();
    _resuming.dispose();
    _overflowMenu?.close(animate: false);
    _menuData.dispose();
    _chatCurve.dispose();
    _chatAnim.dispose();
    _gateCurve.dispose();
    _gateAnim.dispose();
    _youtubeController?.dispose();
    _deviceChangeSub?.cancel();
    _sync?.dispose();
    _av?.removeListener(_onAvChanged);
    _av?.dispose();
    if (isMobile) {
      unawaited(_backgroundCall.stop());
      unawaited(setScreenAwake(false));
    }
    _ownedPlayer?.dispose();
    _positionNotifier.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Presence / membership
  // ---------------------------------------------------------------------------

  Future<void> _refreshMemberTiers() async {
    if (_tierFetchInFlight) return;
    final seen = {..._members.map((m) => m.userId), ..._present.map((m) => m.userId)};
    if (seen.difference(_resolvedTierIds).isEmpty) return;
    _tierFetchInFlight = true;
    try {
      final cosmetics = await RoomService.instance.fetchMemberTiers(widget.roomId);
      if (!mounted) return;
      final premium = premiumMembersFrom(cosmetics.tiers);
      trace(
        'member tiers resolved',
        category: 'room',
        data: {
          'room_id': widget.roomId,
          'members': cosmetics.tiers.length,
          'premium': premium.length,
          'frames': cosmetics.frames.length,
        },
      );
      setState(() {
        _resolvedTierIds = cosmetics.tiers.keys.toSet();
        _premiumMembers = premium;
        _memberFrames = cosmetics.frames;
      });
    } catch (e, s) {
      reportNonFatal(e, s, during: 'loading member tiers for room ${widget.roomId}');
    } finally {
      _tierFetchInFlight = false;
    }
  }

  Future<void> _onPresenceChanged(List<PresentMember> present) async {
    final sync = _sync;
    final prevCount = _present.length;
    setState(() => _present = present);
    _trackTogether(present);
    final av = _av;
    if (av != null) {
      if (prevCount >= 2 && present.length < 2) {
        // Remember active user intent so it restores automatically when a member rejoins.
        _camBeforeSolo = av.camEnabled;
        _micBeforeSolo = av.micEnabled;
        if (_camBeforeSolo) unawaited(av.setCamEnabled(false));
        if (_micBeforeSolo) unawaited(av.setMicEnabled(false));
      } else if (prevCount < 2 && present.length >= 2) {
        // Someone joined: restore active media if it was active before the solo drop.
        if (_camBeforeSolo && !_privacyHidden) unawaited(av.setCamEnabled(true));
        if (_micBeforeSolo && !_privacyHidden) unawaited(av.setMicEnabled(true));
        _camBeforeSolo = false;
        _micBeforeSolo = false;
      }
    }
    unawaited(_refreshMemberTiers());
    _syncGateReveal();
    // Distinct people, not presence entries: a member who leaves and rejoins within
    // a couple of seconds briefly has two entries (the old one has not expired), which
    // used to push the peak - and the recap's "in sync with N others" - one too high.
    final people = {for (final member in present) member.userId}.length;
    if (people > _peakMembers) _peakMembers = people;
    for (final member in present) {
      final tally = _tally(member.userId, member.displayName);
      if (!_firstPresenceSeen) tally.presentAtStart = true;
    }
    // Only the people somebody is *waiting on* - see `gateHolderIds`. Counting
    // every not-yet-ready member would name the whole room on entry and after
    // every media change, which is not what "held everyone up" means.
    if (sync != null) {
      _gateBlockers.addAll(gateHolderIds(sync.canonicalMedia, present));
    }
    _firstPresenceSeen = true;
    // Don't wait on the member fetch: readiness/online changes should land in
    // an open menu immediately, even if the round-trip is slow or fails.
    _publishMenuData();
    // Membership can change under us (join/leave/host succession).
    try {
      final members = await RoomService.instance.fetchMembers(widget.roomId);
      if (!mounted) return;
      setState(() => _members = members);
      unawaited(_refreshMemberTiers());
      final selfRole = members.where((m) => m.userId == _sync?.userId).firstOrNull?.role;
      if (selfRole != null) {
        final wasHost = _sync?.isHost ?? false;
        _sync?.updateRole(selfRole);
        // Inheriting an empty room means inheriting the job of choosing (D2).
        // The original 4.5 s idle prompt is one-shot and long gone by now.
        if (!wasHost &&
            (_sync?.isHost ?? false) &&
            !_canonicalMedia.isSet &&
            !_ended &&
            !_isModeSelectionDialogOpen &&
            !_isYouTubeUrlDialogOpen) {
          _showModeSelectionDialog();
        }
      }
      _publishMenuData();
    } catch (e, s) {
      // Presence still landed; only the membership refresh behind it failed.
      // The cost is a stale roster: a host succession we didn't notice, or a
      // kick the overflow menu keeps showing.
      reportNonFatal(e, s, during: 'refreshing members after a presence change');
    }
  }

  /// Republish the overflow menu's snapshot. Cheap and idempotent (nothing
  /// listens while the menu is closed), so call it from anywhere any of its
  /// inputs move: presence, membership, own role, canonical media, transport
  /// lock, eviction.
  void _publishMenuData() {
    final sync = _sync;
    final isOwner = _room?.createdBy == sync?.userId;
    _menuData.value = _ended
        ? null
        : RoomMenuData(
            members: _members,
            present: _present,
            premiumMembers: _premiumMembers,
            memberFrames: _memberFrames,
            blockedIds: ModerationService.instance.blockedIds,
            media: _canonicalMedia,
            transportLock: sync?.transportLock ?? false,
            selfId: sync?.userId ?? '',
            selfIsHost: sync?.isHost ?? false,
            canAssignHost: (sync?.isHost ?? false) || isOwner,
            ourRoom: _room?.isOurRoom ?? false,
          );
  }

  void _onRemoteAction(RemoteAction action) {
    final name =
        _present.where((m) => m.userId == action.senderId).firstOrNull?.displayName ??
        _members.where((m) => m.userId == action.senderId).firstOrNull?.displayName ??
        'Someone';
    // `remoteActions` is user-initiated only - gate pauses and drift correction
    // never reach here - which is exactly the distinction "The Pauser" needs.
    _tally(action.senderId, name).transportActions++;
    _showActionToast(switch (action.kind) {
      RemoteActionKind.seek => '$name jumped to ${_clock(action.position ?? Duration.zero)}',
      RemoteActionKind.play => '$name resumed the video',
      RemoteActionKind.pause => '$name paused the video',
    });
  }

  /// [arrival] gets the one overshoot curve in the system - reserved for
  /// "we're all here" moments, never for routine attribution.
  void _showActionToast(String text, {bool arrival = false}) {
    if (!mounted) return;
    setState(() {
      _actionToastText = text;
      _actionToastVisible = true;
      _actionToastArrival = arrival;
    });
    _actionToastTimer?.cancel();
    _actionToastTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _actionToastVisible = false);
    });
  }

  static String _clock(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  void _pushOverlayChat(ChatMessage message) {
    setState(() {
      _overlayChat.add(message);
      if (_overlayChat.length > 3) _expiringChat.remove(_overlayChat.removeAt(0));
    });
    late final Timer timer;
    timer = Timer(const Duration(seconds: 5), () {
      _overlayChatTimers.remove(timer);
      if (!mounted) return;
      setState(() => _expiringChat.add(message));
      late final Timer removal;
      removal = Timer(PTMotion.state, () {
        _overlayChatTimers.remove(removal);
        if (!mounted) return;
        setState(() {
          _overlayChat.remove(message);
          _expiringChat.remove(message);
        });
      });
      _overlayChatTimers.add(removal);
    });
    _overlayChatTimers.add(timer);
  }

  void _cancelOverlayChatTimers() {
    for (final t in _overlayChatTimers) {
      t.cancel();
    }
    _overlayChatTimers.clear();
    _expiringChat.clear();
  }

  // ---------------------------------------------------------------------------
  // Remote playback routing (dual player)
  // ---------------------------------------------------------------------------

  bool get _ytReady => _youtubeController?.isReady ?? false;

  /// Spinner shows only while the player is stalled AND meant to be playing -
  /// a buffer that fills behind a paused frame needs no indicator. YouTube's
  /// state reads `buffering` (not `playing`) mid-stall, so gate it on intent.
  bool get _showBuffering => _buffering && (_mode == .youtube ? _ytIntendedPlaying : _playing);

  void _remotePlay() {
    if (_mode == .youtube) {
      _ytIntendedPlaying = true;
      if (!_ytReady || (_youtubeController?.isAdPlaying ?? false)) {
        _pendingYtPlay = true;
        return;
      }
      _youtubeController?.play();
    } else {
      _player.play();
    }
  }

  void _remotePause() {
    if (_mode == .youtube) {
      _ytIntendedPlaying = false;
      if (!_ytReady || (_youtubeController?.isAdPlaying ?? false)) {
        _pendingYtPlay = false;
        return;
      }
      _youtubeController?.pause();
    } else {
      _player.pause();
    }
  }

  void _remoteSeek(Duration position) {
    if (_mode == .youtube) {
      if (!_ytReady || (_youtubeController?.isAdPlaying ?? false)) {
        _pendingYtSeek = position;
        return;
      }
      _ytSeekKeepingPlayState(position);
    } else {
      _player.seek(position);
    }
  }

  /// Seeking a `cued` player starts it, so restore the intended pause and
  /// swallow the transient playing blip rather than re-broadcasting it.
  void _ytSeekKeepingPlayState(Duration position) {
    final controller = _youtubeController;
    if (controller == null) return;
    controller.seekTo(position);
    if (!_ytIntendedPlaying) {
      _ytEventSuppressUntil = DateTime.now().add(const Duration(milliseconds: 800));
      controller.pause();
    }
  }

  void _remoteDriftCorrect(Duration position) {
    if (_mode == .youtube) {
      // No pause: drift correction only fires while both sides are playing.
      if (_ytReady && !(_youtubeController?.isAdPlaying ?? false)) {
        _youtubeController?.seekTo(position);
      }
    } else {
      _player.seek(position);
    }
  }

  // ---------------------------------------------------------------------------
  // Mode switching (ported from PTVideoPlayer - dialog dismissal is delicate)
  // ---------------------------------------------------------------------------

  /// Closes the "choose a file or a YouTube link" dialogs because someone else has
  /// already chosen for the room (a mode switch, or media the room now has). The URL
  /// dialog sits on top of the source chooser, so it pops first.
  void _dismissSourceDialogs() {
    if (!mounted) return;
    if (_isYouTubeUrlDialogOpen) {
      _urlDialogDismissedRemotely = true;
      Navigator.of(context).pop();
      _isYouTubeUrlDialogOpen = false;
    }
    if (_isModeSelectionDialogOpen) {
      Navigator.of(context).pop();
      _isModeSelectionDialogOpen = false;
    }
  }

  Future<void> _onRemoteModeSwitch(dynamic event) async {
    if (mounted) {
      if (_awaitingFirstSource) _resolveFirstSource();
      _dismissSourceDialogs();
    }
    trace('remote mode switch', category: 'media', data: {'mode': event.mode});
    final PlaybackMode mode = event.mode == 'youtube' ? .youtube : .local;
    if (mode == .youtube && event.youtubeUrl != null) {
      _switchToYouTubeMode(event.youtubeUrl as String);
    } else {
      await _switchToLocalMode();
    }
  }

  Future<void> _showModeSelectionDialog() async {
    _hasPromptedInitialSource = true;
    _idleSourceTimer?.cancel();
    _isModeSelectionDialogOpen = true;
    _updateReadiness();
    if (_awaitingFirstSource) _resolveFirstSource();
    final mode = await showGlassDialog<InitialMode>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ModeSelectionDialog(),
    );
    _isModeSelectionDialogOpen = false;
    _updateReadiness();
    if (!mounted) return;

    if (mode == InitialMode.local) {
      await _pickVideo();
    } else if (mode == InitialMode.youtube) {
      _isYouTubeUrlDialogOpen = true;
      _urlDialogDismissedRemotely = false;
      _updateReadiness();
      final url = await showGlassDialog<String>(
        context: context,
        width: 440,
        builder: (_) => const YouTubeUrlDialog(),
      );
      _isYouTubeUrlDialogOpen = false;
      _updateReadiness();
      if (!mounted) return;
      if (url != null) {
        await _handleModeSwitch(.youtube, url);
      } else if (!_urlDialogDismissedRemotely &&
          _mode == .local &&
          _player.state.duration == Duration.zero) {
        _showModeSelectionDialog(); // cancelled and still idle: re-ask
      }
    }
  }

  Future<void> _playSharedVideo(String videoId, String sharedBy) async {
    if (!(_sync?.isHost ?? false)) return;
    if (_mode == .youtube && youtubeVideoId(_youtubeUrl ?? '') == videoId) {
      _snack("That's what we're already watching.", kind: .info);
      return;
    }
    trace('shared youtube link tapped in chat', category: 'youtube', data: {'video_id': videoId});
    final confirmed = await showGlassDialog<bool>(
      context: context,
      width: 400,
      builder: (_) => PlaySharedVideoDialog(videoId: videoId, sharedBy: sharedBy),
    );
    if (confirmed != true || !mounted) return;
    trace('playing youtube link shared in chat', category: 'youtube', data: {'video_id': videoId});
    await _handleModeSwitch(.youtube, canonicalYouTubeUrl(videoId));
  }

  void _switchToYouTubeMode(String url) {
    final videoId = youtubeVideoId(url);
    if (videoId == null) {
      _snack("Hmm, that doesn't look like a YouTube link.");
      return;
    }
    // Re-applying the video we already have embedded must NOT reset anything.
    // Duplicate switches are routine - a `state_response` after a reconnect
    // replays the room's mode - and tearing readiness down for one would shut
    // the gate on a room that never changed what it was watching.
    if (_mode == .youtube &&
        _youtubeController != null &&
        youtubeVideoId(_youtubeUrl ?? '') == videoId) {
      trace(
        'youtube switch to the video already embedded',
        category: 'media',
        data: {'video_id': videoId},
      );
      _youtubeUrl = url;
      _sync?.updatePlaybackState('youtube', url);
      _updateReadiness();
      return;
    }

    _modesUsed.add('youtube');
    _playbackTracked = false;
    // A new video re-runs the D6 buffer race from scratch.
    _ytBufferFallbackTimer?.cancel();
    _ytBufferFallbackTimer = null;
    _ytBufferReady = false;
    _localLoadWatchdog?.cancel();
    _localLoadStalled = false;
    _isStreamingRemoteSharedMedia = false;
    unawaited(_stream?.reset());
    final existing = _youtubeController;
    trace(
      'switching to youtube mode',
      category: 'media',
      data: {'video_id': videoId, 'reusing_controller': existing != null},
    );
    setState(() {
      _mode = .youtube;
      _youtubeUrl = url;
      _localFileName = null;
      _playing = false;
      _buffering = false;
      _position = Duration.zero;
      _duration = Duration.zero;
      _youtubeWasPlaying = false;
      _ytIntendedPlaying = false;
      _pendingYtSeek = null;
      _pendingYtPlay = null;
      _ytErrorShownFor = null;

      if (existing == null) {
        _youtubeController = PTYouTubeController(videoId)
          ..addListener(_onYouTubePlayerEvent)
          ..setVolume((_volume * 100).round());
      }
    });
    // _playing was just reset; a local picture that was playing no longer is.
    _syncScreenAwake();
    existing?.loadVideo(videoId);
    _sync?.updatePlaybackState('youtube', url);
    _armYouTubeReadyFallback();
    _updateReadiness();
  }

  Future<void> _switchToLocalMode() async {
    trace('switching to local mode', category: 'media', data: {'from': _mode.name});
    _modesUsed.add('local');
    _playbackTracked = false;
    _ytBufferFallbackTimer?.cancel();
    _ytBufferFallbackTimer = null;
    _catchUpTimeoutTimer?.cancel();
    _catchUpTimeoutTimer = null;
    _isCatchingUp = false;
    _ytBufferReady = false;
    setState(() {
      _mode = .local;
      _youtubeUrl = null;
      _youtubeWasPlaying = false;
      _youtubeWasAdPlaying = false;
      _ytIntendedPlaying = false;
      _pendingYtSeek = null;
      _pendingYtPlay = null;
      _ytErrorShownFor = null;
      _youtubeController?.dispose();
      _youtubeController = null;
      _playing = _player.state.playing;
      _buffering = _player.state.buffering;
      _position = playablePosition(_player.state.position);
      _duration = _player.state.duration;
    });
    _sync?.updatePlaybackState('local', null);
    _updateReadiness();
    await _pickVideo();
  }

  void _onYouTubePlayerEvent() {
    final controller = _youtubeController;
    if (controller == null) return;

    _flushPendingYtCommands(controller);
    _updateYouTubeReadiness(controller);

    final PTYtPlayerState state = controller.playerState;
    final isPlaying = state == .playing;

    final wasPlaying = _playing;
    final wasBuffering = _buffering;
    setState(() {
      _playing = isPlaying;
      _buffering = state == .buffering;
      _position = playablePosition(controller.position);
      if (controller.duration != Duration.zero) _duration = controller.duration;
    });
    if (isPlaying != wasPlaying) _onPlayingChangedForControls(isPlaying);
    // Ads have their own catch-up (_handleAdEnded); a stall inside one is not ours.
    if (_buffering != wasBuffering && !controller.isAdPlaying) {
      _sync?.noteBuffering(_buffering);
    }

    final wasAd = _youtubeWasAdPlaying;
    final isAd = controller.isAdPlaying;
    _youtubeWasAdPlaying = isAd;

    if (wasAd && !isAd) {
      _handleAdEnded();
    }

    // Broadcast only transitions that diverge from the agreed play state -
    // those are direct iframe interactions. Everything triggered by _playPause
    // or a remote event already matches _ytIntendedPlaying, so no echo and no
    // double-broadcast, regardless of iframe latency.
    // Suppress broadcasts during ads so ad playback doesn't trigger spurious room events.
    final suppressed = DateTime.now().isBefore(_ytEventSuppressUntil) || controller.isAdPlaying;
    if (isPlaying && !_youtubeWasPlaying) {
      _youtubeWasPlaying = true;
      if (!_ytIntendedPlaying && !suppressed) {
        _ytIntendedPlaying = true;
        _sync?.broadcastPlay();
        _sync?.broadcastSeek(controller.position, reason: SyncActionReason.transport);
      }
    } else if (!isPlaying && _youtubeWasPlaying && state == .paused) {
      _youtubeWasPlaying = false;
      if (_ytIntendedPlaying && !suppressed) {
        _ytIntendedPlaying = false;
        _sync?.broadcastPause();
      }
    }

    final errorCode = controller.errorCode;
    if (errorCode != null && errorCode != _ytErrorShownFor) {
      _ytErrorShownFor = errorCode;
      _snack(_ytErrorMessage(errorCode));
      // 100 (removed/private) and 101/150 (embedding disabled by the owner)
      // are answers about the video, already explained in the snack.
      if (const {100, 101, 150}.contains(errorCode)) {
        trace('youtube video unavailable', category: 'youtube', data: {'code': errorCode});
        return;
      }
      reportNonFatal(
        StateError('YouTube IFrame error $errorCode'),
        StackTrace.current,
        during: 'loading a YouTube video',
      );
    }
  }

  void _handleAdEnded() {
    trace('ad ended - checking room alignment', category: 'youtube');
    // Suppress outgoing transport broadcast while realigning.
    _ytEventSuppressUntil = DateTime.now().add(const Duration(milliseconds: 2000));

    final sync = _sync;
    final isAlone =
        sync == null ||
        (sync.hasPresenceSynced && sync.presentMembers.every((m) => m.userId == sync.userId));

    if (isAlone) {
      trace('alone in room after ad: resuming local playback', category: 'youtube');
      _youtubeController?.play();
      return;
    }

    _isCatchingUp = true;
    _catchUpTimeoutTimer?.cancel();
    _catchUpTimeoutTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted || !_isCatchingUp) return;
      trace('catch-up timeout: resuming local playback', category: 'youtube');
      _isCatchingUp = false;
      _youtubeController?.play();
    });

    sync.requestCatchUp();
  }

  void _onCatchUpResponse(CatchUpResponseEvent event) {
    if (!mounted || !_isCatchingUp || _mode != .youtube) return;
    _isCatchingUp = false;
    _catchUpTimeoutTimer?.cancel();

    final targetPos = Duration(milliseconds: event.positionMs);
    final currentPos = _youtubeController?.position ?? _position;
    final deltaMs = targetPos.inMilliseconds - currentPos.inMilliseconds;

    trace(
      'processing catch-up response',
      category: 'youtube',
      data: {
        'target_ms': event.positionMs,
        'current_ms': currentPos.inMilliseconds,
        'delta_ms': deltaMs,
        'playing': event.playing,
      },
    );

    if (deltaMs > 1500) {
      // Room has progressed forward during the ad. Catch up to room position!
      _ytEventSuppressUntil = DateTime.now().add(const Duration(milliseconds: 2000));
      _ytIntendedPlaying = event.playing;
      _remoteSeek(targetPos);
      if (event.playing) {
        _youtubeController?.play();
      } else {
        _youtubeController?.pause();
      }
      final seconds = (deltaMs / 1000).round();
      _snack('Ad ended • Caught up to room (+$seconds s)', kind: .info);
    } else {
      // Already aligned with room or room was paused/scrubbed back.
      _ytIntendedPlaying = event.playing;
      if (event.playing) {
        _youtubeController?.play();
      } else {
        _youtubeController?.pause();
      }
    }
  }

  String _ytErrorMessage(int code) => switch (code) {
    101 || 150 => "The owner of that video won't let it play outside YouTube. Try a different one.",
    100 => "That video is private or isn't on YouTube any more.",
    _ => 'Failed to load that YouTube video.',
  };

  /// Late joiners get the room's position/play state before the iframe can
  /// accept commands; apply the queued state on the first ready tick.
  void _flushPendingYtCommands(PTYouTubeController controller) {
    if (!controller.isReady || controller.isAdPlaying) return;
    final seek = _pendingYtSeek;
    final play = _pendingYtPlay;
    if (seek == null && play == null) return;
    trace(
      'flushing queued youtube commands',
      category: 'youtube',
      data: {'seek_ms': seek?.inMilliseconds, 'play': play},
    );
    _pendingYtSeek = null;
    _pendingYtPlay = null;
    if (seek != null) {
      _ytSeekKeepingPlayState(seek);
    }
    if (play == true) {
      controller.play();
    } else if (play == false && seek == null) {
      controller.pause();
    }
  }

  Future<void> _handleModeSwitch(PlaybackMode targetMode, String? url) async {
    if (targetMode == .youtube && url == null) return;
    Analytics.instance.track('media_selected', {'kind': targetMode.name, 'room_id': widget.roomId});
    await _persistPosition();
    _lastWrittenPosition = null;
    if (targetMode == .youtube) {
      if (url != null) {
        _switchToYouTubeMode(url);
        _sync?.broadcastModeSwitch('youtube', url);
        unawaited(_publishCanonicalMedia(.youtube, url: url));
      }
    } else {
      // Clear canonical first: between leaving YouTube and actually picking a
      // file there is nothing to load, and leaving the old media set would have
      // the gate judging everyone against a video the room has moved off.
      // `_announceLocalFile` sets the real one if a file gets picked.
      await _publishCanonicalMedia(.none);
      await _switchToLocalMode();
      _sync?.broadcastModeSwitch('local', null);
    }
  }

  Future<void> _handleSwitchSource() async {
    if (_mode == .local) {
      await _promptYouTubeLink();
    } else {
      await _handleModeSwitch(.local, null);
    }
  }

  /// The YouTube link dialog, then the switch for the whole room.
  Future<void> _promptYouTubeLink() async {
    _isYouTubeUrlDialogOpen = true;
    _updateReadiness();
    final url = await showGlassDialog<String>(
      context: context,
      width: 440,
      builder: (_) => const YouTubeUrlDialog(),
    );
    _isYouTubeUrlDialogOpen = false;
    _updateReadiness();
    if (url != null && mounted) await _handleModeSwitch(.youtube, url);
  }

  /// Whether the readiness overlay should offer the host a way to choose: the
  /// room has nothing set yet, so the gate is waiting on *us*.
  bool get _hostMustChoose => (_sync?.isHost ?? false) && !_canonicalMedia.isSet;

  /// Opens the local-video chooser (Photos, Files, Recent) and plays what it
  /// returns. [autoStart] jumps straight to one door (the tablet empty room's
  /// own Photos/Files buttons).
  Future<void> _pickVideo({ChoiceSource? autoStart}) async {
    _isFilePickerOpen = true;
    _updateReadiness();
    final LocalVideoChoice? choice;
    try {
      choice = await showLocalVideoChooser(context, autoStart: autoStart);
    } finally {
      _isFilePickerOpen = false;
    }
    final video = choice?.video;
    if (video == null) {
      _updateReadiness(); // closed: back to whatever we had before
      return;
    }
    await _playChosenVideo(video, source: choice!.source);
  }

  /// The empty room's "Reopen (last file)" line: Recent's newest entry, no chooser.
  Future<void> _reopenLastRecent() async {
    final entry = _lastRecent;
    if (entry == null) return;
    var r = await RecentVideos.instance.resolve(entry);
    if (r.status == ResolveStatus.downloading) {
      _snack('Downloading from iCloud…');
      r = await LocalVideoAccess.instance.waitForDownload(r);
    }
    final video = r.video;
    if (video == null || !r.isReady) {
      _snack(r.message ?? kNotAVideoMessage);
      return;
    }
    if (_ended || !mounted) {
      await video.release();
      return;
    }
    trackLocalVideoChosen(ChoiceSource.recent);
    await _playChosenVideo(video, source: ChoiceSource.recent);
  }

  /// Everything after a video was chosen: open it, then (host) offer to share it.
  Future<void> _playChosenVideo(LocalVideo video, {required ChoiceSource source}) async {
    trace(
      'local file picked',
      category: 'media',
      data: {
        'platform': Platform.operatingSystem,
        'source': source.name,
        'origin': video.origin.name,
        'file': video.name,
        'name_has_non_ascii': video.name.runes.any((r) => r > 127),
        'content_uri': video.isContentUri,
        'bytes': video.sizeBytes,
        'normalized': _redactPaths(Media(video.mediaUri).uri),
      },
    );
    _isStreamingRemoteSharedMedia = false;
    if (_ended || !mounted) {
      await video.release();
      return;
    }
    final opened = await _adoptLocalVideo(video);
    // If host, handle media sharing prompt / upload
    if (opened && (_sync?.isHost ?? false)) {
      unawaited(_handleHostMediaSharingPrompt(video));
    }
  }

  Future<void> _onRecentsChanged() async {
    final list = await RecentVideos.instance.list();
    if (!mounted) return;
    final newest = list.isEmpty ? null : list.first;
    if (newest?.id != _lastRecent?.id) setState(() => _lastRecent = newest);
  }

  /// The newest Recent entry as the empty room's Reopen line, unless it is the
  /// file already open.
  bool get _reopenOffered => _lastRecent != null && _localVideo == null;

  Future<void> _handleHostMediaSharingPrompt(LocalVideo video) async {
    final name = video.name;
    final limits = EntitlementService.instance.limits;
    if (!(limits?.canShareMedia ?? false)) return;

    final prefs = await SharedPreferences.getInstance();
    final autoChoice = prefs.getBool('pt.media_sharing.remember_choice');
    bool shouldShare = false;

    if (autoChoice != null) {
      shouldShare = autoChoice;
    } else {
      if (!mounted) return;
      final source = video.uploadSource();
      final int size;
      try {
        size = await source.length();
      } catch (e, s) {
        reportNonFatal(e, s, during: 'sizing a local video for sharing');
        return;
      }
      if (!mounted) return;
      final result = await showMediaSharingPromptDialog(
        context: context,
        fileName: name,
        fileSize: size,
        // Our Room keeps the upload for a while after the session; every other room
        // removes it when the room closes.
        keepNote: (_room?.isOurRoom ?? false)
            ? ourRoomKeepNote(patron: PairService.instance.pair?.patron ?? false)
            : null,
      );
      if (result != null) {
        shouldShare = result.shouldShare;
        if (result.rememberChoice) {
          await prefs.setBool('pt.media_sharing.remember_choice', shouldShare);
        }
      }
    }

    if (shouldShare && mounted) {
      unawaited(_startMediaSharingUpload(video.uploadSource(), name));
    }
  }

  Future<void> _startMediaSharingUpload(UploadSource source, String name) async {
    // The same file twice (a re-pick with a remembered choice, a double Retry)
    // would only abort the upload already in flight.
    if (_isUploadingSharedMedia && _uploadingRef == source.reference) {
      trace('upload already running for this file', category: 'media', data: {'file': name});
      return;
    }
    final generation = ++_uploadGeneration;
    final int fileSize;
    try {
      fileSize = await source.length();
    } catch (e, s) {
      reportNonFatal(e, s, during: 'sizing a local video for sharing');
      _snack("Hmm, we can't read that video to share it. Pick it again to try once more.");
      return;
    }
    final limits = EntitlementService.instance.limitsOrFallback;
    final maxFileBytes = limits.mediaSharingMaxSizeBytes;
    if (fileSize > maxFileBytes) {
      final fileStr = Profile.formatBytes(fileSize);
      final maxStr = Profile.formatBytes(maxFileBytes);
      _snack('This video ($fileStr) exceeds the maximum single file limit ($maxStr).');
      if (mounted) {
        showMediaQuotaDialog(
          context,
          quotaContext: MediaQuotaContext(
            reason: .singleFileLimitExceeded,
            fileName: name,
            fileSize: fileSize,
            maxBytes: maxFileBytes,
          ),
        );
      }
      return;
    }

    final profile = ProfileService.instance.profile;
    if (limits.hasWeeklyQuota && profile != null) {
      final weeklyLimit = limits.mediaSharingWeeklyBytes;
      final remaining = profile.remainingWeeklyBytes(weeklyLimit);
      if (remaining >= 0 && fileSize > remaining) {
        final fileStr = Profile.formatBytes(fileSize);
        final remainingStr = Profile.formatBytes(remaining);
        _snack('This video ($fileStr) exceeds your remaining weekly quota ($remainingStr).');
        if (mounted) {
          showMediaQuotaDialog(
            context,
            quotaContext: MediaQuotaContext(
              reason: .weeklyQuotaExceeded,
              fileName: name,
              fileSize: fileSize,
              remainingBytes: remaining,
              maxBytes: weeklyLimit,
            ),
          );
        }
        return;
      }
    }

    _uploadingRef = source.reference;
    _isUploadingSharedMedia = true;
    _uploadFraction = 0.0;
    _uploadSpeedBps = 0.0;
    _uploadEtaSeconds = 0;
    _uploadState = 'uploading';
    _localReadyPromptDismissed = false;
    _sync?.setMediaUploadState('uploading');
    _sync?.broadcastSharingToggled(
      enabled: true,
      fileName: name,
      fileSize: fileSize,
      uploadState: 'uploading',
    );
    setState(() {});

    try {
      await _mediaSharingService.uploadFile(
        roomId: widget.roomId,
        source: source,
        onProgress: (p) {
          if (!mounted) return;
          setState(() {
            _uploadFraction = p.fraction;
            _uploadSpeedBps = p.speedBps;
            _uploadEtaSeconds = p.etaSeconds;
            _uploadState = p.state;
          });
        },
        syncService: _sync,
      );
      if (!mounted || generation != _uploadGeneration) return;
      _isUploadingSharedMedia = false;
      _uploadState = 'ready';
      _sync?.setMediaUploadState('ready');
      _sync?.broadcastSharingToggled(
        enabled: true,
        fileName: name,
        fileSize: fileSize,
        uploadState: 'ready',
      );
      unawaited(ProfileService.instance.load());
      setState(() {});
    } catch (e, s) {
      if (generation != _uploadGeneration) {
        trace('superseded upload ended', category: 'media', data: {'error': '$e'});
        return;
      }
      reportNonFatal(e, s, during: 'uploading shared media for room ${widget.roomId}');
      DiscoveryTriggers.instance.notify(NudgeReason.uploadFailed);
      if (!mounted) return;
      _isUploadingSharedMedia = false;
      _uploadState = 'failed';
      _sync?.setMediaUploadState('failed');
      _sync?.broadcastSharingToggled(enabled: false, fileName: name, uploadState: 'failed');
      setState(() {});
      final error = MediaSharingException.fromError(e);
      _snack(error.message);
      if (error.code == 'quota_exceeded' && mounted) {
        showMediaQuotaDialog(
          context,
          quotaContext: MediaQuotaContext(
            reason: .weeklyQuotaExceeded,
            fileName: name,
            fileSize: fileSize,
          ),
        );
      }
    }
  }

  Future<void> _retryLocalUpload() async {
    if (!(_sync?.isHost ?? false)) return;

    var video = _localVideo;
    if (video != null && !await _readable(video)) video = null;
    if (video == null) {
      // The handle is gone (or its file moved): try what this device remembers.
      final entry = await LocalMediaStore.instance.lookup(widget.roomId);
      if (entry != null && entry.fileStillExists) {
        var r = await entry.reopen();
        if (r.status == ResolveStatus.downloading) {
          r = await LocalVideoAccess.instance.waitForDownload(r);
        }
        video = r.video;
        if (video != null && mounted) {
          if (!identical(video, _localVideo)) unawaited(_localVideo?.release());
          _localVideo = video;
        }
      }
    }
    if (video != null && mounted) {
      unawaited(_startMediaSharingUpload(video.uploadSource(), _localFileName ?? video.name));
    } else if (mounted) {
      await _pickVideo();
    }
  }

  /// Whether [video]'s bytes can still be read (a moved file or a revoked
  /// Android grant says no).
  Future<bool> _readable(LocalVideo video) async {
    try {
      await video.uploadSource().length();
      return true;
    } catch (_) {
      return false;
    }
  }

  Widget? _mediaSharingPill({bool compact = false}) {
    if (_mode != .local) return null;

    if (!(_sync?.isHost ?? false)) {
      if (_isStreamingRemoteSharedMedia) {
        return const PTActionPill(label: 'Streaming from host', icon: Symbols.cloud_done_rounded);
      }
      return null;
    }

    if (_localFileName == null) return null;
    final limits = EntitlementService.instance.limits;
    if (!(limits?.canShareMedia ?? false)) return null;

    if (_uploadState == 'uploading' || _isUploadingSharedMedia) {
      final pct = (_uploadFraction * 100).toInt();
      return PTActionPill(
        label: 'Uploading $pct%',
        icon: BoothIcons.cloudUpload,
        onTap: _cancelMediaSharingUpload,
      );
    }

    if (_uploadState == 'failed') {
      return PTActionPill(
        label: 'Upload failed • Retry',
        icon: BoothIcons.restore,
        onTap: _retryLocalUpload,
      );
    }

    if (_uploadState == 'ready') {
      return const PTActionPill(label: 'Shared with room', icon: Symbols.cloud_done_rounded);
    }

    if (_uploadState == 'none') {
      return PTActionPill(
        label: 'Share with room',
        icon: BoothIcons.cloudUpload,
        onTap: _retryLocalUpload,
      );
    }

    return null;
  }

  /// The transient states (uploading, failed) as an icon, for a row too narrow
  /// for their label; the label rides the tooltip. Null when neither applies.
  Widget? _mediaSharingTransientIcon() {
    if (_mode != .local || !(_sync?.isHost ?? false) || _localFileName == null) return null;
    if (!(EntitlementService.instance.limits?.canShareMedia ?? false)) return null;
    if (_uploadState == 'uploading' || _isUploadingSharedMedia) {
      return PTIconButton(
        icon: BoothIcons.cloudUpload,
        size: 44,
        iconSize: 20,
        tooltip: 'Uploading ${(_uploadFraction * 100).toInt()}% - tap to cancel',
        onPressed: _cancelMediaSharingUpload,
      );
    }
    if (_uploadState == 'failed') {
      return PTIconButton(
        icon: BoothIcons.restore,
        size: 44,
        iconSize: 20,
        tooltip: 'Upload failed - tap to retry',
        onPressed: _retryLocalUpload,
      );
    }
    return null;
  }

  /// The resting media-sharing states as a header icon, for the portrait
  /// header where a pill costs a whole row. Null for the transient states
  /// (uploading, failed), whose label is the point.
  Widget? _mediaSharingIcon({double size = 44}) {
    // The theatre bar's square is a Rail outline (Desktop room board).
    final outlined = size < 44;
    if (_mode != .local) return null;
    final isHost = _sync?.isHost ?? false;
    if (!isHost) {
      return _isStreamingRemoteSharedMedia
          ? PTIconButton(
              icon: Symbols.cloud_done_rounded,
              size: size,
              outlined: outlined,
              iconSize: outlined ? 18 : 20,
              tooltip: 'Streaming from host',
            )
          : null;
    }
    if (_localFileName == null) return null;
    if (!(EntitlementService.instance.limits?.canShareMedia ?? false)) return null;
    if (_uploadState == 'uploading' || _isUploadingSharedMedia) return null;
    return switch (_uploadState) {
      'ready' => PTIconButton(
        icon: Symbols.cloud_done_rounded,
        size: size,
        outlined: outlined,
        iconSize: outlined ? 18 : 20,
        tooltip: 'Shared with room',
      ),
      'none' => PTIconButton(
        icon: BoothIcons.cloudUpload,
        size: size,
        outlined: outlined,
        iconSize: outlined ? 18 : 20,
        tooltip: 'Share with room',
        onPressed: _retryLocalUpload,
      ),
      _ => null,
    };
  }

  Future<void> _cancelMediaSharingUpload() async {
    _isUploadingSharedMedia = false;
    _uploadState = 'none';
    _sync?.setMediaUploadState('none');
    _sync?.broadcastSharingToggled(enabled: false, uploadState: 'none');
    setState(() {});
    await _mediaSharingService.abortUpload(roomId: widget.roomId);
  }

  /// Plays [video] and remembers it. Takes ownership of its handle: on success
  /// the previous video is released, on failure this one is. True when opened.
  Future<bool> _adoptLocalVideo(LocalVideo video, {Duration? seekTo}) async {
    final name = video.name;
    _localLoadWatchdog?.cancel();
    _localLoadStalled = false;
    _openFailedFor = null;
    _isStreamingRemoteSharedMedia = false;
    _bufferPosition = null;
    unawaited(_stream?.reset());
    try {
      await _player.open(Media(video.mediaUri), play: false);
      unawaited(_suppressSecondarySubtitles());
      unawaited(_preferTextSubtitleOnOpen());
      try {
        await (_player.platform as dynamic)?.setProperty('sub-auto', 'fuzzy');
      } catch (_) {}
      final path = video.path;
      if (path != null) {
        unawaited(_loadSidecarSubtitles(path));
      }
    } catch (e, s) {
      reportNonFatal(e, s, during: 'opening a local video file');
      unawaited(video.release());
      if (!mounted) return false;
      trace('local file would not open', category: 'media', data: {'file': name});
      setState(() => _openFailedFor = name);
      _snack("We couldn't open that file. Try another copy, or a different file.");
      _updateReadiness();
      return false;
    }
    if (!mounted) {
      unawaited(video.release());
      return false;
    }
    trace('local file open issued', category: 'media', data: {'file': name});
    final previous = _localVideo;
    _localVideo = video;
    if (previous != null && !identical(previous, video)) unawaited(previous.release());
    if (_player.state.duration != Duration.zero) {
      _duration = _player.state.duration;
    }
    _localFileName = name;
    _mismatchDismissed = false;
    _armLocalLoadWatchdog(name);
    if (_sync?.isHost ?? false) {
      final provisional = RoomMedia(
        kind: .local,
        name: name,
        duration: _duration == Duration.zero ? null : _duration,
      );
      _canonicalMedia = provisional;
      _sync?.setProvisionalCanonicalMedia(provisional);
      _sync?.updatePlaybackState('local', null);
    }
    if (_awaitingFirstSource) _resolveFirstSource();
    unawaited(
      LocalMediaStore.instance.record(
        roomId: widget.roomId,
        name: name,
        path: video.path,
        reference: video.reference,
      ),
    );
    unawaited(_rememberRecent(video));
    if (video.path != null) unawaited(PhotoExports.instance.touch(video.path!));
    unawaited(_announceLocalFile(name));
    if (seekTo != null) unawaited(_seekOnceLoaded(seekTo, name));
    setState(() {});
    _updateReadiness();
    return true;
  }

  /// Adds the open file to Recent (durable files only - Photos exports are
  /// declined there) and arranges its thumbnail: one still, taken a couple of
  /// seconds into the first real playback, only when the entry has none yet.
  Future<void> _rememberRecent(LocalVideo video) async {
    _thumbWait?.cancel();
    _thumbWait = null;
    _recentId = null;
    final entry = await RecentVideos.instance.record(video);
    if (entry == null || !mounted || !identical(_localVideo, video)) return;
    _recentId = entry.id;
    if (_player.state.duration > Duration.zero) {
      unawaited(RecentVideos.instance.updateDuration(entry.id, _player.state.duration));
    }
    if (await RecentVideos.instance.thumbnailFile(entry.id) != null) return;
    if (!mounted || !identical(_localVideo, video)) return;
    _thumbWait = _player.stream.playing.where((playing) => playing).listen((_) {
      _thumbWait?.cancel();
      _thumbWait = null;
      unawaited(_saveRecentThumbnail(entry.id, video));
    });
  }

  Future<void> _saveRecentThumbnail(String id, LocalVideo video) async {
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted || !identical(_localVideo, video) || _mode != .local) return;
    try {
      final bytes = await _player.screenshot();
      if (bytes != null && mounted && identical(_localVideo, video)) {
        await RecentVideos.instance.saveThumbnail(id, bytes);
      }
    } catch (e) {
      // Cosmetic: the shelf keeps its placeholder.
      trace('recent thumbnail not saved', category: 'media', data: {'error': '$e'});
    }
  }

  Future<void> _startStreamingSharedMedia(String fileName, {Duration? seekTo}) async {
    if (_startingSharedStream) return;
    _startingSharedStream = true;
    try {
      final dl = await _mediaSharingService.fetchDownloadUrl(roomId: widget.roomId);
      if (!mounted || _ended) return;
      _isStreamingRemoteSharedMedia = true;
      _localFileName = fileName;
      _recentId = null;
      _localLoadWatchdog?.cancel();
      _localLoadStalled = false;
      final source = await (_stream ??= _newStreamSession()).start(
        dl,
        duration: _canonicalMedia.duration,
      );
      if (!mounted || _ended) return;
      await _player.open(Media(source.toString()), play: false);
      unawaited(_preferTextSubtitleOnOpen());
      unawaited(_suppressSecondarySubtitles());
      _armLocalLoadWatchdog(fileName);
      if (seekTo != null) unawaited(_seekOnceLoaded(seekTo, fileName));
      setState(() {});
      _updateReadiness();
    } catch (e, s) {
      reportNonFatal(e, s, during: 'streaming shared media for room ${widget.roomId}');
      if (mounted) _snack("Failed to load shared media. You can locate your own copy.");
    } finally {
      _startingSharedStream = false;
    }
  }

  Future<void> _seekOnceLoaded(Duration position, String name) async {
    try {
      await _player.stream.duration
          .firstWhere((d) => d != Duration.zero)
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      return;
    }
    if (!mounted || _mode != .local || _localFileName != name) return;
    if (_sync?.hasReceivedInitialState ?? false) return;
    trace(
      'resuming at the held room position',
      category: 'room',
      data: {'room_id': widget.roomId, 'position_ms': position.inMilliseconds},
    );
    _player.seek(position);
  }

  Future<void> _resumeFromCanonicalMedia() async {
    if (_resumeAttempted || _ended || !mounted) return;
    final media = _canonicalMedia;
    if (!media.isSet) return;
    _resumeAttempted = true;
    final held = resumeSeekPosition(held: _room?.mediaPosition, mediaDuration: media.duration);

    if (media.kind == .youtube) {
      final url = media.url;
      if (url == null || _youtubeUrl != null) return;
      trace(
        'resuming a youtube room from its canonical media',
        category: 'room',
        data: {'room_id': widget.roomId, 'position_ms': held?.inMilliseconds},
      );
      _resolveFirstSource();
      _switchToYouTubeMode(url);
      if (held != null && !(_sync?.hasReceivedInitialState ?? false)) _pendingYtSeek = held;
      return;
    }

    if (kDemoMode || LiveKitService.isMockMode) {
      _resolveFirstSource();
      _idleSourceTimer?.cancel();
      _localFileName = media.name ?? 'Cosmic_Voyage_CC_4K.mp4';
      _duration = media.duration ?? const Duration(hours: 2, minutes: 49, seconds: 3);
      _position = _room?.mediaPosition ?? const Duration(hours: 1, minutes: 24, seconds: 18);
      _playing = true;
      _updateReadiness();
      setState(() {});
      return;
    }

    final entry = await LocalMediaStore.instance.lookup(widget.roomId);
    if (!mounted || _ended) return;
    var storedFileUsable = entry?.fileStillExists ?? false;
    if (shouldAutoReopenLocalFile(
      media: media,
      storedFileName: entry?.name,
      storedFileExists: entry?.fileStillExists ?? false,
      loadedFileName: _localFileName,
      isPickerOpen: _isFilePickerOpen,
    )) {
      trace(
        'reopening the local file this device had for the room',
        category: 'room',
        data: {'room_id': widget.roomId, 'position_ms': held?.inMilliseconds},
      );
      _resolveFirstSource();
      _idleSourceTimer?.cancel();
      var r = await entry!.reopen();
      if (r.status == ResolveStatus.downloading) {
        r = await LocalVideoAccess.instance.waitForDownload(r);
      }
      final reopened = r.video;
      if (!mounted || _ended) {
        await reopened?.release();
        return;
      }
      if (reopened != null && r.isReady) {
        await _adoptLocalVideo(reopened, seekTo: held);
        return;
      }
      // The file moved, or the grant lapsed: fall through to the shared copy
      // (if the host uploaded one); otherwise the gate's Locate button is it.
      storedFileUsable = false;
      trace(
        'remembered room file is unavailable',
        category: 'room',
        data: {'room_id': widget.roomId, 'file': entry.name, 'reason': r.reason?.name},
      );
    }

    // Auto-stream shared media if room has ready shared media and local disk copy not found
    if ((_sync?.mediaUploadState == 'ready' ||
            _room?.mediaUploadState == 'ready' ||
            _uploadState == 'ready') &&
        _localFileName != media.name) {
      trace(
        'auto-streaming shared media for local mode',
        category: 'room',
        data: {'room_id': widget.roomId, 'file': media.name},
      );
      _resolveFirstSource();
      _idleSourceTimer?.cancel();
      if (shouldNoteStreamingFallback(
        isHost: _sync?.isHost ?? false,
        mediaName: media.name,
        storedFileName: entry?.name,
        storedFileUsable: storedFileUsable,
      )) {
        trace(
          'streaming the shared copy because the remembered file is gone',
          category: 'room',
          data: {'room_id': widget.roomId, 'file': media.name},
        );
        setState(() => _streamingFallbackNotice = true);
      }
      unawaited(_startStreamingSharedMedia(media.name!, seekTo: held));
    }
  }

  Future<void> _persistPosition() async {
    final sync = _sync;
    if (sync == null || _ended || !mounted) return;
    if (!sync.isAuthority || !_canonicalMedia.isSet) return;
    final position = _position;
    final last = _lastWrittenPosition;
    if (last != null && (position - last).abs() < const Duration(seconds: 5)) return;
    _lastWrittenPosition = position;
    final written = await RoomService.instance.updateMediaPosition(
      roomId: widget.roomId,
      position: position,
    );
    if (written) {
      _positionWriteFailures = 0;
    } else if (++_positionWriteFailures == _kPositionWriteFailureReport) {
      trace(
        'the room position write keeps failing',
        category: 'room',
        data: {
          'room_id': widget.roomId,
          'position_ms': position.inMilliseconds,
          'failures': _positionWriteFailures,
        },
      );
    }
  }

  static final _pathLike = RegExp(r'(?:[A-Za-z]:)?(?:[\\/][^\s\\/]+)+');
  static String _redactPaths(String text) => text.replaceAllMapped(_pathLike, (match) {
    final leaf = match[0]!.split(RegExp(r'[\\/]')).last;
    return leaf.isEmpty ? '…' : '…/$leaf';
  });

  void _onPlayerLog(PlayerLog log) {
    if (log.level != 'warn' && log.level != 'error' && log.level != 'fatal') return;
    trace(
      'mpv ${log.level}: ${_redactPaths(log.text)}',
      category: 'media',
      data: {'prefix': log.prefix, 'mode': _mode.name},
    );
  }

  SharedStreamSession _newStreamSession() => SharedStreamSession(
    roomId: widget.roomId,
    fetchUrl: () => _mediaSharingService.fetchDownloadUrl(roomId: widget.roomId),
    cache: _streamCache,
    device: _streamDevice(),
    setOption: (key, value) async {
      final native = _player.platform;
      if (native is NativePlayer) await native.setProperty(key, value);
    },
    readOption: (key) async {
      final native = _player.platform;
      return native is NativePlayer ? await native.getProperty(key) : null;
    },
    mpvCacheBps: () async {
      final native = _player.platform;
      if (native is! NativePlayer) return null;
      final raw = double.tryParse(await native.getProperty('cache-speed'));
      return raw == null ? null : raw * 8;
    },
    bufferedAhead: () {
      final buffer = _bufferPosition;
      if (buffer == null || buffer <= _position) return Duration.zero;
      return buffer - _position;
    },
    remaining: () => _duration > _position ? _duration - _position : Duration.zero,
    onChanged: () {
      if (mounted) setState(() {});
    },
    onReadinessChanged: () {
      if (mounted) _updateReadiness();
    },
    onProxyFatal: (_) => unawaited(_recoverFromStream403(direct: true)),
  );

  StreamDeviceClass _streamDevice() {
    if (!isMobile) return .desktop;
    return MediaQuery.sizeOf(context).shortestSide >= 600 ? .tablet : .phone;
  }

  /// Reopens the shared stream after an error, keeping position and the
  /// viewer's audio and subtitle choice. Through the proxy a 403 never reaches
  /// mpv (the proxy re-signs); this path is for a direct stream, and for the
  /// proxy giving up ([direct]), where it falls back to the origin URL.
  Future<void> _recoverFromStream403({bool direct = false}) async {
    if (_recoveringStream403 || !mounted || _ended) return;
    _recoveringStream403 = true;
    try {
      final currentPos = _position;
      final audioTrack = _player.state.track.audio;
      final subtitleTrack = _player.state.track.subtitle;

      final session = _stream;
      final Uri source;
      if (session == null) {
        source = (await _mediaSharingService.fetchDownloadUrl(roomId: widget.roomId)).streamUrl;
      } else if (direct) {
        trace('streaming direct after the proxy gave up', category: 'media');
        source = await session.fallBackToDirect();
      } else {
        source = await session.reopenSource();
      }
      if (!mounted || _ended) return;

      await _player.open(Media(source.toString()), play: _playing);
      if (currentPos > Duration.zero) {
        _player.seek(currentPos);
      }
      _player.setAudioTrack(audioTrack);
      _player.setSubtitleTrack(subtitleTrack);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'recovering from stream 403');
      _surfaceLocalLoadFailure();
    } finally {
      _recoveringStream403 = false;
    }
  }

  void _onPlayerError(String error) {
    if (_mode != .local) return;
    if (_isStreamingRemoteSharedMedia &&
        (error.contains('403') || error.toLowerCase().contains('forbidden'))) {
      unawaited(_recoverFromStream403());
      return;
    }
    // The bundled mpv lacks some codecs (TrueHD, notably). That is a property
    // of the file, not a bug: the rest of it still plays, so say which track
    // is silent instead of reporting it.
    final codec = RegExp(r"Failed to initialize a decoder for codec '([^']+)'").firstMatch(error);
    if (codec != null) {
      final name = codec.group(1)!;
      trace('unsupported codec', category: 'media', data: {'codec': name});
      if (_unsupportedCodecNoted.add('$_localFileName/$name')) {
        _snack(
          "This file's ${name.toUpperCase()} track can't play here - try another audio track.",
        );
      }
      return;
    }
    // No usable output device (unplugged, exclusive-mode hog, remote session):
    // mpv carries on silently and the video still plays. A property of the
    // machine, not a bug - say so once instead of reporting.
    if (error.toLowerCase().contains('audio device')) {
      trace('audio output unavailable', category: 'media');
      if (!_audioDeviceNoted) {
        _audioDeviceNoted = true;
        _snack("Couldn't find a sound output on this device - check your speakers or headphones.");
      }
      return;
    }
    // A file mpv cannot parse (not a video, truncated, an unsupported
    // container) is a property of the file, like the codec case above.
    if (error.contains('Failed to recognize file format')) {
      trace('unrecognised file format', category: 'media');
      if (_localFileName != null && _duration == Duration.zero) _surfaceLocalLoadFailure();
      return;
    }
    // The OS refused read access (moved to a protected folder, sandbox
    // bookmark gone, drive unmounted): a property of the machine, not a bug.
    if (error.contains('Operation not permitted') || error.contains('Permission denied')) {
      trace('local file not readable', category: 'media');
      if (_localFileName != null && _duration == Duration.zero) _surfaceLocalLoadFailure();
      return;
    }
    reportNonFatal(
      StateError('mpv: ${_redactPaths(error)}'),
      StackTrace.current,
      during: 'opening a local video file',
    );
    if (_localFileName != null && _duration == Duration.zero) _surfaceLocalLoadFailure();
  }

  void _armLocalLoadWatchdog(String name, {bool extended = false}) {
    _localLoadWatchdog?.cancel();
    _localLoadWatchdog = Timer(Duration(seconds: extended ? 30 : 15), () {
      if (!mounted || _mode != .local || _localFileName != name) return;
      if (_duration != Duration.zero) return;
      // A slow disk or network share is still working, not dead: give a
      // buffering file one longer window before calling it a failure.
      if (!extended && _player.state.buffering) {
        trace('local load slow, extending watchdog', category: 'media', data: {'file': name});
        _armLocalLoadWatchdog(name, extended: true);
        return;
      }
      final dot = name.lastIndexOf('.');
      trace(
        'local load stalled',
        category: 'media',
        data: {
          'file': name,
          'extension': dot >= 0 ? name.substring(dot + 1).toLowerCase() : '',
          'buffering': _player.state.buffering,
          'extended': extended,
          'platform': Platform.operatingSystem,
          'os_version': Platform.operatingSystemVersion,
        },
      );
      reportNonFatal(
        StateError('local file never reported a duration within ${extended ? 45 : 15}s'),
        StackTrace.current,
        during: 'opening a local video file',
      );
      _surfaceLocalLoadFailure();
    });
  }

  void _surfaceLocalLoadFailure() {
    if (_localLoadStalled) return;
    _localLoadStalled = true;
    _localLoadWatchdog?.cancel();
    setState(() => _openFailedFor = _localFileName);
    _snack("We couldn't open that file. Try another copy, or a different file.");
  }

  /// The display name AND the gate's identity for a picked file, so it has to
  /// be stable across platforms. `path` is already human-readable; `uri` is
  /// percent-encoded (`Movie%20(2005).mkv`), which is both ugly on screen and
  /// a false mismatch against a peer whose picker returned a plain path.
  String _basename(FastFilePickerPath response) {
    final path = response.path;
    if (path != null) return path.split(RegExp(r'[/\\]')).last;
    final last = (response.uri ?? '').split(RegExp(r'[/\\]')).last;
    try {
      return Uri.decodeComponent(last);
    } catch (_) {
      return last; // a stray '%' that isn't an escape sequence
    }
  }

  /// Duration only arrives async after `open`. If it never does, announce
  /// without it rather than never announcing at all - silence would leave the
  /// room with no canonical media and the gate shut forever.
  Future<void> _announceLocalFile(String name) async {
    var duration = Duration.zero;
    try {
      duration = await _player.stream.duration
          .firstWhere((d) => d != Duration.zero)
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Silent by design: the timeout *is* the fallback path described above.
    }
    if (!mounted) return;
    await _sync?.broadcastFileInfo(name, duration);
    await _publishCanonicalMedia(
      .local,
      name: name,
      duration: duration == Duration.zero ? null : duration,
    );
  }

  /// Host only - the RPC rejects everyone else, so this no-ops for members
  /// (whose picker exists to locate their own copy, not to set the room's).
  /// Persist first: the row is what reaches late joiners and outlives the host.
  Future<void> _publishCanonicalMedia(
    RoomMediaKind kind, {
    String? name,
    Duration? duration,
    String? url,
  }) async {
    final sync = _sync;
    if (sync == null || !sync.isHost) return;
    try {
      final room = await RoomService.instance.setRoomMedia(
        roomId: widget.roomId,
        kind: kind,
        name: name,
        duration: duration,
        url: url,
      );
      if (!mounted) return;
      await sync.broadcastMediaSet(RoomMedia.fromRoom(room));
    } catch (e, s) {
      final failure = RoomErrorCode.fromError(e);
      if (failure == .unknown) {
        reportNonFatal(e, s, during: 'setting the canonical media for room ${widget.roomId}');
      }
      if (mounted) _snack(failure.message);
    }
  }

  void _onCanonicalMedia(RoomMedia media) {
    // `media_set` and its `mode_switch` are separate broadcasts and can land in
    // either order. Drop our YouTube buffer flag the moment the room's video
    // changes, or the gate reads "ready" for the *previous* video for a beat -
    // long enough to auto-resume into the wrong thing.
    if (!_isSameYouTubeVideo(media)) {
      _ytBufferFallbackTimer?.cancel();
      _ytBufferFallbackTimer = null;
      _ytBufferReady = false;
      // Re-arm, or a reset that lands after the embed went idle would strand
      // us on "Loading" with nothing left to flip it.
      if (media.kind == .youtube && _youtubeController != null) {
        _armYouTubeReadyFallback();
      }
    }
    setState(() {
      _canonicalMedia = media;
      _mismatchDismissed = false;
    });
    // The room has something now, chosen by someone else (a broadcast never comes
    // back to its sender): the chooser we were still showing has nothing left to ask.
    if (media.isSet) {
      if (_awaitingFirstSource) _resolveFirstSource();
      _dismissSourceDialogs();
    }
    _publishMenuData();
    _updateReadiness();
    // The first media this screen sees goes through the resume path (held position,
    // the remembered local copy, the fallback notice); only a change after that is
    // adopted here.
    final firstMedia = !_resumeAttempted;
    unawaited(_resumeFromCanonicalMedia());
    if (!firstMedia && media.kind == .local) _streamSharedMediaIfNeeded(media.name);
  }

  /// Starts streaming the room's shared copy when it is ready and this device is not
  /// the one that uploaded it (the uploader, and anyone who opened their own copy
  /// under the same name, already has the file). Safe to call from every signal that
  /// can mean "it is ready now": it does nothing twice.
  void _streamSharedMediaIfNeeded(String? fileName) {
    if (!mounted || fileName == null) return;
    final ready =
        _sync?.mediaUploadState == 'ready' ||
        _room?.mediaUploadState == 'ready' ||
        _uploadState == 'ready';
    if (!shouldStreamSharedCopy(
      ended: _ended,
      uploadingHere: _isUploadingSharedMedia,
      shareReady: ready,
      fileName: fileName,
      loadedFileName: _localFileName,
      alreadyStarting: _startingSharedStream,
    )) {
      return;
    }
    trace(
      'streaming the shared copy as it became ready',
      category: 'media',
      data: {'room_id': widget.roomId, 'file': fileName},
    );
    _resolveFirstSource();
    _idleSourceTimer?.cancel();
    _dismissSourceDialogs();
    unawaited(_startStreamingSharedMedia(fileName));
  }

  // ---------------------------------------------------------------------------
  // Readiness: derive our own status from local state and push it onto
  // presence. Cheap to call from anywhere - retrackReadiness no-ops when
  // nothing actually changed.
  // ---------------------------------------------------------------------------

  void _updateReadiness() {
    _sync?.retrackReadiness(
      _computeReadiness(),
      loadedFileName: _mode == .local ? _localFileName : null,
      loadedDuration: _mode == .local && _duration > Duration.zero ? _duration : null,
    );
    _syncGateReveal();
  }

  ReadyStatus _computeReadiness() {
    if (_isModeSelectionDialogOpen || _isYouTubeUrlDialogOpen || _isFilePickerOpen) {
      return .selecting;
    }
    switch (_canonicalMedia.kind) {
      case .none:
        return .none; // nothing has been picked for the room yet
      case .local:
        if (_localFileName == null) return .none;
        // `ready` means "a file is fully open", NOT "the right file" - the gate
        // compares loadedFileName against canonical itself, so the UI can tell
        // "still loading" apart from "loaded the wrong thing".
        if (_stream?.holdingForBuffer ?? false) return .loading;
        return _duration == Duration.zero ? .loading : .ready;
      case .youtube:
        return _ytBufferReady ? .ready : .loading;
    }
  }

  /// Both `unstarted` (-1, initial state when player embeds with a videoId) and
  /// `cued` (5, when cueVideoById is called) indicate the video is fetched and
  /// ready to start playback immediately.
  void _updateYouTubeReadiness(PTYouTubeController controller) {
    if (_ytBufferReady) return;
    // An active ad must complete before the member can be considered ready to sync.
    if (controller.isAdPlaying) return;
    final PTYtPlayerState state = controller.playerState;
    final loaded =
        state == .unstarted ||
        state == .cued ||
        state == .buffering ||
        state == .playing ||
        state == .paused;
    if (!controller.isReady || !loaded) return;
    _ytBufferFallbackTimer?.cancel();
    _ytBufferFallbackTimer = null;
    _ytBufferReady = true;
    _updateReadiness();
  }

  /// Whether canonical media is the video this client already has embedded.
  /// Compared by **video id**, not raw URL: canonical is whatever
  /// `set_room_media` stored (trimmed, capped), while `_youtubeUrl` is the raw
  /// string `mode_switch` carried, so the two are routinely not
  /// string-identical for the same video. Treating that as a video change
  /// wiped readiness on members who had already loaded it.
  bool _isSameYouTubeVideo(RoomMedia media) {
    if (media.kind != .youtube) return false;
    final current = _youtubeUrl;
    if (current == null) return false;
    final canonicalId = youtubeVideoId(media.url ?? '');
    return canonicalId != null && canonicalId == youtubeVideoId(current);
  }

  /// The D6 fallback, armed when the embed is created rather than from the
  /// player listener. The controller only notifies on value *changes*, so a
  /// member who never presses play gets a short burst of events during init
  /// and then silence - arming from the listener meant that if the flag was
  /// ever cleared afterwards, nothing existed to re-arm it and they sat on
  /// "Loading" forever while the host (whose player keeps emitting) went ready.
  void _armYouTubeReadyFallback() {
    _ytBufferFallbackTimer?.cancel();
    final delay = (kDemoMode || LiveKitService.isMockMode)
        ? const Duration(milliseconds: 600)
        : const Duration(seconds: 10);
    _ytBufferFallbackTimer = Timer(delay, () {
      if (!mounted || _ytBufferReady) return;
      if (_youtubeController?.isAdPlaying == true) {
        // Still in ad, do not falsely declare readiness while an ad is running;
        // re-arm the fallback to check again.
        _armYouTubeReadyFallback();
        return;
      }
      trace('youtube readiness fallback fired', category: 'youtube');
      _ytBufferReady = true;
      _updateReadiness();
    });
  }

  /// We are ready with a file the room does not recognise as its movie (name
  /// and length both differ). Offered as a way out, never a wall: the member
  /// can vouch for their copy, which the whole room then honours.
  bool get _suspectWrongFile {
    final sync = _sync;
    if (sync == null || _mode != .local || !_canonicalMedia.isSet) return false;
    if (_canonicalMedia.kind != .local || _canonicalMedia.name == null) return false;
    if (_localFileName == null || _duration == Duration.zero) return false;
    final self = _present.where((m) => m.userId == sync.userId).firstOrNull;
    return self != null && self.isReady && !sync.memberSatisfiesGate(self);
  }

  void _confirmSameMovie() {
    _sync?.confirmSameMedia();
    setState(() {});
  }

  /// The old "different file loaded" banner is gone - the readiness overlay
  /// now says who is missing what, in better words, and the gate stops
  /// playback outright. What survives is the case the gate deliberately does
  /// NOT block on: right name, suspiciously different length (D3's soft
  /// warning). Non-gating by design, so it stays dismissible.
  bool get _durationDrifts {
    final roomFile = _roomFile;
    if (_mode != .local || roomFile == null || _mismatchDismissed) return false;
    if (_localFileName != roomFile.name) return false;
    return _duration != Duration.zero &&
        roomFile.duration != Duration.zero &&
        (_duration - roomFile.duration).abs() > const Duration(seconds: 2);
  }

  // ---------------------------------------------------------------------------
  // User playback actions (act locally + broadcast; play/pause also seek)
  // ---------------------------------------------------------------------------

  /// Non-host while the host holds the remote (D10).
  bool get _transportLocked => (_sync?.transportLock ?? false) && !(_sync?.isHost ?? false);

  /// Why the transport can't be used right now, or null when it can.
  /// `indeterminate` deliberately reads as usable: before presence syncs we
  /// don't know who's here, and blocking on a guess makes entry feel broken.
  String? get _transportBlockedReason {
    if (_transportLocked) return 'The host has the remote.';
    if (_gateState != GateState.closed) return null;
    if (!_canonicalMedia.isSet) {
      return (_sync?.isHost ?? false)
          ? 'Pick something to watch first.'
          : 'Waiting for the host to pick something to watch.';
    }
    final blocker = _sync?.gateBlocker;
    final what = _canonicalMedia.name ?? 'the video';
    if (blocker == null) return "Holding the curtain until everyone's ready.";
    if (blocker.userId == _sync?.userId) return 'Load $what to join in.';
    return 'Holding the curtain for ${blocker.displayName}, loading $what.';
  }

  /// Host only. D9: whether the member may come back is chosen per kick, not
  /// once as a room setting.
  Future<void> _confirmKick(PresentMember member) async {
    final allowRejoin = await showGlassDialog<bool>(
      context: context,
      width: 420,
      builder: (_) => KickMemberDialog(displayName: member.displayName),
    );
    if (allowRejoin == null || !mounted) return;
    try {
      await RoomService.instance.kickMember(
        roomId: widget.roomId,
        userId: member.userId,
        allowRejoin: allowRejoin,
      );
      // Deleting the row doesn't eject them: Realtime authorizes at subscribe
      // time, so an already-connected client keeps receiving until it
      // resubscribes. The broadcast is what actually removes them.
      await _sync?.broadcastMemberKicked(member.userId);
      if (mounted) {
        _snack('Removed ${member.displayName} from the room.', kind: .success);
      }
    } catch (e, s) {
      final failure = RoomErrorCode.fromError(e);
      if (failure == .unknown) reportNonFatal(e, s, during: 'removing a member from the room');
      if (mounted) _snack(failure.message);
    }
  }

  Future<void> _confirmAssignHost(RoomMember member) async {
    final confirmed = await showGlassDialog<bool>(
      context: context,
      width: 400,
      builder: (dialogContext) => Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: [
          Row(
            spacing: 10,
            children: [
              const Icon(BoothIcons.star, size: 22, color: PTColors.warning),
              Text('Assign host', style: PTText.screenTitle.copyWith(fontSize: 18)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Make ${member.displayName} the host of this room? They will receive full host controls including media playback selection, kicking participants, and ending or extending the session.',
            style: PTText.body.copyWith(color: PTColors.white(0.8), height: 1.45),
          ),
          const SizedBox(height: 20),
          Row(
            spacing: 10,
            children: [
              Expanded(
                child: PTButton(
                  label: 'Cancel',
                  variant: .secondary,
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                ),
              ),
              Expanded(
                child: PTButton(
                  label: 'Make host',
                  variant: .primary,
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await RoomService.instance.assignHost(roomId: widget.roomId, userId: member.userId);
      await _sync?.broadcastHostAssigned(member.userId);
      final members = await RoomService.instance.fetchMembers(widget.roomId);
      if (!mounted) return;
      setState(() => _members = members);
      final selfRole = members.where((m) => m.userId == _sync?.userId).firstOrNull?.role;
      if (selfRole != null) {
        _sync?.updateRole(selfRole);
      }
      _publishMenuData();
      _snack('${member.displayName} is now the host.', kind: .success);
    } catch (e, s) {
      final failure = RoomErrorCode.fromError(e);
      if (failure == .unknown) reportNonFatal(e, s, during: 'assigning host');
      if (mounted) _snack(failure.message);
    }
  }

  void _onHostAssignedRemotely(String newHostUserId) async {
    try {
      final members = await RoomService.instance.fetchMembers(widget.roomId);
      if (!mounted) return;
      setState(() => _members = members);
      unawaited(_refreshMemberTiers());
      final selfRole = members.where((m) => m.userId == _sync?.userId).firstOrNull?.role;
      if (selfRole != null) {
        final wasHost = _sync?.isHost ?? false;
        _sync?.updateRole(selfRole);
        if (!wasHost && (_sync?.isHost ?? false)) {
          _snack('You are now the room host.', kind: .info);
        } else if (newHostUserId != _sync?.userId) {
          final hostName =
              members.where((m) => m.userId == newHostUserId).firstOrNull?.displayName ??
              'A member';
          _snack('$hostName is now the room host.', kind: .info);
        }
      }
      _publishMenuData();
    } catch (e, s) {
      reportNonFatal(e, s, during: 'refreshing members after host assignment');
    }
  }

  /// Report and optionally block someone.
  ///
  /// Called three ways: from the flag on a chat bubble (which knows exactly
  /// who and what), from the member list (which knows who), and from the
  /// overflow menu's generic entry (which knows neither, and so asks). The
  /// generic entry is kept because a safety affordance that only exists on a
  /// message is one you cannot find when you need it.
  Future<void> _showReportDialog({
    String? targetUserId,
    String? targetUser,
    String? messageSnippet,
  }) async {
    var userId = targetUserId;
    var name = targetUser;

    if (userId == null) {
      final picked = await _pickReportTarget();
      if (picked == null || !mounted) return;
      userId = picked.userId;
      name = picked.displayName;
    }

    final outcome = await showReportDialog(
      context,
      targetName: name ?? 'this person',
      roomCode: _room?.code,
      messageSnippet: messageSnippet,
      alreadyBlocked: ModerationService.instance.isBlocked(userId),
    );
    if (outcome == null || !mounted) return;

    final moderation = ModerationService.instance;
    try {
      // The block goes first: it is the part the user needs to have worked,
      // and it is the part that must survive a failing report.
      if (outcome.block) {
        await moderation.block(
          userId,
          roomId: widget.roomId,
          reason: outcome.reason,
          messageExcerpt: messageSnippet,
        );
      }
      await moderation.report(
        userId: userId,
        reason: outcome.reason,
        roomId: widget.roomId,
        details: outcome.details,
        messageExcerpt: messageSnippet,
        mediaKind: _room?.mediaKind.wire,
        mediaTitle: _room?.mediaName,
        mediaSourceUrl: _room?.mediaUrl,
        roomCode: _room?.code,
      );
      if (!mounted) return;
      _snack(
        outcome.block
            ? "Thanks, we're reviewing this, and you won't see ${name ?? 'them'} any more."
            : "Thanks, we're reviewing this report.",
        kind: .success,
      );
    } catch (_) {
      // Both paths already reported the cause; the user gets the friendly half.
      if (!mounted) return;
      _snack(
        moderation.isBlocked(userId)
            ? "You won't see ${name ?? 'them'} any more, but the report didn't send. Try again${_orEmailSupport()}."
            : "That didn't send. Try again${_orEmailSupport()}.",
      );
    }
  }

  /// Asks which of the people here the report is about.
  Future<RoomMember?> _pickReportTarget() async {
    final selfId = _sync?.userId;
    final others = _members.where((m) => m.userId != selfId).toList(growable: false);
    if (others.isEmpty) {
      _snack("There's nobody else here to report.", kind: .info);
      return null;
    }
    return showGlassDialog<RoomMember>(
      context: context,
      width: 400,
      builder: (dialogContext) => Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: [
          Row(
            spacing: 10,
            children: [
              const Icon(BoothIcons.flag, size: 22, color: PTColors.warningBorder),
              Expanded(
                child: Text('Who is this about?', style: PTText.screenTitle.copyWith(fontSize: 18)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final member in others)
            PTPressable(
              onTap: () => Navigator.of(dialogContext).pop(member),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
                child: Row(
                  spacing: 12,
                  children: [
                    PTAvatar(
                      userId: member.userId,
                      displayName: member.displayName,
                      avatarUrl: member.profile?.avatarUrl,
                      size: 32,
                    ),
                    Expanded(
                      child: Text(
                        member.displayName,
                        overflow: .ellipsis,
                        style: PTText.body.copyWith(fontSize: 14, fontWeight: .w500),
                      ),
                    ),
                    if (ModerationService.instance.isBlocked(member.userId))
                      Text('Blocked', style: PTText.finePrint.copyWith(color: PTColors.white(0.5))),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: PTButton(
              label: 'Cancel',
              variant: .secondary,
              expand: false,
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _unblockMember(RoomMember member) async {
    try {
      await ModerationService.instance.unblock(member.userId);
      if (mounted) _snack('${member.displayName} is unblocked.', kind: .success);
    } catch (_) {
      if (mounted) _snack("Couldn't unblock them. Try again.");
    }
  }

  bool get _canStartWithout {
    final sync = _sync;
    if (sync == null || !sync.isHost || !_canonicalMedia.isSet) return false;
    return sync.gateBlockers.any((m) => m.userId != sync.userId);
  }

  String get _startWithoutLabel {
    final sync = _sync;
    final others =
        sync?.gateBlockers.where((m) => m.userId != sync.userId).toList() ??
        const <PresentMember>[];
    if (others.length == 1) return 'Start without ${others.first.displayName}';
    return 'Start without them';
  }

  Future<void> _startWithoutStragglers() async {
    final sync = _sync;
    if (sync == null) return;
    final skipped = sync.gateBlockers.where((m) => m.userId != sync.userId).length;
    if (skipped == 0) return;
    Analytics.instance.track('gate_override_used', {
      'room_id': widget.roomId,
      'skipped': skipped,
      'members_present': _present.length,
    });
    await sync.waiveGateBlockers();
    if (!mounted) return;
    _showActionToast(
      skipped == 1 ? 'Starting without one watcher' : 'Starting without $skipped watchers',
    );
  }

  /// The file this device tried and failed to open (it would not decode, or
  /// never reported a length). Offering "Locate copy" for that same file again
  /// is a dead end, so while it is the room's file the overlay's primary action
  /// is to choose a different video instead.
  String? _openFailedFor;

  bool get _selfFileFailed =>
      _openFailedFor != null && _openFailedFor == _canonicalMedia.name && _mode == .local;

  bool get _selfBlocksGate {
    final sync = _sync;
    if (sync == null) return false;
    final self = _present.where((m) => m.userId == sync.userId).firstOrNull;
    return self != null && !sync.memberSatisfiesGate(self);
  }

  bool get _allMembersLocallyReady {
    if (_present.length <= 1) return false;
    if (_canonicalMedia.name == null) return false;
    return _present.every((m) => memberSatisfiesGate(m, _canonicalMedia));
  }

  /// Plain-language "who are we waiting on, and for what".
  String get _gateHeadline {
    final sync = _sync;
    if (!_canonicalMedia.isSet) {
      return (sync?.isHost ?? false)
          ? 'Pick something for everyone to watch.'
          : 'Waiting for the host to pick something to watch.';
    }
    final what = _canonicalMedia.name ?? 'the video';
    final blockers = sync?.gateBlockers ?? const <PresentMember>[];
    if (blockers.isEmpty) return 'Lining everyone back up…';

    final others = blockers.where((m) => m.userId != sync?.userId).toList();
    if (others.isEmpty) {
      if (_selfFileFailed) return "We couldn't open $what.";
      return _canonicalMedia.kind == .local ? 'Load $what to join in.' : 'Getting $what ready…';
    }
    // The wrong-file case only reads well for a single person; past that,
    // "waiting for X and Y to load <name>" covers both situations.
    if (others.length == 1 && _canonicalMedia.kind == .local && others.first.isReady) {
      final wrong = others.first.loadedFileName ?? 'nothing';
      return 'Holding the curtain for ${others.first.displayName}: '
          'they have $wrong open, not the room\'s file.';
    }
    return 'Holding the curtain for ${_joinNames(others.map((m) => m.displayName).toList())}, '
        'loading $what.';
  }

  String _joinNames(List<String> names) => switch (names.length) {
    0 => 'everyone',
    1 => names.first,
    2 => '${names[0]} and ${names[1]}',
    _ => '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}',
  };

  /// True when the action was blocked. Every user-initiated transport action
  /// funnels through here - the dimmed widgets are affordance only, and
  /// keyboard shortcuts and double-tap skip zones never touch them.
  bool _blockTransport() {
    final reason = _transportBlockedReason;
    if (reason == null) return false;
    // Informational, not a failure: the gate or the lock is doing its job.
    _snack(reason, kind: .info);
    return true;
  }

  void _playPause() {
    if (_blockTransport()) return;
    _showControls();
    if (_sync?.userId case final selfId?) {
      _tally(selfId, ProfileService.instance.profile?.displayName ?? 'You').transportActions++;
    }
    if (_mode == .youtube) {
      final controller = _youtubeController;
      if (controller == null || !_ytReady) return;
      final currentPosition = controller.position;
      // Toggle on intent, not iframe state - the iframe lags behind commands.
      if (_ytIntendedPlaying) {
        _ytIntendedPlaying = false;
        controller.pause();
        _sync?.broadcastPause();
      } else {
        _ytIntendedPlaying = true;
        controller.play();
        _sync?.broadcastPlay();
        _trackPlaybackStarted();
      }
      _sync?.broadcastSeek(currentPosition, reason: SyncActionReason.transport);
    } else {
      if (LiveKitService.isMockMode && _player.state.duration == Duration.zero) {
        setState(() => _playing = !_playing);
        _playing ? _sync?.broadcastPlay() : _sync?.broadcastPause();
        if (_playing) _trackPlaybackStarted();
        _sync?.broadcastSeek(_position, reason: SyncActionReason.transport);
        unawaited(_persistPosition());
        return;
      }
      final currentPosition = _player.state.position;
      _player.playOrPause();
      _playing ? _sync?.broadcastPause() : _sync?.broadcastPlay();
      if (!_playing) _trackPlaybackStarted();
      _sync?.broadcastSeek(currentPosition, reason: SyncActionReason.transport);
    }
    unawaited(_persistPosition());
  }

  /// Returns false when the gate or transport lock refused the seek, so
  /// callers can skip their own feedback (the ±10 s badge) too.
  bool _seek(Duration position) {
    if (_blockTransport()) return false;
    _showControls();
    final clamped = position < Duration.zero
        ? Duration.zero
        : (_duration != Duration.zero && position > _duration ? _duration : position);
    if (_mode == .youtube) {
      if (!_ytReady) return false;
      _ytSeekKeepingPlayState(clamped);
    } else {
      if (LiveKitService.isMockMode && _player.state.duration == Duration.zero) {
        setState(() => _position = clamped);
      } else {
        _player.seek(clamped);
      }
    }
    _sync?.broadcastSeek(clamped);
    unawaited(_persistPosition());
    return true;
  }

  bool _skip(Duration delta) => _seek(_position + delta);

  void _flashSkip(int direction) {
    setState(() => _skipFlash = direction);
    _skipFlashTimer?.cancel();
    _skipFlashTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _skipFlash = 0);
    });
  }

  bool _togglingFullscreen = false;

  Future<void> _toggleFullscreen() async {
    if (!isDesktop || _togglingFullscreen) return;
    _togglingFullscreen = true;
    try {
      final isFull = await AppWindow.instance.isFullScreen();
      await AppWindow.instance.setFullScreen(!isFull);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'toggling fullscreen');
    } finally {
      Future.delayed(const Duration(milliseconds: 700), () {
        if (mounted) _togglingFullscreen = false;
      });
    }
  }

  /// Phone fullscreen: turn the picture to landscape. The lock only lasts for
  /// the turn; once the app is landscape the device is free to rotate again,
  /// so physically turning the phone back still wins.
  Future<void> _turnToLandscape() async {
    trace('phone fullscreen', category: 'room', data: {'room_id': widget.roomId});
    try {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await Future<void>.delayed(const Duration(seconds: 1));
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'turning the phone for fullscreen');
    }
  }

  Future<void> _exitFullscreen() async {
    if (!isDesktop || _togglingFullscreen) return;
    _togglingFullscreen = true;
    try {
      await AppWindow.instance.setFullScreen(false);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'exiting fullscreen');
    } finally {
      Future.delayed(const Duration(milliseconds: 700), () {
        if (mounted) _togglingFullscreen = false;
      });
    }
  }

  void _setVolume(double v) {
    if (_mode == .youtube) {
      _youtubeController?.setVolume((v * 100).round());
      setState(() => _volume = v);
    } else {
      _player.setVolume(v * 100);
    }
    _showControls();
  }

  void _toggleMute() {
    if (_volume > 0) {
      _volumeBeforeMute = _volume;
      _setVolume(0);
    } else {
      _setVolume(_volumeBeforeMute > 0 ? _volumeBeforeMute : 1.0);
    }
  }

  bool get _modifierChordHeld {
    final keys = HardwareKeyboard.instance;
    return keys.isControlPressed || keys.isMetaPressed || keys.isAltPressed;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    if (_modifierChordHeld) return KeyEventResult.ignored;

    // A focused text field (chat input) owns the keyboard - space must type a
    // space, not toggle playback. Esc hands focus back to player shortcuts.
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    if (focusedContext?.findAncestorStateOfType<EditableTextState>() != null) {
      if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
        _shortcutFocus.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // Toggles must not flap while the key is held.
    final toggleKeys = {LogicalKeyboardKey.keyD, LogicalKeyboardKey.keyE, LogicalKeyboardKey.keyR};
    if (event is KeyRepeatEvent && toggleKeys.contains(event.logicalKey)) {
      return KeyEventResult.handled;
    }

    var handled = true;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.space:
      case LogicalKeyboardKey.keyK:
        _playPause();
      case LogicalKeyboardKey.arrowLeft:
        _skip(const Duration(seconds: -5));
      case LogicalKeyboardKey.arrowRight:
        _skip(const Duration(seconds: 5));
      case LogicalKeyboardKey.keyJ:
        _skip(const Duration(seconds: -10));
      case LogicalKeyboardKey.keyL:
        _skip(const Duration(seconds: 10));
      case LogicalKeyboardKey.arrowUp:
        _setVolume((_volume + 0.1).clamp(0, 1));
      case LogicalKeyboardKey.arrowDown:
        _setVolume((_volume - 0.1).clamp(0, 1));
      case LogicalKeyboardKey.keyM:
        _toggleMute();
      case LogicalKeyboardKey.keyC:
        return _toggleChatFromShortcut() ? KeyEventResult.handled : KeyEventResult.ignored;
      case LogicalKeyboardKey.keyV:
        return _toggleCamsFromShortcut() ? KeyEventResult.handled : KeyEventResult.ignored;
      case LogicalKeyboardKey.keyD:
        return _toggleFacecamFromShortcut('mic') ? KeyEventResult.handled : KeyEventResult.ignored;
      case LogicalKeyboardKey.keyE:
        return _toggleFacecamFromShortcut('cam') ? KeyEventResult.handled : KeyEventResult.ignored;
      case LogicalKeyboardKey.keyR:
        if (_privacyHidden || _sync == null) return KeyEventResult.ignored;
        _toggleReact();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyF:
        _toggleFullscreen();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyH:
        _toggleControlsVisible();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.question:
      case LogicalKeyboardKey.slash:
        _showShortcuts();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.f1:
        _togglePrivacy();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.f2:
        if (kDebugMode && _mode == .youtube && _youtubeController != null) {
          _youtubeController!.debugToggleAdState();
          final isAd = _youtubeController!.isAdPlaying;
          if (isAd) {
            _snack('Ad simulated: playback & sync paused', kind: .info);
          }
          return KeyEventResult.handled;
        } else {
          handled = false;
        }
      case LogicalKeyboardKey.escape:
        // Ordered: emoji picker close (RoomChatPanel consumes it first, while
        // open) → text-field unfocus (handled above) → reaction strip close →
        // chat close → fullscreen exit → let Esc bubble.
        if (_reactOpen) {
          _closeReact();
          return KeyEventResult.handled;
        } else if (_chatOpen) {
          _toggleChat();
          return KeyEventResult.handled;
        } else if (_fullscreen) {
          _exitFullscreen();
          return KeyEventResult.handled;
        } else {
          handled = false;
        }
      default:
        handled = false;
    }
    if (!handled) return KeyEventResult.ignored;
    if (_controlsVisible) _showControls();
    return KeyEventResult.handled;
  }

  // ---------------------------------------------------------------------------
  // Controls visibility & Cinema Mode (overlay layouts)
  // ---------------------------------------------------------------------------

  void _showControls() {
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
    }
    _cursorHideTimer?.cancel();
    if (!_cursorVisible) {
      setState(() => _cursorVisible = true);
    }
  }

  void _hideControls() {
    if (_reactOpen) _closeReact();
    _cursorHideTimer?.cancel();
    if (_controlsVisible || _cursorVisible) {
      setState(() {
        _controlsVisible = false;
        _cursorVisible = false;
      });
    }
  }

  void _onMouseMove() {
    if (!_cursorVisible) {
      setState(() => _cursorVisible = true);
    }
    _cursorHideTimer?.cancel();
    if (!_controlsVisible) {
      _cursorHideTimer = Timer(const Duration(seconds: 2), () {
        if (mounted && !_controlsVisible) setState(() => _cursorVisible = false);
      });
    }
  }

  void _togglePrivacy() {
    final av = _av;
    if (_privacyHidden) {
      setState(() => _privacyHidden = false);
      if (_chatOpenBeforePrivacy && !_chatOpen) _toggleChat();
      if (av != null) {
        if (_present.length >= 2) {
          if (_micBeforePrivacy) av.setMicEnabled(true);
          if (_camBeforePrivacy) av.setCamEnabled(true);
        } else {
          if (_micBeforePrivacy) _micBeforeSolo = true;
          if (_camBeforePrivacy) _camBeforeSolo = true;
        }
      }
    } else {
      _chatOpenBeforePrivacy = _chatOpen;
      if (_chatOpen) _toggleChat();
      if (av != null) {
        _micBeforePrivacy = av.micEnabled;
        _camBeforePrivacy = av.camEnabled;
        if (_micBeforePrivacy) av.setMicEnabled(false);
        if (_camBeforePrivacy) av.setCamEnabled(false);
      }
      setState(() {
        _privacyHidden = true;
        _cancelOverlayChatTimers();
        _overlayChat.clear();
      });
    }
    _sync?.retrackPrivacy(_privacyHidden);
    _shortcutFocus.requestFocus();
  }

  void _toggleReact() {
    setState(() => _reactOpen = !_reactOpen);
    _shortcutFocus.requestFocus();
    _showControls();
  }

  void _closeReact() {
    if (!_reactOpen) return;
    setState(() => _reactOpen = false);
    _shortcutFocus.requestFocus();
    _showControls();
  }

  Future<void> _showReactionPicker() async {
    final available = reactionsForTier(EntitlementService.instance.tier);
    if (available.length <= kBaseReactionCount) return;
    final picked = await showGlassDialog<PTReaction>(
      context: context,
      width: 420,
      builder: (_) => ReactionPickerDialog(reactions: available, assets: _reactionAssets),
    );
    if (!mounted) return;
    _shortcutFocus.requestFocus();
    if (picked != null) _sendReaction(picked);
  }

  void _sendReaction(PTReaction reaction) {
    _sync?.sendReaction(reaction.emoji);
    _reactionsSent++;
  }

  /// One place for both halves of the reaction tally: the stream carries the
  /// local echo as well as everyone else's, so self needs no separate branch.
  void _tallyReaction(ReactionEvent event) {
    _tally(event.senderId, event.displayName).reactions++;
    _emojiCounts.update(event.emoji, (n) => n + 1, ifAbsent: () => 1);
  }

  /// The session's most-sent emoji, for the recap's one flourish.
  String? get _topEmoji {
    String? best;
    var bestCount = 0;
    for (final entry in _emojiCounts.entries) {
      if (entry.value > bestCount) {
        bestCount = entry.value;
        best = entry.key;
      }
    }
    return best;
  }

  void _toggleControlsVisible() {
    // Tapping the video or pressing H also steals focus from the chat input,
    // so keyboard shortcuts work again immediately.
    _shortcutFocus.requestFocus();
    if (_reactOpen) {
      _closeReact();
      return;
    }
    if (_controlsVisible) {
      _hideControls();
    } else {
      _showControls();
    }
  }

  void _onPlayingChangedForControls(bool playing) {
    _syncScreenAwake();
    if (!playing) {
      // Paused: controls stay up - hiding them on a paused frame helps no one.
      _cursorHideTimer?.cancel();
      if (!_controlsVisible) setState(() => _controlsVisible = true);
      if (!_cursorVisible) setState(() => _cursorVisible = true);
      _kbBarTimer?.cancel();
      if (!_kbBarVisible) setState(() => _kbBarVisible = true);
    } else if (_kbBarWasUp) {
      _revealKbBar();
    }
  }

  /// Whether the portrait room is floating its transport over the picture
  /// because the keyboard (or the inline emoji picker) holds the lower half.
  /// Phone portrait and tablet portrait only - the layouts [_portrait] builds.
  bool get _kbOverlayOn {
    if (isDesktop || foldOf(context).isSplit) return false;
    final size = MediaQuery.sizeOf(context);
    final portraitish = switch (layoutOf(context)) {
      .portrait => true,
      .tablet => size.height >= size.width && size.height / size.width >= kSquarishMaxAspect,
      _ => false,
    };
    return portraitish && (MediaQuery.viewInsetsOf(context).bottom > 0 || _chatPickerUp);
  }

  /// Whether the chrome over the picture is showing: the landscape overlay's
  /// state, or the keyboard-up bar's.
  bool get _overlayShown => _kbOverlayOn ? _kbBarVisible : _controlsVisible;

  /// Called from build with whether the keyboard overlay is wanted. The rising
  /// edge shows the bar (and starts its hide timer); the work is deferred past
  /// the frame because it sets state.
  void _kbBarEdge(bool up) {
    if (up == _kbBarWasUp) return;
    _kbBarWasUp = up;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (up) {
        _revealKbBar();
      } else {
        _kbBarTimer?.cancel();
      }
    });
  }

  void _revealKbBar() {
    _kbBarTimer?.cancel();
    if (!_kbBarVisible) setState(() => _kbBarVisible = true);
    // Paused, the bar stays: hiding the transport on a paused frame helps no one.
    if (!_playing) return;
    _kbBarTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _kbBarWasUp && _playing) setState(() => _kbBarVisible = false);
    });
  }

  /// The one transport bar, in both of its places. While the keys are up the
  /// stack floats it over the picture's bottom edge; this wrapper is what lets
  /// it fade and slide away on its own timer. The tree is the same whether or
  /// not it floats, so nothing remounts when the keys rise or fall.
  Widget _kbBarShell(Widget bar, {required bool floating}) {
    final away = floating && !_kbBarVisible;
    return IgnorePointer(
      ignoring: away,
      child: AnimatedSlide(
        offset: away ? const Offset(0, 1.2) : Offset.zero,
        duration: PTMotion.functional(context, PTMotion.state),
        curve: away ? PTMotion.exit : PTMotion.enter,
        child: AnimatedOpacity(
          opacity: away ? 0 : 1,
          duration: PTMotion.functional(context, Durations.medium2),
          // Any touch on the bar keeps it up another few seconds.
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) {
              if (floating) _revealKbBar();
            },
            onPointerUp: (_) {
              if (floating) _revealKbBar();
            },
            child: bar,
          ),
        ),
      ),
    );
  }

  /// Fades and slides the floating chrome.
  ///
  /// [fromTop] chrome drifts up as it goes and bottom chrome drifts down, so
  /// the controls retreat off their edge completely rather than dissolving in place.
  Widget _overlayControls(Widget child, {bool fromTop = false}) {
    return IgnorePointer(
      ignoring: !_controlsVisible,
      child: AnimatedSlide(
        offset: _controlsVisible ? Offset.zero : Offset(0, fromTop ? -1.2 : 1.2),
        duration: PTMotion.functional(context, PTMotion.state),
        curve: _controlsVisible ? PTMotion.enter : PTMotion.exit,
        child: AnimatedOpacity(
          opacity: _controlsVisible ? 1 : 0,
          duration: PTMotion.functional(context, Durations.medium2),
          child: Listener(onPointerDown: (_) => _showControls(), child: child),
        ),
      ),
    );
  }

  /// Subtle bottom-right reveal trigger shown when room controls are hidden in Cinema Mode.
  Widget _showControlsButton() {
    return AnimatedSlide(
      offset: !_controlsVisible ? Offset.zero : const Offset(0, 2.5),
      duration: PTMotion.functional(context, PTMotion.state),
      curve: !_controlsVisible ? PTMotion.enter : PTMotion.exit,
      child: IgnorePointer(
        ignoring: _controlsVisible,
        child: GlassPanel(
          radius: PTRadius.panel,
          baseColor: PTColors.surfaceBase,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: PTIconButton(
            icon: Symbols.keyboard_arrow_up_rounded,
            glass: false,
            size: 32,
            iconSize: 22,
            tooltip: 'Show controls (H)',
            onPressed: _showControls,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Expiry & eviction
  // ---------------------------------------------------------------------------

  void _tickCountdown() {
    final room = _room;
    if (room == null || _ended) return;
    final left = room.expiresAt.difference(RoomService.instance.serverNow);
    setState(() => _timeLeft = left.isNegative ? Duration.zero : left);
    if (left <= Duration.zero) {
      if (_sync?.isHost ?? false) {
        _sync?.broadcastRoomEnded();
      }
      _onRoomEnded(reason: 'expiry');
    }
    if (LiveKitService.isMockMode &&
        _playing &&
        _mode == .local &&
        _player.state.duration == Duration.zero) {
      setState(() {
        _position += const Duration(seconds: 1);
        if (_duration != Duration.zero && _position > _duration) {
          _position = Duration.zero;
        }
      });
    }
  }

  Future<void> _onRoomEnded({String reason = 'room_ended'}) => _evictSelf(reason: reason);

  void _onRoomEndedRemotely(String? reason) {
    if (reason == 'deleted') {
      unawaited(_onRoomDeleted());
    } else if (reason == 'room_banned' || reason == 'banned') {
      unawaited(_onRoomBanned());
    } else {
      unawaited(_onRoomEnded());
    }
  }

  Future<void> _onRoomDeleted() => _evictSelf(
    reason: 'deleted',
    title: 'This room is gone',
    body:
        'Whoever made this room deleted it, so there is nothing left to come back to. '
        'Head to the lobby and start a fresh one.',
    icon: BoothIcons.delete,
  );

  Future<void> _onRoomBanned() => _evictSelf(
    reason: 'room_banned',
    title: 'Room Closed by Moderation',
    body:
        'This room was closed by SyncTogether moderation for violating our anti-piracy or community guidelines. '
        'Media sharing in this room has been terminated.',
    icon: Symbols.block_rounded,
  );

  /// The host removed us. Same teardown as a room ending - only the copy
  /// differs - because from this client's side the room is equally over.
  Future<void> _onKicked() => _evictSelf(
    reason: 'kicked',
    title: 'Removed from the room',
    body: 'The host removed you from this room. No hard feelings!',
    icon: BoothIcons.personRemove,
  );

  Future<void> _evictSelf({
    required String reason,
    String? title,
    String? body,
    IconData? icon,
  }) async {
    if (_ended) return;
    // Fired, not awaited: a best-effort last write, and the room is on its
    // way out either way. Chaining it ahead of the dialog is what used to
    // make "End room for everyone" visibly freeze for the round trip.
    unawaited(_persistPosition());
    _ended = true;
    _evictionReason = reason;
    _trackWatchSessionEnded();
    RoomService.instance.noteRoomExited();
    trace(
      'evicted from the room',
      category: 'room',
      data: {'room_id': widget.roomId, 'reason': reason},
    );
    // Null closes the overflow menu if it happens to be open - otherwise it
    // sits over the "House lights up." dialog listing a room that no longer runs.
    _publishMenuData();
    _overflowMenu?.close();
    _overflowMenu = null;
    _actionToastTimer?.cancel();
    _gateAnim.reset();
    _countdownTimer?.cancel();
    _remotePause();
    // Unpublish mic/cam right away - not when the user finally taps
    // "Back to lobby".
    final av = _av;
    av?.removeListener(_onAvChanged);
    if (mounted) {
      setState(() {
        _av = null;
        _actionToastVisible = false;
      });
    } else {
      _av = null;
      _actionToastVisible = false;
    }
    av?.dispose();
    if (_isUploadingSharedMedia || _uploadState == 'uploading') {
      _isUploadingSharedMedia = false;
      _uploadState = 'none';
      unawaited(_mediaSharingService.abortUpload(roomId: widget.roomId));
    }
    // Same reason: the dialog doesn't need the channel gone or playback
    // stopped, it needs this widget's own UI gone. Run both concurrently in
    // the background instead of making the user wait on two more round
    // trips they can't see.
    unawaited(Future.wait([?_sync?.disconnect(), _player.stop()]));
    if (mounted) _showEndedDialog(title: title, body: body, icon: icon);
  }

  ({String title, String body, IconData icon})? get _endedCopy {
    final room = _room;
    if (room == null) return null;
    if (room.isOurRoom) {
      const base = 'It is always in your lobby. Open it again whenever you two are ready.';
      return (
        title: 'Our Room is resting',
        body: _ourRoomFilmKept
            ? '$base Your film is kept. ${ourRoomKeepNote(patron: PairService.instance.pair?.patron ?? false)}'
            : base,
        icon: BoothIcons.heart,
      );
    }
    if (room.persistent) {
      return (
        title: 'Room saved',
        body: 'Your persistent room is saved in your lobby. You can start another watch party anytime.',
        icon: Symbols.bookmark_rounded,
      );
    }
    return (
      title: 'House lights up.',
      body: "That show's over. Your lobby is right there whenever you want to open another room.",
      icon: BoothIcons.film,
    );
  }

  void _showEndedDialog({String? title, String? body, IconData? icon}) {
    _ended = true;
    _gateAnim.reset();
    if (!mounted) return;
    final roomRoute = ModalRoute.of(context);
    if (roomRoute != null) {
      Navigator.of(context).popUntil((route) => route == roomRoute);
    }
    if (title == null && body == null) {
      final ended = _endedCopy;
      if (ended != null) {
        title = ended.title;
        body = ended.body;
        icon ??= ended.icon;
      }
    }
    final isMobile = layoutOf(context) == .portrait;
    showRoomEndedDialog(
      context: context,
      resuming: _resuming,
      isMobile: isMobile,
      evictionReason: _evictionReason,
      title: title ?? 'House lights up.',
      body: body ?? 'This room has ended. Head back to the lobby to start another one.',
      icon: icon ?? BoothIcons.film,
      persistent: _room?.persistent ?? false,
      canShowPremiumUpsell: _canShowPremiumUpsell,
      onBackToLobby: () async {
        if (AuthService.instance.isSignedIn) {
          unawaited(ProfileService.instance.load());
          unawaited(EntitlementService.instance.refresh());
          unawaited(RewardsService.instance.refresh());
        }
        await _maybeShowRecap();
        if (mounted) context.go('/lobby');
      },
      // A free pair whose film is being kept is offered the long window, once, here:
      // never while they are watching.
      premiumUpsellLabel: _ourRoomFilmKept ? ourRoomKeepUpsellLabel : null,
      onPremiumUpsell: () {
        context.go(
          _ourRoomFilmKept
              ? '/lobby/subscribe?source=room_ended_film'
              : '/lobby/subscribe?source=room_ended',
        );
      },
    );
  }

  /// Our Room ended with a finished shared film in it: it is kept for a while, not
  /// removed (see `ourRoomKeepNote`).
  bool get _ourRoomFilmKept =>
      (_room?.isOurRoom ?? false) &&
      (_sync?.mediaUploadState == 'ready' ||
          _uploadState == 'ready' ||
          _room?.mediaUploadState == 'ready');

  /// Our Room named a film whose shared copy has been released, and this device has no
  /// copy open and nothing is being shared again: say so, instead of a silent "Locate".
  bool get _showCopyExpiredNotice =>
      !_copyExpiredDismissed &&
      (_room?.isOurRoom ?? false) &&
      _room?.mediaShareExpiredAt != null &&
      _canonicalMedia.kind == .local &&
      _canonicalMedia.name != null &&
      _localFileName != _canonicalMedia.name &&
      _sync?.mediaUploadState != 'ready' &&
      _uploadState != 'ready' &&
      _uploadState != 'uploading';

  bool get _canShowPremiumUpsell {
    // Patron on either side already covers both of them; the offer is for the
    // pair that has none.
    if ((_room?.isOurRoom ?? false) && (PairService.instance.pair?.patron ?? false)) return false;
    if (!canSellPremium ||
        EntitlementService.instance.isPremium ||
        !AuthService.instance.isSignedIn) {
      return false;
    }
    return _evictionReason != 'kicked' && _evictionReason != 'deleted';
  }

  Future<void> _leaveRoom() async {
    trace('leaving the room', category: 'room', data: {'room_id': widget.roomId});
    _setImmersive(false);
    _trackWatchSessionEnded();
    if (isMobile) {
      unawaited(_backgroundCall.stop());
      unawaited(setScreenAwake(false));
    }
    unawaited(_persistPosition());
    _thumbWait?.cancel();
    unawaited(_localVideo?.release());
    try {
      await RoomService.instance.leaveRoom(widget.roomId);
    } catch (e, s) {
      // Leave for the lobby regardless - trapping someone in a room they asked
      // to leave is worse. But the membership is now stranded: it holds a slot
      // against the 8-member cap and stays eligible for host succession.
      reportNonFatal(e, s, during: 'leaving room ${widget.roomId}');
    }
    // Concurrent, not chained - the lobby route doesn't need the channel gone
    // or playback stopped first, and chaining them is what made this freeze.
    // Safe here (unlike dispose): this path always lands on the lobby, never
    // straight into another room.
    unawaited(
      Future.wait([
        ?_sync?.disconnect(),
        // The app can be tearing the player down as we leave; stopping a
        // disposed one asserts, and there is nothing left to stop.
        _player.stop().then<void>(
          (_) {},
          onError: (Object e, StackTrace _) =>
              trace('player stop failed on leave', category: 'media', data: {'error': '$e'}),
        ),
      ]),
    );
    if (AuthService.instance.isSignedIn) {
      unawaited(ProfileService.instance.load());
      unawaited(EntitlementService.instance.refresh());
      unawaited(RewardsService.instance.refresh());
    }
    await _maybeShowRecap();
    if (mounted) context.go('/lobby');
  }

  Future<void> _endRoomForEveryone() async {
    try {
      await RoomService.instance.endRoom(widget.roomId);
      await _sync?.broadcastRoomEnded();
      await _onRoomEnded(reason: 'ended_by_host');
    } catch (e, s) {
      final failure = RoomErrorCode.fromError(e);
      if (failure == .unknown) reportNonFatal(e, s, during: 'ending room ${widget.roomId}');
      _snack(failure.message);
    }
  }

  // ---------------------------------------------------------------------------
  // Misc UI actions
  // ---------------------------------------------------------------------------

  /// Lifted clear of whatever owns the bottom edge in each layout: the floating
  /// control bar on desktop/landscape, the chat input in portrait. A toast that
  /// lands on the transport controls hides the thing the message is about.
  void _snack(String message, {PTSnackKind kind = PTSnackKind.error}) {
    if (!mounted) return;
    showPTSnack(
      context,
      message,
      kind: kind,
      bottomInset: switch (layoutOf(context)) {
        .desktop || .tablet => 180,
        .landscape => 120,
        .portrait => 70,
      },
    );
  }

  Future<void> _showShortcuts() async {
    await showGlassDialog<void>(
      context: context,
      width: 460,
      builder: (_) => ShortcutsDialog(facecams: _av != null),
    );
    if (mounted) _shortcutFocus.requestFocus();
  }

  void _copyCode() {
    final room = _room;
    if (room == null) return;
    Clipboard.setData(ClipboardData(text: room.code));
    _snack('Room code copied.', kind: .success);
  }

  void _copyInvite() {
    final room = _room;
    if (room == null) return;
    Clipboard.setData(ClipboardData(text: room.inviteLink));
    Analytics.instance.track('invite_copied', {'room_id': widget.roomId});
    _snack('Invite link copied. Send it to your people.', kind: .success);
  }

  void _onChatCopied() => _snack('Message copied.', kind: .success);

  void _openChat() {
    if (!_chatOpen) _toggleChat();
  }

  bool _toggleChatFromShortcut() {
    if (_privacyHidden || _chatEmbedded) return false;
    _toggleChat();
    return true;
  }

  bool _toggleCamsFromShortcut() {
    if (_privacyHidden || _av == null) return false;
    setState(() => _camsVisible = !_camsVisible);
    _shortcutFocus.requestFocus();
    return true;
  }

  /// D / E: mic and camera, Meet's mnemonics (M and V were already taken by
  /// mute and the facecam rail).
  bool _toggleFacecamFromShortcut(String kind) {
    final av = _av;
    if (_privacyHidden || av == null) return false;
    if (kind == 'cam' && !av.canPublishCamera) {
      _toggleFacecam('cam', true); // explains the voice-only room
      return true;
    }
    _toggleFacecam(kind, !(kind == 'mic' ? av.micEnabled : av.camEnabled));
    setState(() {});
    return true;
  }

  void _toggleChat() {
    setState(() {
      _chatOpen = !_chatOpen;
      if (_chatOpen) {
        _unread = 0;
        _cancelOverlayChatTimers();
      }
    });
    if (_chatOpen) {
      _chatAnim.forward();
    } else {
      _chatAnim.reverse();
    }
    // Closing chat may leave a disposed TextField as primary focus; reclaim it
    // so playback shortcuts work again.
    if (!_chatOpen) _shortcutFocus.requestFocus();
  }

  Future<void> _sendChat(String text) async {
    final message = await _sync?.sendChat(text);
    if (message == null) return;
    _messagesSent++;
    _tally(message.senderId, message.displayName).messages++;
    if (mounted) setState(() => _messages.add(message));
  }

  Future<void> _reloadChatHistory() async {
    try {
      final history = await _sync?.loadChatHistory();
      if (history == null || !mounted) return;
      setState(() => mergeChatHistory(_messages, history));
    } catch (e, s) {
      // Broadcasts don't replay, so this reload is the only way messages sent
      // while we were disconnected ever arrive - losing it leaves a permanent
      // hole in the transcript.
      reportNonFatal(e, s, during: 'reloading chat history after a reconnect');
    }
  }

  void _openOverflowMenu() {
    // A null snapshot means "close" - opening on it would strand an empty panel.
    if (_ended) return;
    if (_overflowMenu?.isOpen ?? false) return;
    _publishMenuData();
    _overflowMenu = showRoomOverflowMenu(
      context: context,
      data: _menuData,
      onCopyInvite: _copyInvite,
      onLeave: _leaveRoom,
      onEndRoom: _endRoomForEveryone,
      onExtendRoom: _extendRoom,
      onReportConcern: _showReportDialog,
      onReportBug: () => BugReport.open(context, source: 'more'),
      onTransportLockChanged: _setTransportLock,
      onKick: (member) {
        final present = _present.where((p) => p.userId == member.userId).firstOrNull;
        _confirmKick(
          present ??
              PresentMember(
                userId: member.userId,
                displayName: member.displayName,
                role: member.role,
                joinedAt: member.joinedAt,
                avatarUrl: member.profile?.avatarUrl,
              ),
        );
      },
      onAssignHost: _confirmAssignHost,
      onReportMember: (member) =>
          unawaited(_showReportDialog(targetUserId: member.userId, targetUser: member.displayName)),
      onUnblockMember: (member) => unawaited(_unblockMember(member)),
      playbackActions: _menuPlaybackActions(),
    );
  }

  Future<void> _setTransportLock(bool locked) async {
    try {
      final room = await RoomService.instance.setTransportLock(
        roomId: widget.roomId,
        locked: locked,
      );
      if (!mounted) return;
      setState(() => _room = room);
      await _sync?.broadcastTransportLock(room.transportLock);
      if (mounted) {
        _snack(
          locked ? 'You have the remote now.' : 'Everyone can use the controls again.',
          kind: .info,
        );
      }
    } catch (e, s) {
      final failure = RoomErrorCode.fromError(e);
      if (failure == .unknown) reportNonFatal(e, s, during: 'changing the transport lock');
      if (mounted) _snack(failure.message);
    }
  }

  Future<void> _showTrackChooser({required bool subtitles}) async {
    return showRoomTrackChooser(
      context: context,
      player: _player,
      subtitles: subtitles,
      hasSubtitleStyle: _subtitleStyle != null,
      onSubtitlesChanged: () => unawaited(_suppressSecondarySubtitles()),
      onAddExternalSubtitle: () => unawaited(_pickExternalSubtitleFile()),
      onInfo: (msg) => _snack(msg, kind: .info),
    );
  }

  Future<void> _showYouTubeCaptionChooser() async {
    final yt = _youtubeController;
    if (yt == null) return;
    return showRoomYouTubeCaptionChooser(context: context, controller: yt);
  }

  Future<void> _pickExternalSubtitleFile() async {
    const subtitleTypes = XTypeGroup(
      label: 'Subtitles',
      extensions: ['srt', 'vtt', 'ass', 'ssa', 'sub'],
    );
    final FastFilePickerPath? response;
    try {
      response = await FastFilePicker.pickFile(acceptedTypeGroups: [subtitleTypes]);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'picking external subtitle file');
      return;
    }
    final uri = response?.uri ?? response?.path;
    if (uri == null) return;
    final name = _basename(response!);
    try {
      await _player.setSubtitleTrack(SubtitleTrack.uri(uri, title: name));
      unawaited(_suppressSecondarySubtitles());
      if (mounted) {
        _snack('Loaded subtitle: $name', kind: .info);
      }
    } catch (e, s) {
      reportNonFatal(e, s, during: 'loading external subtitle track');
      if (mounted) {
        _snack('Failed to load subtitle file.');
      }
    }
  }

  Future<void> _loadSidecarSubtitles(String videoPath) async {
    try {
      final videoFile = File(videoPath);
      final parentDir = videoFile.parent;
      if (!await parentDir.exists()) return;
      final videoBase = p.basenameWithoutExtension(videoPath).toLowerCase();
      const validExts = {'.srt', '.vtt', '.ass', '.ssa', '.sub'};

      await for (final entity in parentDir.list()) {
        if (entity is! File) continue;
        final ext = p.extension(entity.path).toLowerCase();
        if (!validExts.contains(ext)) continue;
        final base = p.basenameWithoutExtension(entity.path).toLowerCase();
        if (base == videoBase ||
            base.startsWith('$videoBase.') ||
            base.startsWith('$videoBase-') ||
            base.startsWith('${videoBase}_')) {
          trace(
            'found sidecar subtitle',
            category: 'media',
            data: {'file': p.basename(entity.path)},
          );
          final track = SubtitleTrack.uri(entity.path, title: p.basename(entity.path));
          await _player.setSubtitleTrack(track);
          unawaited(_suppressSecondarySubtitles());
          break;
        }
      }
    } on FileSystemException catch (e) {
      // macOS grants only the picked file, not its folder; sidecars are optional.
      trace(
        'sidecar subtitle scan not permitted',
        category: 'media',
        data: {'errno': e.osError?.errorCode},
      );
    } catch (e, s) {
      reportNonFatal(e, s, during: 'scanning sidecar subtitles');
    }
  }

  /// mpv auto-picks subtitles by language and takes the first match, which on
  /// a Blu-ray rip is usually the PGS picture track - one no subtitle style
  /// can reach. Once per *fresh* open, swap to a text track in the same
  /// language. Not on the 403 re-sign reopen, which restores the viewer's own
  /// choice, and never after they have picked a track themselves.
  Future<void> _preferTextSubtitleOnOpen() async {
    // No native player behind an injected video view (tests).
    if (widget.dependencies.videoView != null) return;
    try {
      bool hasReal(Tracks t) => t.subtitle.any((s) => s.id != 'no' && s.id != 'auto');
      var tracks = _player.state.tracks;
      if (!hasReal(tracks)) {
        final none = tracks;
        tracks = await _player.stream.tracks
            .firstWhere(hasReal, orElse: () => none)
            .timeout(const Duration(seconds: 5));
      }
      if (!mounted) return;
      final native = _player.platform;
      if (native is! NativePlayer) return;
      final sid = await native.getProperty('sid');
      final pick = preferredTextSubtitle(tracks.subtitle, sid);
      if (pick == null || !mounted) return;
      await _player.setSubtitleTrack(pick);
      trace(
        'preferred a text subtitle over a picture track',
        category: 'media',
        data: {'from': sid, 'to': pick.id, 'language': pick.language},
      );
    } on TimeoutException {
      // No subtitle tracks at all: nothing to prefer.
    } catch (e, s) {
      reportNonFatal(e, s, during: 'preferring a text subtitle track');
    }
  }

  Future<void> _suppressSecondarySubtitles() async {
    try {
      await (_player.platform as dynamic)?.setProperty('secondary-sid', 'no');
    } catch (_) {}
  }

  /// What the top bar's sync dot reports. Read in build from fields that
  /// already drive a rebuild, so it adds no listener of its own.
  SyncDotState get _syncDotState {
    if (!_connected) return .reconnecting;
    if (!_canonicalMedia.isSet || _present.length < 2) return .idle;
    if (_buffering) return .catchingUp;
    return .locked;
  }

  String get _countdownLabel {
    final h = _timeLeft.inHours;
    final m = _timeLeft.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _timeLeft.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s left' : '$m:$s left';
  }

  TierLimits get _limits => EntitlementService.instance.limitsOrFallback;

  /// AV is deployed but this room's host tier grants none (a guest's room):
  /// the bar draws a locked mic rather than nothing, so the room says why.
  bool get _voiceLocked =>
      _av == null && LiveKitService.isConfigured && _room?.avLevel == AvLevel.none;

  String get _voiceLockedTooltip => _limits.isGuest
      ? 'Guest rooms have no voice chat. Sign in free and the rooms you host get it.'
      : canSellPremium
      ? kVoiceLockedTooltip
      : 'This is a guest room, so voice chat is off. Rooms hosted from a free '
            'account get voice.';

  /// A guest can fix this for their own rooms with one sign-in, so they get
  /// that offer; anyone else is told why - the host's tier decides, and
  /// upgrading would not change this room.
  Future<void> _explainVoiceLock() async {
    if (!_limits.isGuest) {
      _snack(_voiceLockedTooltip, kind: .info);
      return;
    }
    await _showPremiumTease(
      surface: 'voice_lock',
      headline: 'Talk while you watch',
      body:
          'Guest rooms are watch-only. Sign in: it takes a moment, it costs '
          'nothing, and this session carries over.',
      perks: const [
        'Voice chat in the rooms you host',
        'Rooms of 8 that run for four hours',
        'Rooms that nap in your lobby instead of vanishing',
      ],
      onSignIn: _linkGoogleIdentity,
      onSignInApple: AuthService.instance.isAppleSupported ? _linkAppleIdentity : null,
    );
  }

  String get _extendLabel => _limits.picksExtensionLength ? 'Add time' : 'Get a Patron seat';

  IconData? get _extendIcon => _limits.picksExtensionLength ? null : BoothIcons.crown;

  String get _expirySubtitle {
    final room = _room;
    if (room != null && room.persistent) {
      return 'Persistent room · current session ends at $_endsAtLabel.';
    }
    return 'Time to wrap up. This room ends at $_endsAtLabel.';
  }

  Future<void> _extendRoom() async {
    final room = _room;
    if (room == null || _extending) return;

    if (!_limits.picksExtensionLength) {
      if (_limits.isGuest) {
        await _showPremiumTease(
          surface: 'room_expiry',
          headline: 'Sign in for more time',
          body:
              'Guest rooms run for an hour and stop there. Sign in: it '
              'takes a moment, it costs nothing, and this session carries over.',
          perks: const [
            'Rooms that run for four hours, not one',
            'Voice chat for up to 8 friends',
            'Rooms that nap in your lobby instead of vanishing',
          ],
          onSignIn: _linkGoogleIdentity,
          onSignInApple: AuthService.instance.isAppleSupported ? _linkAppleIdentity : null,
        );
        return;
      }
      await _showPremiumTease(
        surface: 'room_expiry',
        headline: 'Get a Patron seat',
        body:
            'This room ends at $_endsAtLabel. Patron rooms run all night, up to 24 hours, '
            'seat sixteen and stay saved between shows.',
        perks: const [
          'Rooms that run up to 24 hours',
          'Up to 16 watchers, with video facecams',
          'Rooms that stay put until you delete them',
        ],
      );
      return;
    }

    final headroom = _limits.maxTotalSessionMinutes - room.durationMinutes;
    final options = [30, 60, 120, 240].where((m) => m <= headroom).toList();
    if (options.isEmpty) {
      _snack(RoomErrorCode.extensionCap.message, kind: .info);
      Analytics.instance.track('limit_hit', {'which': 'extension_cap'});
      return;
    }
    final chosen = await showGlassDialog<int>(
      context: context,
      width: 420,
      sheetOnCompact: true,
      builder: (_) => ExtendRoomDialog(
        options: options,
        headroomMinutes: headroom,
        endsAt: room.expiresAt,
        now: () => RoomService.instance.serverNow,
      ),
    );
    if (chosen == null || !mounted) return;
    final minutes = chosen;

    setState(() => _extending = true);
    try {
      final extended = await RoomService.instance.extendRoom(
        roomId: widget.roomId,
        minutes: minutes,
      );
      if (!mounted) return;
      setState(() {
        _room = extended;
        _warningDismissed = false;
      });
      _tickCountdown();
      unawaited(
        _sync?.broadcastRoomExtended(
          expiresAt: extended.expiresAt.toIso8601String(),
          durationMinutes: extended.durationMinutes,
        ),
      );
      _snack('More time. This room now runs until $_endsAtLabel.', kind: .success);
    } catch (e, s) {
      final failure = RoomErrorCode.fromError(e);
      if (failure == .unknown) reportNonFatal(e, s, during: 'extending room ${widget.roomId}');
      if (!mounted) return;
      if (failure == .extensionUsed || failure == .extensionCap) {
        await _showPremiumTease(
          surface: 'room_expiry',
          headline: 'Get a Patron seat',
          body: '${failure.message} Patron rooms run up to 24 hours and stay saved between shows.',
          perks: const [
            'Rooms that run up to 24 hours',
            'Up to 16 watchers, with video facecams',
            'Rooms that stay put until you delete them',
          ],
        );
      } else {
        _snack(failure.message);
      }
    } finally {
      if (mounted) setState(() => _extending = false);
    }
  }

  Future<void> _showPremiumTease({
    required String surface,
    required String headline,
    required String body,
    required List<String> perks,
    VoidCallback? onSignIn,
    VoidCallback? onSignInApple,
  }) async {
    // A Google Play build may not offer Premium at all (see canSellPremium);
    // the guest sign-in shape is not a sale and still shows.
    if (onSignIn == null && !canSellPremium) {
      _snack('This room ends at $_endsAtLabel.', kind: .info);
      return;
    }
    Analytics.instance.track('upgrade_cta_shown', {'surface': surface});
    await showGlassDialog<void>(
      context: context,
      width: 430,
      builder: (_) => PremiumTeaseDialog(
        headline: headline,
        body: body,
        perks: perks,
        onUpgrade: () {
          Analytics.instance.track('upgrade_cta_clicked', {
            'surface': surface,
            'action': 'subscribe',
          });
          context.push('/lobby/subscribe?source=$surface');
        },
        onNotify: () => Analytics.instance.track('upgrade_cta_clicked', {
          'surface': surface,
          'action': 'notify',
        }),
        onSignIn: onSignIn == null
            ? null
            : () {
                Analytics.instance.track('upgrade_cta_clicked', {
                  'surface': surface,
                  'action': 'sign_in',
                });
                onSignIn();
              },
        onSignInApple: onSignInApple == null
            ? null
            : () {
                Analytics.instance.track('upgrade_cta_clicked', {
                  'surface': surface,
                  'action': 'sign_in_apple',
                });
                onSignInApple();
              },
      ),
    );
    if (mounted) _shortcutFocus.requestFocus();
  }

  Future<void> _linkAppleIdentity() async {
    trace(
      'starting an Apple guest upgrade from the room',
      category: 'auth',
      data: {'room': widget.roomId},
    );
    try {
      await AuthService.instance.linkAppleIdentity();
    } catch (e, s) {
      reportNonFatal(e, s, during: 'linking an Apple identity from the expiry upsell');
      if (mounted) _snack("Couldn't start Apple sign-in. Try again.");
    }
  }

  Future<void> _linkGoogleIdentity() async {
    trace(
      'starting a guest upgrade from the room',
      category: 'auth',
      data: {'room': widget.roomId},
    );
    try {
      await AuthService.instance.linkGoogleIdentity();
    } catch (e, s) {
      reportNonFatal(e, s, during: 'linking a Google identity from the expiry upsell');
      if (mounted) _snack("Couldn't start Google sign-in. Try again.");
    }
  }

  String get _endsAtLabel {
    final room = _room;
    if (room == null) return '';
    final local = room.expiresAt.toLocal();
    final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour12:$minute $ampm';
  }

  void _showMicDeviceSelector(BuildContext buttonContext) {
    final av = _av;
    if (av == null) return;
    showRoomMicDeviceSelector(context: context, buttonContext: buttonContext, av: av);
  }

  void _showCamDeviceSelector(BuildContext buttonContext) {
    final av = _av;
    if (av == null) return;
    showRoomCamDeviceSelector(context: context, buttonContext: buttonContext, av: av);
  }

  void _showAudioOutputDeviceSelector(BuildContext buttonContext) {
    final av = _av;
    if (av == null) return;
    showRoomAudioOutputDeviceSelector(
      context: context,
      buttonContext: buttonContext,
      av: av,
      onAudioOutputSelected: (device) async {
        if (_mode == .local) {
          final playerDevices = _player.state.audioDevices;
          final match = playerDevices.where((d) {
            final devDesc = d.description.trim().toLowerCase();
            final targetLabel = device.label.trim().toLowerCase();
            final devName = d.name.trim().toLowerCase();
            final targetId = device.deviceId.trim().toLowerCase();
            return (devDesc.isNotEmpty &&
                    (devDesc == targetLabel ||
                        targetLabel.contains(devDesc) ||
                        devDesc.contains(targetLabel))) ||
                (targetId.isNotEmpty && devName.contains(targetId));
          }).firstOrNull;
          if (match != null) {
            unawaited(_player.setAudioDevice(match));
            trace(
              'switched player audio device',
              category: 'media',
              data: {'device': match.name, 'label': device.label},
            );
          }
        }
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  /// [compact] is the phone bar, the only one that also carries source, file
  /// and hide - the desktop and tablet bars keep to the boards and leave those
  /// to the room menu. What does not fit a bar folds into the bar's own More
  /// list, so nothing is left out here for want of room.
  RoomControlBarActions _controlActionsFor({bool docked = false, bool compact = false}) =>
      RoomControlBarActions(
        onPlayPause: _playPause,
        onSeek: _seek,
        onSkip: _skip,
        onMicToggle: (v) => _toggleFacecam('mic', v),
        onCamToggle: (v) => _toggleFacecam('cam', v),
        onCamLocked:
            (canSellPremium &&
                _av?.canPublishCamera == false &&
                !_startingVideoTrial &&
                !EntitlementService.instance.isPremium)
            ? () => context.push('/lobby/subscribe?source=camera_lock')
            : null,
        onVoiceLocked: _voiceLocked ? _explainVoiceLock : null,
        voiceLockedTooltip: _voiceLockedTooltip,
        onMicDeviceSelect: isDesktop && _av != null ? _showMicDeviceSelector : null,
        onCamDeviceSelect: isDesktop && _av != null ? _showCamDeviceSelector : null,
        onAudioOutputSelect: isDesktop && _mode == .local && _av != null
            ? _showAudioOutputDeviceSelector
            : null,
        audioOutputDisabledTooltip: isDesktop && _mode == .youtube
            ? 'Audio output selection is unavailable for YouTube'
            : null,
        onAudioTracks: !(compact || docked || _floatingBarIsWide)
            ? null
            : _mode == .local
            ? () => _showTrackChooser(subtitles: false)
            : null,
        onSubtitles: _mode == .local
            ? () => _showTrackChooser(subtitles: true)
            : (_mode == .youtube && _youtubeController != null)
            ? _showYouTubeCaptionChooser
            : null,
        // D1: only the host chooses what the room watches. Members keep a picker
        // purely to locate their own copy of the canonical file.
        onSwitchSource: compact && (_sync?.isHost ?? false) ? _handleSwitchSource : null,
        onOpenFile: compact && _mode == .local ? _pickVideo : null,
        openFileTooltip: (_sync?.isHost ?? false)
            ? 'Open file'
            : 'Locate your copy of ${_canonicalMedia.name ?? 'the file'}',
        onVolume: _setVolume,
        onToggleMute: _toggleMute,
        onReact: _sync != null ? _toggleReact : null,
        // A docked bar never hides, so it offers no hide button.
        onHideControls: compact && !docked ? _toggleControlsVisible : null,
        // Desktop toggles the window; a phone has no window to fill, so in
        // portrait its fullscreen turns the picture to landscape (board 46,
        // More), which already goes immersive. Landscape is that state, so it
        // offers nothing (and keeps the More list short enough for its slot);
        // tablets are big enough as they are.
        onFullscreenToggle: isDesktop
            ? _toggleFullscreen
            : compact && layoutOf(context) == PTLayout.portrait
            ? _turnToLandscape
            : null,
      );

  @override
  Widget build(BuildContext context) {
    _scheduleImmersiveSync(context);
    // The room sits on top of the lobby, so a system back gesture would pop
    // straight out of it - and a bare pop skips leave_room, stranding the
    // membership (member cap, authority election). Route it through _leaveRoom.
    // PopScope stays outside the loading branch so a back gesture during the
    // initial fetch is handled too.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Back closes an open menu first, as it did when the menu was a route.
        if (_overflowMenu?.isOpen ?? false) {
          _overflowMenu!.close();
          return;
        }
        _leaveRoom();
      },
      // A build failure anywhere in the room lands on a recovery screen whose
      // way out is the real leave, instead of a grey box over a live membership.
      child: PTErrorBoundary(
        where: 'room',
        onExit: _leaveRoom,
        exitLabel: 'Leave room',
        child: Scaffold(
          backgroundColor: PTColors.screenBg,
          // Cross-faded so the room *resolves* out of the spinner instead of the
          // whole layout flashing into place under it.
          body: AnimatedSwitcher(
            duration: PTMotion.functional(context, PTMotion.panel),
            switchInCurve: PTMotion.enter,
            switchOutCurve: PTMotion.exit,
            child: _loading
                ? const Center(key: ValueKey('loading'), child: PTLoader(size: 32))
                : Focus(
                    key: const ValueKey('room'),
                    focusNode: _shortcutFocus,
                    autofocus: true,
                    onKeyEvent: _handleKeyEvent,
                    child: Stack(
                      children: [
                        if (!isDesktop && foldOf(context).isSplit)
                          _folded(foldOf(context))
                        else
                          PTResponsive(
                            desktop: (_) => _desktop(),
                            tablet: (_) => _tablet(),
                            portrait: (_) => _portrait(),
                            landscape: (_) => _landscape(),
                          ),
                        if (_reactionStream != null && !_privacyHidden)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: ReactionOverlay(
                                reactions: _reactionStream!,
                                assets: _reactionAssets,
                                spawnBottom: switch (layoutOf(context)) {
                                  PTLayout.desktop || PTLayout.tablet => 180,
                                  PTLayout.landscape => 150,
                                  PTLayout.portrait => 96,
                                },
                                compact: switch (layoutOf(context)) {
                                  .desktop || .tablet => false,
                                  _ => true,
                                },
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _skipZones({required Widget child, VoidCallback? onTap}) {
    return RoomSkipZones(
      onTap: onTap,
      onSkip: (d) {
        if (_skip(d)) _flashSkip(d.isNegative ? -1 : 1);
      },
      onToggleFullscreen: _toggleFullscreen,
      isDesktop: isDesktop,
      child: child,
    );
  }

  Widget _sizedVideo(Widget video) =>
      VideoSurfaceSizer.supported ? VideoSurfaceSizer(controller: controller, child: video) : video;

  Widget _video() {
    // In-flow layouts put nothing over the picture, so there is nothing to clear.
    if (!_controlsOverVideo) _subtitleStyle?.setLift(0);
    return Stack(
      fit: .expand,
      children: [
        if (_mode == .local)
          _player.state.duration > Duration.zero || (!kDemoMode && !LiveKitService.isMockMode)
              ? widget.dependencies.videoView?.call(context, _player) ??
                    _sizedVideo(
                      Video(
                        controller: controller,
                        controls: NoVideoControls,
                        // The picture is shown whole, always: letterboxed in
                        // black inside whatever box a layout gives it (a tall
                        // half of a folded phone included), never cropped to
                        // fill it. Stated, not left to the package default.
                        fit: BoxFit.contain,
                        fill: PTColors.black(1),
                        filterQuality: .medium,
                        // libass draws subtitles into the frame; the Flutter
                        // view must never draw a second copy.
                        subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false),
                      ),
                    )
              // The demo still follows the same rule as the real picture.
              : ColoredBox(
                  color: PTColors.black(1),
                  child: Image.asset('assets/store/movie_still.jpg', fit: BoxFit.contain),
                ),
        if (_mode == .youtube && _youtubeController != null)
          // The embed is a display surface, not a control surface. Its own
          // chrome is stripped, but when an ad is actively playing, allow pointer
          // interaction so the user can click the native "Skip Ad" button.
          IgnorePointer(
            ignoring: !(_youtubeController!.isAdPlaying),
            child: PTYouTubeEmbed(
              // Keyed on the controller so a replaced one gets a fresh webview
              // rather than leaving the old element pointed at a closed
              // loopback server. Never key this by URL - switching video reuses
              // the controller by design.
              key: ObjectKey(_youtubeController!),
              controller: _youtubeController!,
            ),
          ),
        if (_mode == .youtube) ...[
          Positioned(
            top: 24,
            left: 24,
            // The badge fades in when an ad starts and out when it ends, and only takes
            // clicks while it is there.
            child: AnimatedOpacity(
              duration: PTMotion.functional(context, PTMotion.state),
              curve: PTMotion.enter,
              opacity: (_youtubeController?.isAdPlaying ?? false) ? 1 : 0,
              child: IgnorePointer(
                ignoring: !(_youtubeController?.isAdPlaying ?? false),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: PTColors.noticeSurface,
                    borderRadius: BorderRadius.circular(PTRadius.panel),
                    border: Border.all(color: PTColors.white(0.15)),
                  ),
                  child: Row(
                    mainAxisSize: .min,
                    children: [
                      const Icon(Icons.campaign_rounded, size: 16, color: PTColors.notice),
                      const SizedBox(width: 6),
                      Text(
                        'Ad in progress. Click Skip Ad when available',
                        style: PTText.caption.copyWith(color: PTColors.white(0.9)),
                      ),
                      if (kDebugMode) ...[
                        const SizedBox(width: 8),
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () {
                              _youtubeController?.debugToggleAdState();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: PTColors.white(0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'End Test Ad',
                                style: PTText.finePrint.copyWith(
                                  color: PTColors.textAccent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_youtubeController?.debugSimulatedAd ?? false)
            Positioned(
              bottom: 80,
              right: 24,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: PTColors.toastSurface,
                  borderRadius: BorderRadius.circular(PTRadius.control),
                  border: Border.all(color: PTColors.notice.withValues(alpha: 0.5)),
                  boxShadow: const [
                    BoxShadow(color: PTColors.shadow, blurRadius: 16, offset: Offset(0, 4)),
                  ],
                ),
                child: Row(
                  mainAxisSize: .min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: PTColors.notice,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Ad',
                        style: TextStyle(
                          color: PTColors.ink,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: .min,
                      children: [
                        Text(
                          'Simulated Ad Playing',
                          style: PTText.body.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: PTColors.white(0.95),
                          ),
                        ),
                        Text(
                          'Main video paused • Sync suspended',
                          style: PTText.caption.copyWith(fontSize: 11, color: PTColors.white(0.6)),
                        ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    PTButton(
                      label: 'Skip Ad',
                      trailingIcon: Symbols.skip_next_rounded,
                      height: 32,
                      expand: false,
                      onPressed: () {
                        _youtubeController?.debugToggleAdState();
                      },
                    ),
                  ],
                ),
              ),
            ),
        ],
        // Bottom scrim so glass controls always sit on something dark - a
        // band behind the controls, only while they show. libass draws
        // subtitles *into* the video frame, so anything painted over the
        // video paints over them too: the old full-height radial scrim, at its
        // darkest exactly where centred subtitles sit, dimmed them ~37% while
        // left/right-aligned lines stayed white. A plain gradient, so fading
        // it breaks no glass. Only where the controls actually float over
        // the picture - under a docked or in-flow bar it would dim subtitles
        // for nothing.
        if (_controlsOverVideo)
          Positioned.fill(
            child: IgnorePointer(
              child: LayoutBuilder(
                builder: (context, c) {
                  _liftSubtitles(c.maxHeight);
                  return Align(
                    alignment: .bottomCenter,
                    child: AnimatedOpacity(
                      opacity: _overlayShown ? 1 : 0,
                      duration: PTMotion.functional(context, Durations.medium2),
                      child: SizedBox(
                        width: double.infinity,
                        height: math.min(kControlScrimHeight, c.maxHeight * 0.3),
                        child: const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: .bottomCenter,
                              end: .topCenter,
                              colors: [PTColors.scrimTop, PTColors.scrimClear],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        // Cross-faded rather than mounted/unmounted: this covers every buffer
        // stall, not just room entry, and popping a scrim over the video on
        // each one is the flickeriest thing in the room.
        AnimatedOpacity(
          opacity: _showBuffering || _awaitingFirstSource ? 1 : 0,
          duration: PTMotion.functional(context, PTMotion.panel),
          // Opacity 0 skips painting but does NOT stop tickers, and this slot
          // now stays mounted for the whole session so it can fade. Without
          // TickerMode the spinner would drive a repaint every frame of every
          // film, forever.
          child: TickerMode(
            enabled: _showBuffering || _awaitingFirstSource,
            child: IgnorePointer(
              child: ColoredBox(
                color: PTColors.shadowSoft,
                // The caption gives way when the picture is too short for it (a
                // cover display at large text): a spinner alone beats an overflow.
                child: LayoutBuilder(
                  builder: (context, box) => Center(
                    child: Column(
                      mainAxisSize: .min,
                      children: [
                        const PTLoader(size: 44),
                        if (_awaitingFirstSource && box.maxHeight >= 130) ...[
                          const SizedBox(height: 18),
                          Text('Setting up the room…', style: PTText.caption),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // Covers the video only - chat, facecams and the member list stay
        // interactive while the room waits (D2). Mounted for as long as the
        // reveal is non-zero rather than while the gate is shut, so the exit
        // animation gets to play - and so the roster's entrance stagger fires
        // when the overlay actually appears, not when the room screen builds.
        Positioned.fill(
          child: LayoutBuilder(
            // Compact is judged by the video's own box, not the window: a
            // tablet-portrait or folded pane can be wide yet short.
            builder: (context, videoBox) => AnimatedBuilder(
              animation: _gateCurve,
              builder: (context, _) {
                final t = _gateCurve.value;
                // IgnorePointer even when empty: Positioned.fill hands down tight
                // constraints, so a bare SizedBox still fills (and blocks) the slot.
                if (t == 0) return const IgnorePointer(child: SizedBox.shrink());
                return IgnorePointer(
                  ignoring: _gateAnim.status == AnimationStatus.reverse,
                  child: ReadinessOverlay(
                    reveal: t,
                    headline: _gateHeadline,
                    members: _present,
                    premiumMembers: _premiumMembers,
                    memberFrames: _memberFrames,
                    media: _canonicalMedia,
                    selfId: _sync?.userId ?? '',
                    selfIsHost: _sync?.isHost ?? false,
                    compact: videoBox.maxWidth < 700 || videoBox.maxHeight < 460,
                    chromeInsets: _videoChromeInsets(),
                    uploadProgressWidget: (_uploadState == 'uploading' || _isUploadingSharedMedia)
                        ? Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: SharingProgressIndicator(
                              fraction: _uploadFraction,
                              speedBps: _uploadSpeedBps,
                              etaSeconds: _uploadEtaSeconds,
                              state: _uploadState,
                              label: (_sync?.isHost ?? false)
                                  ? 'Uploading shared media…'
                                  : 'Host is uploading media…',
                              onCancel: (_sync?.isHost ?? false) ? _cancelMediaSharingUpload : null,
                            ),
                          )
                        : null,
                    onLocateFile: _selfBlocksGate && _canonicalMedia.kind == .local
                        ? _pickVideo
                        : null,
                    openFailed: _selfFileFailed,
                    onStartWithout: _canStartWithout ? _startWithoutStragglers : null,
                    startWithoutLabel: _startWithoutLabel,
                    onPickSource: _hostMustChoose
                        ? (_mode == .youtube ? _promptYouTubeLink : _pickVideo)
                        : null,
                    pickSourceLabel: _mode == .youtube ? 'Paste a YouTube link' : 'Choose a video',
                    onSwitchSource: _hostMustChoose ? _handleSwitchSource : null,
                    switchSourceLabel: _mode == .youtube
                        ? 'Choose a video instead'
                        : 'Use a YouTube link instead',
                    switchSourceShortLabel: _mode == .youtube ? 'Local file' : 'YouTube link',
                    reopenName: _hostMustChoose && _mode == .local && _reopenOffered
                        ? _lastRecent!.displayName
                        : null,
                    reopenAgo: _lastRecent == null
                        ? null
                        : formatAgoShort(_lastRecent!.lastOpened, DateTime.now()),
                    onReopen: _reopenLastRecent,
                    onPickPhotos: _hostMustChoose && _mode == .local && photosAvailable
                        ? () => _pickVideo(autoStart: ChoiceSource.photos)
                        : null,
                    onPickFiles: _hostMustChoose && _mode == .local && photosAvailable
                        ? () => _pickVideo(autoStart: ChoiceSource.files)
                        : null,
                    onKick: _confirmKick,
                  ),
                );
              },
            ),
          ),
        ),
        if (_skipFlash != 0)
          Positioned.fill(
            child: IgnorePointer(
              child: Align(
                alignment: _skipFlash < 0 ? const Alignment(-0.55, 0) : const Alignment(0.55, 0),
                child: _skipFlashBadge(_skipFlash < 0),
              ),
            ),
          ),
        Positioned(
          top: 72,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Center(
              // Drops in from above and rises on the way out. The pill is an
              // opaque panel, and AnimatedSlide + AnimatedOpacity provide a
              // clean entrance and exit.
              child: AnimatedSlide(
                offset: _actionToastVisible ? Offset.zero : const Offset(0, -0.4),
                duration: PTMotion.functional(context, PTMotion.state),
                curve: !_actionToastVisible
                    ? PTMotion.exit
                    : _actionToastArrival
                    ? PTMotion.arrive
                    : PTMotion.enter,
                child: AnimatedOpacity(
                  opacity: _actionToastVisible ? 1 : 0,
                  duration: PTMotion.functional(context, PTMotion.state),
                  child: GlassPill(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    child: Row(
                      mainAxisSize: .min,
                      spacing: 8,
                      children: [
                        const Icon(Symbols.sync_alt_rounded, size: 16, color: PTColors.textAccent),
                        // A second action landing while the toast is still up
                        // swaps the line rather than hard-cutting it.
                        AnimatedSize(
                          duration: PTMotion.functional(context, PTMotion.state),
                          curve: PTMotion.enter,
                          child: AnimatedSwitcher(
                            duration: PTMotion.functional(context, PTMotion.state),
                            switchInCurve: PTMotion.enter,
                            switchOutCurve: PTMotion.exit,
                            child: Text(
                              _actionToastText,
                              key: ValueKey(_actionToastText),
                              style: PTText.body.copyWith(
                                fontSize: 13,
                                color: PTColors.white(0.85),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        IgnorePointer(
          child: AnimatedOpacity(
            opacity: _privacyHidden ? 1 : 0,
            duration: PTMotion.functional(context, PTMotion.panel),
            child: const ColoredBox(
              color: PTColors.ink,
              child: Center(child: PTLogoMark(size: 88)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _skipFlashBadge(bool backward) =>
      RoomSkipFlashBadge(backward: backward, animationKey: _skipFlashTimer);

  Widget _roomPill({bool compact = false}) {
    final room = _room!;
    return RoomPill(
      room: room,
      compact: compact,
      syncDotState: _syncDotState,
      isHost: _sync?.isHost ?? false,
      timeLeft: _timeLeft,
      countdownLabel: _countdownLabel,
      onCopyCode: _copyCode,
      onExtendRoom: _extendRoom,
      isExtending: _extending,
      isYouTube: _mode == .youtube,
      isAdPlaying: _youtubeController?.isAdPlaying ?? false,
      onDebugToggleAd: () {
        _youtubeController?.debugToggleAdState();
        final isAd = _youtubeController?.isAdPlaying ?? false;
        if (isAd) {
          _snack('Ad simulated: playback & sync paused', kind: .info);
        }
      },
    );
  }

  /// Banners, each sliding down into place instead of popping.
  ///
  /// The stable `ValueKey`s live on the *wrapper*, not the `PTBanner`: they are
  /// what stops `_tickCountdown`'s per-second rebuild from restarting the T-5
  /// auto-dismiss ring, and an unkeyed wrapper would reintroduce that by making
  /// the list match children positionally again.
  /// The date night that is on, when its planner attached a film and nobody has
  /// started it yet: Our Room opened with the film loaded, and this says so.
  Widget? _dateNightBanner() {
    final room = _room;
    if (room == null || !room.isOurRoom || _dateNightBannerDismissed || _playing) return null;
    final svc = PairService.instance;
    final now = DateTime.now().toUtc();
    final night = featuredNight(now, svc.nights);
    if (night == null || !isNightImminent(now, night)) return null;
    final mine = night.proposedBy == _sync?.userId;
    final first = svc.pair?.partner.displayName.split(' ').first ?? 'Your person';
    final arriving = night.hasFile && !night.fileReady && !night.fileStopped;
    if (!night.attachmentReady && !arriving) return null;
    return PTEntrance(
      key: ValueKey(arriving ? 'date-night-arriving' : 'date-night-ready'),
      offset: -8,
      duration: PTMotion.state,
      child: PTBanner(
        kind: arriving ? .warning : .info,
        icon: arriving ? BoothIcons.cloudUpload : BoothIcons.film,
        title: 'Date night · ${night.title}',
        subtitle: arriving
            ? '${mine ? 'Your' : "$first's"} movie is still uploading (${night.uploadPercent}%). '
                  'It plays as soon as it lands, or pick something else.'
            : mine
            ? "Tonight's film is loaded. Press play when you're both here."
            : "$first picked tonight's film. Press play when you're both here.",
        onDismiss: () => setState(() => _dateNightBannerDismissed = true),
      ),
    );
  }

  List<Widget> _banners() {
    final dateNight = _dateNightBanner();
    return [
      ?dateNight,
      if (!_warningDismissed &&
          _timeLeft > Duration.zero &&
          _timeLeft <= const Duration(minutes: 5))
        PTEntrance(
          key: const ValueKey('t5-warning'),
          offset: -8,
          duration: PTMotion.state,
          child: PTBanner(
            autoDismissAfter: (_sync?.isHost ?? false) ? null : const Duration(seconds: 10),
            pulseOnArrival: true,
            kind: .warning,
            icon: BoothIcons.schedule,
            title: () {
              final mins = (_timeLeft.inSeconds / 60).ceil();
              return '$mins minute${mins == 1 ? '' : 's'} left';
            }(),
            subtitle: _expirySubtitle,
            trailing: (_sync?.isHost ?? false)
                ? PTButton(
                    label: _extendLabel,
                    icon: _extendIcon,
                    variant: .secondary,
                    height: 38,
                    expand: false,
                    loading: _extending,
                    onPressed: _extending ? null : _extendRoom,
                  )
                : null,
            onDismiss: () => setState(() => _warningDismissed = true),
          ),
        ),
      if (!_connected)
        const PTEntrance(
          key: ValueKey('reconnecting'),
          offset: -8,
          duration: PTMotion.state,
          child: PTBanner(
            kind: .info,
            icon: Symbols.sync_rounded,
            spinIcon: true,
            showActivity: true,
            title: 'Reconnecting…',
            subtitle: 'Hang tight, getting you back in sync.',
          ),
        ),
      if (_suspectWrongFile)
        PTEntrance(
          key: const ValueKey('wrong-file-suspect'),
          offset: -8,
          duration: PTMotion.state,
          child: PTBanner(
            kind: .warning,
            icon: Symbols.difference_rounded,
            title: 'Is this the same movie?',
            subtitle:
                '${_roomFile?.name ?? 'The room\'s video'} looks different from your '
                '$_localFileName. If it is the same film, you can join anyway.',
            trailing: PTButton(
              label: 'Same movie',
              variant: .secondary,
              height: 38,
              expand: false,
              onPressed: _confirmSameMovie,
            ),
          ),
        ),
      if (_durationDrifts)
        PTEntrance(
          key: const ValueKey('duration-drift'),
          offset: -8,
          duration: PTMotion.state,
          child: PTBanner(
            kind: .warning,
            icon: Symbols.difference_rounded,
            title: 'Same name, different length',
            subtitle:
                'Your copy of ${_roomFile!.name} runs a little different, so you might drift apart.',
            trailing: PTButton(
              label: 'Pick another',
              variant: .secondary,
              height: 38,
              expand: false,
              onPressed: _pickVideo,
            ),
            onDismiss: () => setState(() => _mismatchDismissed = true),
          ),
        ),
      if (_showCopyExpiredNotice)
        PTEntrance(
          key: const ValueKey('shared-copy-expired'),
          offset: -8,
          duration: PTMotion.state,
          child: SharedCopyExpiredBanner(
            subtitle: ourRoomCopyExpiredSubtitle(
              patron: PairService.instance.pair?.patron ?? false,
            ),
            onPickMyCopy: () {
              setState(() => _copyExpiredDismissed = true);
              _pickVideo();
            },
            onDismiss: () => setState(() => _copyExpiredDismissed = true),
          ),
        ),
      if (_streamingFallbackNotice && _localFileName != _canonicalMedia.name)
        PTEntrance(
          key: const ValueKey('streaming-fallback'),
          offset: -8,
          duration: PTMotion.state,
          child: StreamingFallbackBanner(
            onUseMyCopy: () {
              setState(() => _streamingFallbackNotice = false);
              _pickVideo();
            },
            onDismiss: () => setState(() => _streamingFallbackNotice = false),
          ),
        ),
      if ((_sync?.isHost ?? false) && _mode == .local && _uploadState == 'failed')
        PTEntrance(
          key: const ValueKey('media-sharing-failed'),
          offset: -8,
          duration: PTMotion.state,
          child: PTBanner(
            kind: .error,
            icon: Symbols.cloud_off_rounded,
            title: 'Media upload failed',
            subtitle: 'Participants without a local copy cannot watch until uploaded.',
            trailing: PTButton(
              label: 'Retry upload',
              icon: BoothIcons.restore,
              variant: .primary,
              height: 38,
              expand: false,
              loading: _isUploadingSharedMedia,
              onPressed: _retryLocalUpload,
            ),
            onDismiss: () => setState(() => _uploadState = 'none'),
          ),
        ),
      if ((_sync?.isHost ?? false) &&
          _mode == .local &&
          (_uploadState == 'uploading' || _isUploadingSharedMedia) &&
          _allMembersLocallyReady &&
          !_localReadyPromptDismissed)
        PTEntrance(
          key: const ValueKey('all-members-locally-ready'),
          offset: -8,
          duration: PTMotion.state,
          child: PTBanner(
            kind: .info,
            icon: Symbols.check_circle_rounded,
            title: 'Everyone has a local copy!',
            subtitle: 'Playback is ready. Cancel upload to save quota, or keep uploading for late joiners.',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                PTButton(
                  label: 'Cancel upload',
                  icon: BoothIcons.close,
                  variant: .primary,
                  height: 36,
                  expand: false,
                  onPressed: () {
                    setState(() => _localReadyPromptDismissed = true);
                    _cancelMediaSharingUpload();
                  },
                ),
                PTButton(
                  label: 'Keep uploading',
                  variant: .secondary,
                  height: 36,
                  expand: false,
                  onPressed: () => setState(() => _localReadyPromptDismissed = true),
                ),
              ],
            ),
            onDismiss: () => setState(() => _localReadyPromptDismissed = true),
          ),
        ),
      ..._streamNoticeBanners(),
    ];
  }

  /// The gentle connection notice, in three states (design board 51). Info
  /// style throughout, never blocks playback, never for a local file.
  List<Widget> _streamNoticeBanners() {
    final session = _stream;
    if (session == null || _mode != .local || !_isStreamingRemoteSharedMedia) return const [];
    final notice = session.notice;
    switch (notice.notice) {
      case StreamNotice.none:
        return const [];
      case StreamNotice.bufferingMore:
        return [
          PTEntrance(
            key: const ValueKey('stream-notice-buffering-more'),
            offset: -8,
            duration: PTMotion.state,
            child: PTBanner(
              kind: .info,
              icon: BoothIcons.clock,
              title: 'Buffering a little more',
              subtitle: 'Smoothing things out so it plays without pauses.',
              showActivity: true,
              autoDismissAfter: const Duration(seconds: 6),
              onDismiss: notice.dismiss,
            ),
          ),
        ];
      case StreamNotice.connection:
        final need = notice.requiredBps ?? 0;
        final have = notice.capacityBps ?? 0;
        return [
          PTEntrance(
            key: const ValueKey('stream-notice-connection'),
            offset: -8,
            duration: PTMotion.state,
            child: PTBanner(
              kind: .info,
              icon: BoothIcons.info,
              title: 'This video is high quality (${formatMbps(need)})',
              subtitle:
                  'Your connection looks like it can keep up with ${formatMbps(have)} right now, '
                  'so it may pause now and then. You can let it buffer ahead first.',
              trailing: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  PTButton(
                    label: 'Buffer ahead',
                    variant: .primary,
                    height: 36,
                    expand: false,
                    onPressed: () {
                      Analytics.instance.track('stream_notice_answered', {
                        'choice': 'buffer_ahead',
                      });
                      session.bufferAhead();
                    },
                  ),
                  PTButton(
                    label: 'Keep going',
                    variant: .secondary,
                    height: 36,
                    expand: false,
                    onPressed: _keepGoingOnStreamNotice,
                  ),
                ],
              ),
              onDismiss: notice.dismiss,
            ),
          ),
        ];
      case StreamNotice.bufferingAhead:
        final (have, want) = session.holdProgress;
        return [
          PTEntrance(
            key: const ValueKey('stream-notice-buffering-ahead'),
            offset: -8,
            duration: PTMotion.state,
            child: PTBanner(
              kind: .info,
              icon: BoothIcons.clock,
              title: 'Buffering ahead',
              subtitle:
                  'About $have s of $want s is ready. You will show as loading to the room until then.',
              showActivity: true,
              trailing: PTButton(
                label: 'Start anyway',
                variant: .secondary,
                height: 36,
                expand: false,
                onPressed: session.releaseHold,
              ),
              onDismiss: session.releaseHold,
            ),
          ),
        ];
    }
  }

  void _keepGoingOnStreamNotice() {
    Analytics.instance.track('stream_notice_answered', {'choice': 'keep_going'});
    _stream?.notice.dismiss();
  }

  /// Collapses to nothing when the last banner goes, so dismissing one doesn't
  /// yank the layout by a banner height.
  ///
  /// Capped at a third of the window and scrollable past that: the floating
  /// layouts place this in a Positioned, so three stacked banners at a large
  /// text scale would otherwise overflow the room.
  ///
  /// [inScroll] is for stacks already inside a scroll view ([_aboveChat]):
  /// those take their natural height, since a second, nested scroll view
  /// would leave its end reachable only by scrolling both.
  Widget _bannerStack({
    required double spacing,
    EdgeInsets padding = EdgeInsets.zero,
    bool inScroll = false,
  }) {
    return RoomBannerStack(
      banners: _banners(),
      spacing: spacing,
      padding: padding,
      inScroll: inScroll,
    );
  }

  /// Floating stack of the last few incoming messages, shown while the chat
  /// panel is closed (desktop/landscape). Bottom-aligned so new bubbles push up.
  /// Deliberately *not* wrapped in an `IgnorePointer`: the bubbles themselves are
  /// tap targets that open the panel, and the bare Column/Padding around them
  /// hit-tests children only, so the empty gaps still pass clicks to the video.
  Widget _chatOverlay() => RoomChatOverlay(
    messages: _overlayChat,
    expiringMessages: _expiringChat,
    premiumMembers: _premiumMembers,
    memberFrames: _memberFrames,
    onTapMessage: _openChat,
  );

  Widget _chatRevealed({required double offscreen, required Widget panel}) =>
      RoomChatRevealed(animation: _chatCurve, offscreen: offscreen, panel: panel);

  Widget _chatDisplaced(Widget displaced) =>
      RoomChatDisplaced(animation: _chatCurve, displaced: displaced);

  Widget _reactionStrip({bool compact = false}) {
    final available = reactionsForTier(EntitlementService.instance.tier);
    final isPremium = EntitlementService.instance.isPremium;
    return ReactionStrip(
      open: _reactOpen,
      assets: _reactionAssets,
      compact: compact,
      reactions: available.take(kBaseReactionCount).toList(growable: false),
      hasMore: available.length > kBaseReactionCount,
      onMore: _showReactionPicker,
      showLockedMore: !isPremium && canSellPremium,
      onLockedMore: () {
        setState(() => _reactOpen = false);
        context.push('/lobby/subscribe?source=reaction_lock');
      },
      onPick: _sendReaction,
    );
  }

  Widget _chatToggleButton({double size = 44, bool glass = true}) {
    return UnreadBadge(
      count: _unread,
      child: PTIconButton(
        icon: BoothIcons.chat,
        size: size,
        iconSize: size < 44 ? 18 : 21,
        glass: glass,
        active: _chatOpen,
        tooltip: _chatOpen ? 'Close chat (C)' : 'Party chat (C)',
        onPressed: _toggleChat,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Layout builders
  //
  // Every builder places the *same* hoisted video - [_videoSurface] carries a
  // GlobalKey - so crossing a layout class (split-view drag, rotation,
  // fold/unfold) reparents it instead of remounting it. Each builder must
  // mount it at most once. [_chatPanel] is deliberately NOT keyed: its
  // composer owns an OverlayPortal, which cannot survive a reparent, so it
  // remounts and the draft is carried by [_chatDraft] instead.
  // ---------------------------------------------------------------------------

  /// How much of the video box the floating chrome (top actions, control
  /// bar, and in phone landscape the chat column and facecam rail) covers, so
  /// the readiness card sits in the gap above the bar - bottom-anchored, never
  /// under it, the rail or the chat. Zero for the in-flow layouts, whose chrome
  /// sits outside the video box.
  EdgeInsets _videoChromeInsets() {
    final fold = !isDesktop ? foldOf(context) : null;
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.4);
    if (fold != null && fold.isSplit) {
      // Book fold: the bar floats 16 px up from the pane's bottom, ~135 tall.
      return fold.axis == .vertical
          ? EdgeInsets.only(top: 60, bottom: 156 * scale)
          : EdgeInsets.zero;
    }
    if (_chatEmbedded || !_controlsOverVideo) return EdgeInsets.zero;
    if (layoutOf(context) != .landscape) {
      // The roomy composition (touch tablets, an unfolded iPhone Duo held
      // landscape) keeps its facecam rail down the left edge: 24 in, 200 wide.
      // On a window as narrow as the Duo's 951 pt the centred card would run
      // under it, so the card gives that column up - less what the video
      // surface itself already yields to the rail (see [railClearance]).
      final railLeft =
          layoutOf(context) == .tablet && _av != null && !_privacyHidden && _camsVisible;
      return EdgeInsets.only(
        left: railLeft ? kRailReserve - railClearance(MediaQuery.sizeOf(context)) : 0,
        top: 76 * scale,
        bottom: 154 * scale,
      );
    }
    // Phone landscape: the chat column and the rail hug the right edge of the
    // safe area (56 px in); the card stays left of whichever is showing.
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final edge = math.max(56.0, math.max(pad.left, pad.right));
    final safeWidth = size.width - 2 * edge;
    var right = 0.0;
    if (_chatOpen && landscapeChatFits(safeWidth)) right += landscapeChatWidth(safeWidth) + 12;
    if (_av != null && !_privacyHidden && _camsVisible) {
      // Judged against the shortest bar form so the reserve is never too small.
      final slot = size.height - (kLandscapeBarInset + 86) - kRailGap - kRailTop;
      right += railPlanFor(slot).tileWidth + 12;
    }
    return EdgeInsets.only(
      top: 60 * scale,
      right: right == 0 ? 0 : math.max(0, edge + right - pad.right - 12),
      // The bar's inset (22) plus its tallest form: ~136, growing ~20 px per
      // 1x of text scale (the forms step down rather than scale, so no more).
      bottom:
          kLandscapeBarInset +
          136 +
          20 * (MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0) - 1),
    );
  }

  /// Raises libass's subtitles by the control bar's height while the bar is
  /// showing over the picture, so a centred line is never hidden behind it;
  /// hiding the controls (H, a click) drops them back. Called from the
  /// scrim's layout builder because that is where the picture's real height is
  /// known, so it only touches the applier - which ignores an unchanged value
  /// and does its mpv writes off the build path.
  void _liftSubtitles(double videoHeight) {
    final applier = _subtitleStyle;
    if (applier == null) return;
    if (!_overlayShown || videoHeight <= 0) return applier.setLift(0);
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.4);
    applier.setLift(100 * kSubtitleLiftPx * scale / videoHeight);
  }

  Widget _videoSurface() => PTErrorBoundary(
    where: 'video',
    compact: true,
    child: KeyedSubtree(key: _videoKey, child: _video()),
  );

  /// Whether chat is laid out inline (always visible) rather than toggled as
  /// a floating panel: phone portrait, tablet portrait and folded panes.
  bool get _chatEmbedded {
    if (!isDesktop && foldOf(context).isSplit) return true;
    return switch (layoutOf(context)) {
      .portrait => true,
      .tablet => MediaQuery.sizeOf(context).height >= MediaQuery.sizeOf(context).width,
      _ => false,
    };
  }

  Widget _chatPanel({bool embedded = false, bool docked = false}) {
    final sync = _sync!;
    return PTErrorBoundary(
      where: 'chat',
      compact: true,
      child: RoomChatPanel(
        draftController: _chatDraft,
        keyboardMemory: _keyboardMemory,
        onInlinePickerChanged: embedded
            ? (up) {
                if (mounted && _chatPickerUp != up) setState(() => _chatPickerUp = up);
              }
            : null,
        sync: sync,
        messages: _visibleMessages,
        premiumMembers: _premiumMembers,
        memberFrames: _memberFrames,
        typingNames: _typingNames,
        watchingCount: _present.length,
        onClose: embedded ? () {} : _toggleChat,
        onSend: _sendChat,
        onCopied: _onChatCopied,
        onPlaySharedVideo: (_sync?.isHost ?? false) ? _playSharedVideo : null,
        onReportMessage: (msg) => _showReportDialog(
          targetUserId: msg.senderId,
          targetUser: msg.displayName,
          messageSnippet: msg.content,
        ),
        embedded: embedded,
        docked: docked,
        // The desktop compositions close it from their own chat key,
        // but in floating overlay mode (fullscreen or roomy) provide the close button.
        closable: !docked && layoutOf(context) != .desktop,
        // Everyone present, blocked or not: the gate waits on all of them, so
        // the roster mirrors the readiness overlay rather than the chat feed.
        rosterFold: embedded ? _rosterFold : null,
        roster: isDesktop || docked || embedded
            ? [
                for (final m in _present)
                  ChatRosterSeat(
                    member: m,
                    ready: sync.memberSatisfiesGate(m),
                    premium: _premiumMembers.contains(m.userId),
                    frame: _memberFrames[m.userId],
                  ),
              ]
            : null,
      ),
    );
  }

  /// The inline chat used by the embedded layouts: no card, just a Rail
  /// hairline where it starts - the phone room is one continuous booth.
  Widget _embeddedChat({EdgeInsets padding = const EdgeInsets.only(top: 12)}) {
    return Padding(
      padding: padding,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: PTColors.aisle)),
        ),
        child: _sync != null ? _chatPanel(embedded: true) : const SizedBox.shrink(),
      ),
    );
  }

  /// Whether the floating desktop bar is wide enough for the Desktop room
  /// board's row, which carries the AUDIO key (so the menu drops it). The bar
  /// sits 16 px in from each window edge with 16 px of panel padding inside,
  /// and decides on its row width against the same [kFloatingBoardWidth].
  bool get _floatingBarIsWide =>
      layoutOf(context) == .desktop && MediaQuery.sizeOf(context).width - 64 >= kFloatingBoardWidth;

  Widget _controlBar({bool compact = false, bool docked = false}) {
    return ValueListenableBuilder(
      valueListenable: _positionNotifier,
      builder: (context, position, _) => _controlBarAt(position, compact: compact, docked: docked),
    );
  }

  Widget _controlBarAt(Duration position, {required bool compact, bool docked = false}) =>
      _barWidget(position, compact: compact, docked: docked);

  RoomControlBar _barWidget(Duration position, {required bool compact, bool docked = false}) {
    return RoomControlBar(
      playing: _playing,
      position: position,
      duration: _duration,
      bufferedPosition: _isStreamingRemoteSharedMedia && _mode == .local ? _bufferPosition : null,
      volume: _volume,
      micOn: _av?.micEnabled ?? false,
      camOn: _av?.camEnabled ?? false,
      avAvailable: _av != null,
      camAvailable: (_av?.canPublishCamera ?? false) || _videoTrialOnOffer || _startingVideoTrial,
      camTrialMinutes: _videoTrialOnOffer ? kVideoTrialOfferMinutes : null,
      actions: _controlActionsFor(docked: docked, compact: compact),
      sourceTag: _mode == .local ? 'Local file' : 'YouTube',
      subtitleTag: _mode == .local ? shortTrackTag(_player.state.track.subtitle) : null,
      audioTag: _mode == .local ? shortTrackTag(_player.state.track.audio) : null,
      fullscreen: _fullscreen,
      docked: docked,
      reactOpen: _reactOpen,
      transportEnabled: _transportBlockedReason == null,
      // The readiness card already says who we are waiting for; repeating
      // it under the transport cost phone landscape the room to show the
      // card at all.
      transportHint: _gateOverlayUp ? null : _transportBlockedReason,
      compact: compact,
    );
  }

  /// What the room menu carries beyond the board's own items: whatever the
  /// current bar never has a key for. The desktop and tablet bars never carry
  /// the source and file pickers (the boards give them no key), and the
  /// floating bar has no audio key. A phone bar carries all of them, folding
  /// them into its own More list when it runs short of room.
  List<RoomMenuAction> _menuPlaybackActions() {
    final layout = layoutOf(context);
    final compact = layout != .desktop && layout != .tablet;
    final a = _controlActionsFor(compact: true);
    final pickersInMenu = !compact;
    final audioInMenu = !compact && layout != .desktop;
    return [
      if (pickersInMenu && a.onSwitchSource != null)
        RoomMenuAction(icon: BoothIcons.youtube, label: 'Switch source', onTap: a.onSwitchSource!),
      if (pickersInMenu && a.onOpenFile != null)
        RoomMenuAction(
          icon: BoothIcons.file,
          label: a.openFileTooltip ?? 'Open file',
          onTap: a.onOpenFile!,
        ),
      if (audioInMenu && a.onAudioTracks != null)
        RoomMenuAction(
          icon: Symbols.audiotrack_rounded,
          label: 'Audio track',
          onTap: a.onAudioTracks!,
        ),
      // The phone header keeps to the board (no sharing square), so the
      // resting "share" action moves here.
      if (compact && _canOfferShareWithRoom)
        RoomMenuAction(
          icon: BoothIcons.cloudUpload,
          label: 'Share with room',
          onTap: _retryLocalUpload,
        ),
      if (inputOf(context) != .touch)
        RoomMenuAction(
          icon: Symbols.keyboard_rounded,
          label: 'Keyboard shortcuts',
          onTap: _showShortcuts,
        ),
      // Debug builds against a stack with AV_DEBUG_SWITCHING: move the whole
      // room to another endpoint to exercise the failover path by hand.
      if (kDebugMode && (_av?.endpoints.length ?? 0) > 1)
        RoomMenuAction(
          icon: Symbols.swap_horiz_rounded,
          label: 'AV endpoint (debug): ${_av?.endpoint}',
          onTap: _showAvEndpointChooser,
        ),
    ];
  }

  Future<void> _showAvEndpointChooser() async {
    final av = _av;
    if (av == null) return;
    return showRoomAvEndpointChooser(context: context, av: av);
  }

  /// The host has a local file the tier may share and nothing is uploading.
  bool get _canOfferShareWithRoom =>
      _mode == .local &&
      (_sync?.isHost ?? false) &&
      _localFileName != null &&
      (EntitlementService.instance.limits?.canShareMedia ?? false) &&
      _uploadState == 'none' &&
      !_isUploadingSharedMedia;

  /// Room pill (+ sharing pill) on the left, chat toggle and overflow on the right.
  /// Expanded (not Flexible+Spacer: they'd split the free space 50/50,
  /// stranding the action icons mid-screen) pins the icons to the edge.
  Widget _topActions({bool compact = false, bool chatToggle = true}) {
    return Row(
      crossAxisAlignment: .start,
      children: [
        // One row, never a wrap: a sharing pill wrapping under the room pill
        // floated a lone chip over the video. The room pill (whose title
        // already ellipsizes) gives up width instead.
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              // A narrow row (a 455 pt half of a folded iPhone Duo at large
              // text) cannot carry a labelled pill beside the room pill: the
              // transient state steps down to an icon with the label as its
              // tooltip, rather than squeezing the room pill to nothing.
              final narrow = compact && box.maxWidth < MediaQuery.textScalerOf(context).scale(320);
              return Row(
                spacing: 10,
                children: [
                  Flexible(child: _roomPill(compact: compact)),
                  // Compact rows (phone landscape, fold panes) take the resting
                  // states as an icon; only the transient ones keep a label.
                  if (compact && _mediaSharingIcon() != null)
                    _mediaSharingIcon()!
                  else if (narrow && _mediaSharingTransientIcon() != null)
                    _mediaSharingTransientIcon()!
                  else
                    ?_mediaSharingPill(compact: compact),
                ],
              );
            },
          ),
        ),
        if (chatToggle) ...[
          SizedBox(width: compact ? 12 : 10),
          _chatToggleButton(size: compact ? 44 : 40),
        ],
        SizedBox(width: compact ? 10 : 10),
        // Desktop carries the button in the marquee bar instead.
        if (!isDesktop) ...[const BugReportButton(), const SizedBox(width: 6)],
        PTIconButton(
          icon: BoothIcons.moreVert,
          size: compact ? 44 : 40,
          iconSize: compact ? 21 : 18,
          tooltip: 'Room menu',
          onPressed: _openOverflowMenu,
        ),
      ],
    );
  }

  Widget _facecamStrip() {
    return FacecamRail(
      av: _av!,
      present: _visiblePresent,
      premiumMembers: _premiumMembers,
      memberFrames: _memberFrames,
      selfId: _sync?.userId ?? '',
      layout: .stripTop,
      trialEndsAt: _trialChipEndsAt,
      now: () => RoomService.instance.serverNow,
      showTrialEnded: _videoTrialEndedNote,
      onKeepFaces: _offersKeepFaces ? _keepFacesOn : null,
    );
  }

  /// Every pointer window gets the docked theatre; its chat column narrows in
  /// a small window (`kTheaterChatShare`) rather than switching composition.
  /// The roomy floating one is for touch tablets only.
  Widget _desktop() => _theater();

  /// Whether the chrome floats over the video in the current layout. Never on
  /// desktop: the theatre docks its marquee and control bars around the picture.
  bool get _controlsOverVideo {
    if (_kbOverlayOn) return true;
    if (!isDesktop && foldOf(context).isSplit) return foldOf(context).axis == .vertical;
    if (layoutOf(context) == .desktop) return false;
    return !_chatEmbedded;
  }

  /// The Desktop room board: the marquee bar across the top (it carries the
  /// window controls), the picture, a flat control bar under it, and chat as
  /// a Seat column beside both. Nothing is painted over the picture, so
  /// subtitles are never covered. In fullscreen H or a click on the picture
  /// collapses both bars; in a window only the control bar goes, since the
  /// marquee bar is where the traffic lights live.
  Widget _theater() {
    final camsUp = _av != null && !_privacyHidden;
    return RoomTheaterLayout(
      videoSurface: GestureDetector(
        behavior: .opaque,
        onTap: _toggleControlsVisible,
        child: _videoSurface(),
      ),
      topBar: _theaterTopBar(),
      controlBar: _controlBar(docked: true),
      reactionStrip: _reactionStrip(),
      bannerStack: _bannerStack(spacing: 12),
      showControlsButton: _showControlsButton(),
      fullscreen: _fullscreen,
      controlsVisible: _controlsVisible,
      cursorVisible: _cursorVisible,
      reactOpen: _reactOpen,
      chatCurve: _chatCurve,
      chatAnim: _chatAnim,
      onMouseMove: _onMouseMove,
      facecamRail: (camsUp && _camsVisible)
          ? FacecamRail(
              av: _av!,
              present: _visiblePresent,
              premiumMembers: _premiumMembers,
              memberFrames: _memberFrames,
              selfId: _sync?.userId ?? '',
              layout: .railLeft,
              trialEndsAt: _trialChipEndsAt,
              now: () => RoomService.instance.serverNow,
              showTrialEnded: _videoTrialEndedNote,
              onKeepFaces: _offersKeepFaces ? _keepFacesOn : null,
              showNames: _controlsVisible,
              onHide: () => setState(() => _camsVisible = false),
            )
          : null,
      showCamsPill: (camsUp && !_camsVisible)
          ? PTActionPill(
              label: 'Show cams',
              icon: BoothIcons.chevronRight,
              onTap: () => setState(() => _camsVisible = true),
            )
          : null,
      overlayChat: _overlayChat.isNotEmpty ? _chatDisplaced(_chatOverlay()) : null,
      chatPanel: _sync != null ? _chatPanel(docked: true) : null,
    );
  }

  /// Name, paper code tag, the sync heartbeat and "house lights in ..." on one
  /// hairline-ruled strip. Pieces step out as the column narrows - the label
  /// beside the dot first, then Invite (the menu has it) - never wrap.
  Widget _theaterTopBar() {
    final room = _room!;
    final isHost = _sync?.isHost ?? false;
    final urgent = _timeLeft > Duration.zero && _timeLeft <= const Duration(minutes: 5);
    return LayoutBuilder(
      builder: (context, box) {
        final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
        final wide = box.maxWidth >= 860 * scale;
        final invite = box.maxWidth >= 700 * scale;
        // The countdown's "HOUSE LIGHTS IN" prefix goes before the sync
        // label does - the dot's words are the product's promise.
        final spelled = box.maxWidth >= 1000 * scale;

        final leading = Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: PTIconButton(
                  icon: BoothIcons.chevronLeft,
                  glass: false,
                  size: 36,
                  iconSize: 20,
                  tooltip: 'Back to the lobby',
                  onPressed: _leaveRoom,
                ),
              ),
              Expanded(
                child: Row(
                  spacing: 14,
                  children: [
                    Flexible(
                      child: Text(
                        room.name,
                        maxLines: 1,
                        overflow: .ellipsis,
                        style: PTText.panelHeading.copyWith(fontSize: 17),
                      ),
                    ),
                    if (!room.isOurRoom)
                      CoachTarget(
                        id: .roomCode,
                        child: RoomCodeChip(
                          code: room.code,
                          onCopy: _copyCode,
                          fontSize: 12,
                          plain: true,
                        ),
                      ),
                    Tooltip(
                      message: _syncDotTooltip,
                      child: Row(
                        mainAxisSize: .min,
                        spacing: 8,
                        children: [
                          SyncDot(state: _syncDotState, size: 8),
                          if (wide)
                            AnimatedSwitcher(
                              duration: PTMotion.functional(context, PTMotion.state),
                              child: Text(
                                _syncDotLabel,
                                key: ValueKey(_syncDotState),
                                style: PTText.label.copyWith(
                                  letterSpacing: 11 * 0.12,
                                  color: _syncDotState == .reconnecting
                                      ? PTColors.danger
                                      : PTColors.fgDim,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (_mediaSharingIcon(size: 36) != null) _mediaSharingIcon(size: 36)!,
                  ],
                ),
              ),
            ],
          ),
        );

        final trailing = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0),
          child: Row(
            mainAxisSize: .min,
            spacing: 14,
            children: [
              if (_showClock)
                MouseRegion(
                  cursor: isHost ? SystemMouseCursors.click : MouseCursor.defer,
                  child: GestureDetector(
                    onTap: isHost && !_extending ? _extendRoom : null,
                    child: Tooltip(
                      message: isHost ? 'Extend room duration' : 'Time remaining',
                      child: PTPulse(
                        enabled:
                            _timeLeft > Duration.zero && _timeLeft <= const Duration(minutes: 1),
                        low: 0.35,
                        child: AnimatedDefaultTextStyle(
                          duration: PTMotion.functional(context, PTMotion.state),
                          style: PTText.label.copyWith(
                            fontSize: 12,
                            color: urgent ? PTColors.warning : PTColors.fgMute,
                          ),
                          child: Text(
                            spelled ? 'HOUSE LIGHTS IN $_houseLightsLabel' : _houseLightsLabel,
                            maxLines: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (invite && !room.isOurRoom)
                PTButton(
                  label: 'Invite',
                  variant: .secondary,
                  height: 36,
                  expand: false,
                  onPressed: _copyInvite,
                ),
              Row(
                mainAxisSize: .min,
                spacing: 12,
                children: [
                  _chatToggleButton(size: 36, glass: false),
                  // Desktop carries the button in the marquee bar instead.
                  if (!isDesktop) const BugReportButton(),
                  PTIconButton(
                    icon: BoothIcons.moreHoriz,
                    glass: false,
                    size: 36,
                    iconSize: 20,
                    tooltip: 'Room menu',
                    onPressed: _openOverflowMenu,
                  ),
                ],
              ),
            ],
          ),
        );

        if (isDesktop) {
          return CinemaMarqueeBar(
            height: 52,
            fullscreen: _fullscreen,
            child: Row(
              children: [
                Expanded(child: leading),
                trailing,
              ],
            ),
          );
        }

        return Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: const BoxDecoration(
            color: PTColors.canvas,
            border: Border(bottom: BorderSide(color: PTColors.aisle)),
          ),
          child: Row(
            children: [
              Expanded(child: leading),
              trailing,
            ],
          ),
        );
      },
    );
  }

  String get _syncDotTooltip => switch (_syncDotState) {
    .locked => 'In sync with the room',
    .catchingUp => 'Catching up',
    .reconnecting => 'Reconnecting…',
    .idle => 'Nothing playing together yet',
  };

  String get _syncDotLabel => switch (_syncDotState) {
    _ when _gateState == GateState.closed && _canonicalMedia.isSet => 'HOLDING THE CURTAIN',
    .locked when _driftLabel != null => 'IN SYNC · $_driftLabel',
    .locked => 'IN SYNC · ${_present.length} SEATS',
    .catchingUp => 'CATCHING UP',
    .reconnecting => 'RECONNECTING…',
    .idle when (_room?.isOurRoom ?? false) =>
      _present.length < 2 ? 'WAITING FOR ${_partnerFirstName.toUpperCase()}' : 'TOGETHER',
    .idle => _present.length < 2 ? 'SAVING SEATS' : 'HOUSE OPEN',
  };

  /// "±0.2s" - our distance from the authority at its last heartbeat. Null
  /// when unmeasured, and always for the authority (it is the reference), so
  /// the label falls back to the seat count.
  String? get _driftLabel {
    final drift = _sync?.measuredDrift.value;
    if (drift == null) return null;
    return '±${(drift.inMilliseconds / 1000).toStringAsFixed(1)}s';
  }

  /// "2H 55M", or "4:59" inside the last hour's final minutes.
  /// Our Room's other person, for the header. The roster knows them even while
  /// they are offline; "them" only while it has not loaded.
  String get _partnerFirstName {
    // What I call them: the pair knows my nickname for them, the roster does not.
    final label = PairService.instance.pair?.partner.displayName;
    final me = _sync?.userId;
    final other = _members.where((m) => m.userId != me).firstOrNull;
    final first = (label ?? other?.displayName ?? '').split(' ').first.trim();
    if (first.isEmpty) return 'THEM';
    return first.length > 12 ? first.substring(0, 12) : first;
  }

  /// Our Room does not run on a visible clock until the last half hour: a
  /// countdown on the couple's own room reads like a rental, and nothing is
  /// lost by saying it only when it matters.
  bool get _showClock => !(_room?.isOurRoom ?? false) || _timeLeft <= const Duration(minutes: 30);

  String get _houseLightsLabel {
    final h = _timeLeft.inHours;
    final m = _timeLeft.inMinutes.remainder(60);
    if (h > 0) return '${h}H ${m.toString().padLeft(2, '0')}M';
    if (m >= 10) return '${m}M';
    final s = _timeLeft.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// Touch tablets. Landscape reuses the desktop composition with touch input;
  /// portrait has height to spare, so chat and facecams sit *below* the video
  /// as real layout instead of covering it.
  Widget _tablet() {
    final size = MediaQuery.sizeOf(context);
    if (size.width > size.height) return _roomy(touch: true);
    // Near-square (an unfolded Fold, a Pixel Fold): picture over a deck.
    return size.height / size.width < kSquarishMaxAspect ? _squarish() : _portrait(roomy: true);
  }

  /// Near-square touch windows (board 54): the picture across the top at 16:9
  /// (never more than half the height), the deck under it. Same pieces as the
  /// tabletop's two halves, minus the fold.
  Widget _squarish() {
    final hasCams = _av != null && !_privacyHidden && _camsVisible;
    // Sized against the body's own height, not the window's: with the soft
    // keyboard up the body is what is left above it, and half of the whole
    // window left the deck a sliver.
    return LayoutBuilder(
      builder: (context, box) => Column(
        children: [
          ColoredBox(
            color: PTColors.screenBg,
            child: SafeArea(
              bottom: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: box.maxHeight * 0.5),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: _skipZones(child: _videoSurface()),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: RoomDeck(
                header: _portraitHeader(),
                transport: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Column(
                    mainAxisSize: .min,
                    children: [_reactionStrip(compact: true), _controlBar(compact: true)],
                  ),
                ),
                aside: [
                  _bannerStack(
                    spacing: 10,
                    inScroll: true,
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  ),
                  if (hasCams)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                      child: _facecamStrip(),
                    ),
                ],
                chat: _embeddedChat(padding: EdgeInsets.zero),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The desktop composition: full-bleed video, floating chrome, docked chat.
  /// [touch] (landscape tablets) swaps pointer affordances for touch ones: no
  /// hover/cursor hiding, and ±10 s double-tap skip zones. Fullscreen needs no
  /// branch here - its button is already absent whenever `isDesktop` is false.
  Widget _roomy({required bool touch}) {
    return RoomRoomyLayout(
      touch: touch,
      fullscreen: _fullscreen,
      videoSurface: touch
          ? _skipZones(onTap: _toggleControlsVisible, child: _videoSurface())
          // Single click toggles instantly: deliberately no onDoubleTap (D1).
          : GestureDetector(
              behavior: .opaque,
              onTap: _toggleControlsVisible,
              child: _videoSurface(),
            ),
      topActions: _topActions(),
      bannerStack: _bannerStack(spacing: 12),
      reactionStrip: _reactionStrip(),
      controlBar: _controlBar(),
      showControlsButton: _showControlsButton(),
      chatOpen: _chatOpen,
      chatMotion: _chatMotion,
      controlsVisible: _controlsVisible,
      cursorVisible: _cursorVisible,
      reactOpen: _reactOpen,
      hasAv: _av != null && !_privacyHidden,
      onMouseMove: _onMouseMove,
      overlayControls: _overlayControls,
      facecamRail: (_av != null && !_privacyHidden && _camsVisible)
          ? FacecamRail(
              av: _av!,
              present: _visiblePresent,
              premiumMembers: _premiumMembers,
              memberFrames: _memberFrames,
              selfId: _sync?.userId ?? '',
              layout: .railLeft,
              trialEndsAt: _trialChipEndsAt,
              now: () => RoomService.instance.serverNow,
              showTrialEnded: _videoTrialEndedNote,
              onKeepFaces: _offersKeepFaces ? _keepFacesOn : null,
              showNames: _controlsVisible,
              onHide: () => setState(() => _camsVisible = false),
            )
          : null,
      showCamsPill: (_av != null && !_privacyHidden && !_camsVisible)
          ? PTActionPill(
              label: 'Show cams',
              icon: BoothIcons.chevronRight,
              onTap: () => setState(() => _camsVisible = true),
            )
          : null,
      chatRevealed: _sync != null ? _chatRevealed(offscreen: 380, panel: _chatPanel()) : null,
      chatDisplaced: _overlayChat.isNotEmpty ? _chatDisplaced(_chatOverlay()) : null,
    );
  }

  /// The Mobile room board's header: leave on the left, the room's name over
  /// its sync line in the middle, the menu on the right. The code lives in
  /// the menu's "Copy invite"; the countdown rides the sync line.
  Widget _portraitHeader({EdgeInsets padding = const EdgeInsets.fromLTRB(8, 6, 8, 8)}) {
    final room = _room!;
    final isHost = _sync?.isHost ?? false;
    final urgent = _timeLeft > Duration.zero && _timeLeft <= const Duration(minutes: 5);
    return Padding(
      padding: padding,
      child: Row(
        spacing: 4,
        children: [
          PTIconButton(
            icon: BoothIcons.chevronLeft,
            glass: false,
            iconSize: 22,
            tooltip: 'Leave room',
            onPressed: _leaveRoom,
          ),
          Expanded(
            child: Column(
              spacing: 3,
              children: [
                PTMarquee(
                  room.name,
                  textAlign: .center,
                  style: PTText.panelHeading.copyWith(fontSize: 17),
                ),
                GestureDetector(
                  onTap: isHost && !_extending ? _extendRoom : null,
                  child: Row(
                    mainAxisSize: .min,
                    spacing: 6,
                    children: [
                      SyncDot(state: _syncDotState, size: 7),
                      Flexible(
                        child: AnimatedDefaultTextStyle(
                          duration: PTMotion.functional(context, PTMotion.state),
                          style: PTText.label.copyWith(
                            fontSize: 10,
                            letterSpacing: 10 * 0.12,
                            color: urgent ? PTColors.warning : PTColors.fgDim,
                          ),
                          child: Text(
                            _showClock ? '$_syncDotLabel · $_houseLightsLabel' : _syncDotLabel,
                            maxLines: 1,
                            overflow: .ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Transient sharing states (uploading, failed) keep a label.
                if (_mediaSharingIcon() == null) ?_mediaSharingPill(compact: true),
              ],
            ),
          ),
          const BugReportButton(),
          PTIconButton(
            icon: BoothIcons.moreHoriz,
            glass: false,
            iconSize: 22,
            tooltip: 'Room menu',
            onPressed: _openOverflowMenu,
          ),
        ],
      ),
    );
  }

  /// Phone portrait, and (with [roomy]) tablet portrait: video pinned top,
  /// everything else stacked below it as real layout.
  Widget _portrait({bool roomy = false}) {
    // The inline emoji picker takes the keyboard's place, so it counts: the
    // header would otherwise pop back for the frames between the two.
    // Reading the MediaQuery inset is what rebuilds this on every frame of the
    // keyboard's slide; the memory reads the same value from the View.
    final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0 || _chatPickerUp;
    final liveKeyboard = _keyboardMemory.observe(View.of(context));
    final gutter = roomy ? 24.0 : (MediaQuery.sizeOf(context).width < 380 ? 10.0 : 14.0);
    // With the keys up the transport floats over the picture instead of taking
    // its own row, so the picture keeps that height. The same widget tree either
    // way (a Stack around the picture), so nothing remounts when the keys rise.
    final floatBar = keyboardUp;
    _kbBarEdge(floatBar);
    return RoomMobilePortraitLayout(
      roomy: roomy,
      keyboardUp: keyboardUp,
      chatFloorExtra: _chatPickerUp ? _keyboardMemory.pickerShown(liveKeyboard) : 0,
      chatFloorReveal: _keyboardMemory.pickerReveal,
      header: _portraitHeader(
        padding: roomy
            ? const EdgeInsets.fromLTRB(16, 10, 16, 10)
            : const EdgeInsets.fromLTRB(6, 4, 6, 8),
      ),
      // A hidden transport comes back with a tap on the picture; with it showing,
      // the tap is left alone so it closes the keyboard like any empty space.
      videoSurface: _skipZones(
        onTap: floatBar && !_kbBarVisible ? _revealKbBar : null,
        child: _videoSurface(),
      ),
      facecamStrip: (_av != null && !_privacyHidden && _camsVisible) ? _facecamStrip() : null,
      reactionStrip: _reactionStrip(compact: !roomy),
      controlBar: _kbBarShell(_controlBar(compact: !roomy, docked: true), floating: floatBar),
      bannerStack: _bannerStack(
        spacing: 10,
        inScroll: true,
        padding: EdgeInsets.fromLTRB(gutter, 10, gutter, 0),
      ),
      embeddedChat: _embeddedChat(padding: EdgeInsets.zero),
    );
  }

  /// [children] stacked above [chat], for the in-flow layouts (portrait, fold
  /// panes). The chat takes whatever height is left, but never less than a
  /// readable floor: when the window is too short for that (320x568 at 2x, a
  /// keyboard, three banners) it is [children] that scroll, in the height the
  /// floor leaves them. The chat stays outside that scroll view, so its input
  /// and send button are always on screen rather than scrolled past.
  Widget _aboveChat({required List<Widget> children, required Widget chat}) {
    return RoomAboveChat(chat: chat, children: children);
  }

  Widget _landscape() {
    return RoomMobileLandscapeLayout(
      videoSurface: _skipZones(onTap: _toggleControlsVisible, child: _videoSurface()),
      topActionsBuilder: (keyboardMode) => _topActions(compact: true, chatToggle: !keyboardMode),
      bannerStack: _bannerStack(spacing: 8),
      reactionStrip: _reactionStrip(compact: true),
      controlBar: _controlBar(compact: true),
      barCaps: _barWidget(_positionNotifier.value, compact: true).caps,
      showControlsButton: _showControlsButton(),
      controlsVisible: _controlsVisible,
      cursorVisible: _cursorVisible,
      chatOpen: _chatOpen,
      reactOpen: _reactOpen,
      onMouseMove: _onMouseMove,
      overlayControls: _overlayControls,
      facecamRailBuilder: (_av != null && !_privacyHidden && _camsVisible)
          // Not displaced by the chat: it sits beside it (the layout moves its
          // right edge to the chat's left, 12 px clear).
          ? (plan) => FacecamRail(
              av: _av!,
              present: _visiblePresent,
              premiumMembers: _premiumMembers,
              memberFrames: _memberFrames,
              selfId: _sync?.userId ?? '',
              layout: .miniStackRight,
              trialEndsAt: _trialChipEndsAt,
              now: () => RoomService.instance.serverNow,
              showTrialEnded: _videoTrialEndedNote,
              onKeepFaces: _offersKeepFaces ? _keepFacesOn : null,
              maxTiles: math.max(1, plan.tiles),
              miniLarge: plan.large,
              showNames: _controlsVisible,
            )
          : null,
      chatDisplacedOverlay: _overlayChat.isNotEmpty ? _chatDisplaced(_chatOverlay()) : null,
      chatRevealedBuilder: _sync != null
          ? (chatWidth) => _chatRevealed(offscreen: chatWidth + 40, panel: _chatPanel())
          : null,
    );
  }

  /// Foldables with a hinge or a half-opened fold. [PTFoldAxis.vertical]
  /// (book): video left, chat right. [PTFoldAxis.horizontal] (tabletop): video
  /// on the top half, transport + reactions + chat on the bottom half.
  Widget _folded(PTFold fold) {
    final hasCams = _av != null && !_privacyHidden && _camsVisible;
    // A tabletop whose lower half the soft keyboard has taken: the room keeps
    // the same tree (a remount would drop the composer's focus and the
    // keyboard with it) and only moves geometry - the lower pane's rect lifts
    // above the keys over the picture's bottom, and the deck's control column
    // steps aside for the chat, as phone landscape's control bar does.
    final keyboardOverLower =
        fold.axis == .horizontal &&
        MediaQuery.viewInsetsOf(context).bottom > 0 &&
        MediaQuery.sizeOf(context).height -
                MediaQuery.viewInsetsOf(context).bottom -
                fold.bounds.bottom <
            kMinLowerPaneHeight;
    if (fold.axis == .vertical) {
      return _foldSplit(
        fold,
        Stack(
          children: [
            Positioned.fill(
              child: _skipZones(onTap: _toggleControlsVisible, child: _videoSurface()),
            ),
            SafeArea(
              right: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _overlayControls(fromTop: true, _topActions(compact: true, chatToggle: false)),
                    const Spacer(),
                    _overlayControls(
                      Column(
                        mainAxisSize: .min,
                        children: [_reactionStrip(compact: true), _controlBar(compact: true)],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: SafeArea(right: false, child: _showControlsButton()),
            ),
          ],
        ),
        SafeArea(
          left: false,
          child: _aboveChat(
            chat: _embeddedChat(),
            children: [
              _bannerStack(
                spacing: 10,
                inScroll: true,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              ),
              if (hasCams)
                Padding(padding: const EdgeInsets.fromLTRB(14, 12, 14, 0), child: _facecamStrip()),
            ],
          ),
        ),
      );
    }
    return _foldSplit(
      fold,
      liftSecond: keyboardOverLower,
      SafeArea(
        bottom: false,
        child: ColoredBox(
          color: PTColors.screenBg,
          child: Center(
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: _skipZones(child: _videoSurface()),
            ),
          ),
        ),
      ),
      Builder(
        builder: (context) {
          final aside = [
            _bannerStack(
              spacing: 10,
              inScroll: true,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            ),
            if (hasCams)
              Padding(padding: const EdgeInsets.fromLTRB(14, 10, 14, 0), child: _facecamStrip()),
          ];
          final transport = Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              mainAxisSize: .min,
              children: [_reactionStrip(compact: true), _controlBar(compact: true)],
            ),
          );
          return SafeArea(
            top: false,
            // A wide lower half is two columns (board 54); a narrow one, a
            // phone-sized stack.
            child: deckFits(MediaQuery.sizeOf(context))
                ? RoomDeck(
                    controlsAside: keyboardOverLower,
                    header: _portraitHeader(),
                    transport: transport,
                    aside: aside,
                    chat: _embeddedChat(padding: EdgeInsets.zero),
                  )
                : _aboveChat(
                    chat: _embeddedChat(),
                    children: [_portraitHeader(), transport, ...aside],
                  ),
          );
        },
      ),
    );
  }

  /// Splits the window at the hinge: [first] before it, [second] after it,
  /// and the hinge itself left empty so nothing interactive straddles it.
  /// The hinge rect is in window coordinates, and the room fills the window.
  Widget _foldSplit(PTFold fold, Widget first, Widget second, {bool liftSecond = false}) {
    return RoomFoldSplit(fold: fold, first: first, second: second, liftSecond: liftSecond);
  }
}
