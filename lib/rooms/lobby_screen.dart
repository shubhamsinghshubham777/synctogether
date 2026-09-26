import 'dart:async';
import '../ui/booth_icons.g.dart';
import 'dart:io';

import 'package:fast_file_picker/fast_file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as p;
import 'package:synctogether/analytics.dart';
import 'package:synctogether/app_router.dart';
import 'package:synctogether/app_version.dart';
import 'package:synctogether/auth/auth_service.dart';
import 'package:synctogether/diagnostics.dart';
import 'package:synctogether/env.dart';
import 'package:synctogether/profile/entitlement_service.dart';
import 'package:synctogether/profile/media_quota_dialog.dart';
import 'package:synctogether/profile/profile_models.dart';
import 'package:synctogether/profile/profile_service.dart';
import 'package:synctogether/rooms/local_media_store.dart';
import 'package:synctogether/rooms/media_sharing_service.dart';
import 'package:synctogether/rooms/room_models.dart';
import 'package:synctogether/rewards/rewards_logic.dart';
import 'package:synctogether/rewards/rewards_service.dart';
import 'package:synctogether/rewards/widgets/streak_chip.dart';
import 'package:synctogether/rooms/room_service.dart';
import 'package:synctogether/rooms/widgets/ended_room_dialog.dart';
import 'package:synctogether/rooms/widgets/extend_room_dialog.dart';
import 'package:synctogether/rooms/widgets/lobby_header.dart';
import 'package:synctogether/rooms/widgets/my_rooms_section.dart';
import 'package:synctogether/updates/update_service.dart';
import 'package:synctogether/ui/banners.dart';
import 'package:synctogether/ui/booth.dart';
import 'package:synctogether/ui/loader.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/identity.dart';
import 'package:synctogether/ui/inputs.dart';
import 'package:synctogether/ui/logo.dart';
import 'package:synctogether/ui/pt_motion.dart';
import 'package:synctogether/ui/pt_theme.dart';
import 'package:synctogether/ui/responsive.dart';
import 'package:synctogether/ui/scroll_fade.dart';

/// Width below which the desktop lobby stacks into a single column.
const double kLobbySplitWidth = 960;

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  final _nameController = TextEditingController();
  final _codeKey = GlobalKey<PTCodeInputState>();
  int _durationMinutes = 150;
  String _code = '';
  bool _creating = false;
  bool _joining = false;
  int _codeShake = 0;
  _PhonePanel _phonePanel = _PhonePanel.none;
  String? _busyRoomId;
  bool _clearingEndedRooms = false;
  Timer? _myRoomsPollTimer;

  File? _stagedFile;
  StagedUploadSession? _stagedSession;
  StagedUploadSession? _activeStagingSession;
  CancellationToken? _stagingCancelToken;
  bool _stagingUpload = false;
  UploadProgress? _stagingProgress;
  final MediaSharingService _mediaSharingService = MediaSharingService();

  /// The entrance choreography is a *first impression*, not a transition.
  /// Static so coming back from a room is instant familiarity rather than a
  /// re-performance of the same arrival.
  static bool _introPlayed = false;
  late final bool _playIntro = !_introPlayed;

  @override
  void initState() {
    super.initState();
    _introPlayed = true;
    unawaited(
      EntitlementService.instance.load().then((_) {
        if (!mounted || _durationMinutes <= _durationCap) return;
        setState(() => _durationMinutes = _durationCap);
      }),
    );
    unawaited(RewardsService.instance.load());
    unawaited(_loadMyRooms());
    _myRoomsPollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && RoomService.instance.currentRoom == null) {
        unawaited(_loadMyRooms());
      }
    });
    RoomService.instance.addListener(_onRoomServiceChanged);
    if (ProfileService.instance.profile == null) {
      // Consume the parked invite even if the profile fetch fails - the join
      // itself doesn't need the profile.
      ProfileService.instance
          .load()
          .catchError((Object e, StackTrace s) {
            reportNonFatal(e, s, during: 'loading the profile for the lobby');
            return null;
          })
          .whenComplete(_consumePendingJoin);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _consumePendingJoin());
    }
  }

  final _roomExit = RoomExitEdge(RoomService.instance.currentRoom != null);

  void _onRoomServiceChanged() {
    if (_roomExit.observe(inRoom: RoomService.instance.currentRoom != null)) {
      if (mounted && (_stagedSession != null || _stagedFile != null)) {
        setState(_clearStagedUploadState);
      }
      unawaited(_loadMyRooms());
      if (AuthService.instance.isSignedIn) {
        unawaited(ProfileService.instance.load());
        unawaited(EntitlementService.instance.refresh());
      }
    }
  }

  @override
  void dispose() {
    _myRoomsPollTimer?.cancel();
    RoomService.instance.removeListener(_onRoomServiceChanged);
    _nameController.dispose();
    super.dispose();
  }

  /// Invite deep link received before sign-in lands here after login.
  Future<void> _consumePendingJoin() async {
    final code = RoomService.instance.pendingJoinCode;
    if (code == null || !mounted) return;
    RoomService.instance.pendingJoinCode = null;
    trace('consuming a parked invite', category: 'deeplink');
    await _join(code, via: .deeplink);
  }

  int get _durationCap => EntitlementService.instance.limitsOrFallback.maxSessionMinutes;

  String get _durationCapLabel =>
      _durationCap >= 120 ? '${_durationCap ~/ 60} hours' : '$_durationCap min';

  String get _durationLabel => _minutesLabel(_durationMinutes);

  static String _minutesLabel(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  Future<void> _pickStagedMedia() async {
    final profile = ProfileService.instance.profile;
    final isGuest = profile?.isGuest ?? true;
    if (isGuest) {
      if (mounted) {
        showMediaQuotaDialog(context, quotaContext: const MediaQuotaContext(reason: .guestBlocked));
      }
      return;
    }

    const videoTypeGroup = XTypeGroup(label: 'Videos', extensions: ['mp4', 'mkv']);
    final FastFilePickerPath? response;
    try {
      response = await FastFilePicker.pickFile(acceptedTypeGroups: [videoTypeGroup]);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'picking staged video in lobby');
      return;
    }
    final path = response?.path;
    if (path == null) return;
    final file = File(path);
    if (!file.existsSync()) return;

    final fileSize = file.lengthSync();
    final fileName = file.uri.pathSegments.isNotEmpty ? file.uri.pathSegments.last : null;
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
            fileName: fileName,
            fileSize: fileSize,
            maxBytes: maxFileBytes,
          ),
        );
      }
      return;
    }

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
              fileName: fileName,
              fileSize: fileSize,
              remainingBytes: remaining,
              maxBytes: weeklyLimit,
            ),
          );
        }
        return;
      }
    }

    final cancelToken = CancellationToken();
    setState(() {
      _stagedFile = file;
      _stagingUpload = true;
      _stagingProgress = null;
      _stagedSession = null;
      _activeStagingSession = null;
      _stagingCancelToken = cancelToken;
    });

    try {
      final session = await _mediaSharingService.uploadStagedFile(
        file: file,
        cancelToken: cancelToken,
        onSessionCreated: (session) {
          if (mounted && _stagingCancelToken == cancelToken) {
            setState(() => _activeStagingSession = session);
          }
        },
        onProgress: (progress) {
          if (mounted && _stagingCancelToken == cancelToken) {
            setState(() {
              _stagingProgress = progress;
            });
          }
        },
      );
      if (mounted && _stagingCancelToken == cancelToken) {
        setState(() {
          _stagedSession = session;
          _stagingUpload = false;
        });
        unawaited(ProfileService.instance.load());
      }
    } catch (e, s) {
      if (cancelToken.isCancelled) {
        // User explicitly cancelled, nothing to snack
        return;
      }
      reportNonFatal(e, s, during: 'staging media upload in lobby');
      if (mounted && _stagingCancelToken == cancelToken) {
        setState(() {
          _stagingUpload = false;
          _stagedFile = null;
          _stagedSession = null;
          _activeStagingSession = null;
          _stagingProgress = null;
        });
        final error = MediaSharingException.fromError(e);
        _snack(error.message);
        if (error.code == 'quota_exceeded' && mounted) {
          showMediaQuotaDialog(
            context,
            quotaContext: MediaQuotaContext(
              reason: .weeklyQuotaExceeded,
              fileName: fileName,
              fileSize: fileSize,
            ),
          );
        }
      }
    }
  }

  void _clearStagedUploadState() {
    _stagedFile = null;
    _stagedSession = null;
    _activeStagingSession = null;
    _stagingUpload = false;
    _stagingProgress = null;
    _stagingCancelToken = null;
  }

  Future<void> _cancelStagedMedia() async {
    _stagingCancelToken?.cancel();
    final active = _activeStagingSession;
    final ready = _stagedSession;

    setState(_clearStagedUploadState);

    if (active != null) {
      unawaited(
        _mediaSharingService.abortStagedUpload(
          stagedId: active.stagedId,
          uploadId: active.uploadId,
          r2Key: active.r2Key,
        ),
      );
    } else if (ready != null) {
      unawaited(
        _mediaSharingService.abortStagedUpload(
          stagedId: ready.stagedId,
          uploadId: ready.uploadId,
          r2Key: ready.r2Key,
        ),
      );
    }
  }

  Future<void> _create({
    bool isRetry = false,
    StagedUploadSession? retrySession,
    File? retryFile,
  }) async {
    if (_stagingUpload) return;

    final session = retrySession ?? _stagedSession;
    final file = retryFile ?? _stagedFile;

    setState(() {
      _creating = true;
      _clearStagedUploadState();
    });
    var roomEndedForRetry = false;
    try {
      final room = await RoomService.instance.createRoom(
        name: _nameController.text,
        durationMinutes: _durationMinutes,
        stagedId: session?.stagedId,
      );
      if (file != null) {
        await LocalMediaStore.instance.record(
          roomId: room.id,
          name: p.basename(file.path),
          path: file.path,
        );
      }
      if (mounted) {
        final path = file == null ? '${roomPath(room.id)}?dialog=media' : roomPath(room.id);
        context.go(path);
      }
    } catch (e, s) {
      final code = RoomErrorCode.fromError(e);
      if (code == .unknown) reportNonFatal(e, s, during: 'creating a room');
      if (!mounted) return;
      if (code == .guestRoomLimit) {
        roomEndedForRetry = await _showGuestLimitDialog() && !isRetry;
      } else if (code == .roomLimitReached) {
        await _showRoomLimitDialog();
      } else if (code == .notAuthenticated) {
        _snack(code.message);
        await AuthService.instance.signOut();
      } else {
        _snack(code.message);
      }
      if (!roomEndedForRetry && mounted) {
        setState(() {
          _stagedSession = session;
          _stagedFile = file;
        });
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
    if (roomEndedForRetry && mounted) {
      await _create(isRetry: true, retrySession: session, retryFile: file);
    }
  }

  Future<void> _join(String code, {RoomJoinSource via = RoomJoinSource.code}) async {
    if (code.length != PTCodeInput.length) {
      _snack('Enter the 6-character room code.');
      setState(() => _codeShake++);
      return;
    }
    setState(() => _joining = true);
    try {
      final room = await RoomService.instance.joinRoom(code, via: via);
      if (mounted) context.go(roomPath(room.id));
    } catch (e, s) {
      final failure = RoomErrorCode.fromError(e);
      if (failure == .unknown) reportNonFatal(e, s, during: 'joining a room by code');
      if (mounted) {
        _snack(failure.message);
        _codeKey.currentState?.clear();
        setState(() => _codeShake++);
      }
      if (failure == .notAuthenticated) {
        await AuthService.instance.signOut();
      }
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _loadMyRooms() async {
    try {
      final rooms = await RoomService.instance.loadMyRooms();
      await LocalMediaStore.instance.prune(keepRoomIds: {for (final r in rooms) r.room.id});
      if (AuthService.instance.isSignedIn) {
        unawaited(ProfileService.instance.load());
        unawaited(EntitlementService.instance.refresh());
      }
    } catch (e, s) {
      final failure = RoomErrorCode.fromError(e);
      if (failure == .notAuthenticated) {
        await AuthService.instance.signOut();
      } else {
        reportNonFatal(e, s, during: 'loading the lobby room list');
      }
    }
  }

  Future<void> _openMyRoom(MyRoom entry) async {
    if (!entry.isLive) {
      await showGlassDialog<void>(
        context: context,
        width: 440,
        builder: (_) => EndedRoomDialog(
          room: entry.room,
          isOwner: entry.isOwner,
          onStartFresh: () {
            _nameController.text = entry.room.name;
            _create();
          },
          onUpgrade: () {
            Analytics.instance.track('upgrade_cta_clicked', {
              'surface': 'ended_room',
              'action': 'subscribe',
            });
            context.go('/lobby/subscribe?source=ended_room');
          },
          onDelete: () => _deleteMyRoom(entry),
        ),
      );
      return;
    }

    if (entry.isMember) {
      context.go(roomPath(entry.room.id));
    } else {
      await _join(entry.room.code, via: .code);
    }
  }

  Future<void> _deleteMyRoom(MyRoom entry) async {
    final confirmed = await showGlassDialog<bool>(
      context: context,
      width: 420,
      builder: (_) => DeleteRoomDialog(roomName: entry.room.name, isLive: entry.isLive),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busyRoomId = entry.room.id);
    try {
      await RoomService.instance.deleteRoom(entry.room.id);
      await LocalMediaStore.instance.forget(entry.room.id);
      if (mounted) _snack('Room deleted.', kind: .success);
    } catch (e, s) {
      final failure = RoomErrorCode.fromError(e);
      if (failure == .unknown) reportNonFatal(e, s, during: 'deleting a room from the lobby');
      if (mounted) _snack(failure.message);
    } finally {
      if (mounted) setState(() => _busyRoomId = null);
    }
  }

  Future<void> _showRoomLimitDialog() async {
    Analytics.instance.track('upgrade_cta_shown', {'surface': 'room_limit'});
    await showGlassDialog<void>(
      context: context,
      width: 430,
      builder: (_) => PremiumTeaseDialog(
        headline: "That's all your rooms",
        body:
            "You're holding as many rooms as your account allows. Delete one you're done "
            'with, or upgrade to Premium for more.',
        perks: const [
          'Room for a lot more of them at once',
          'Rooms that stay put until you delete them',
          'Up to 16 watchers, with video facecams',
        ],
        onUpgrade: () {
          Analytics.instance.track('upgrade_cta_clicked', {
            'surface': 'room_limit',
            'action': 'subscribe',
          });
          context.go('/lobby/subscribe?source=room_limit');
        },
      ),
    );
  }

  Future<void> _clearEndedRooms(List<MyRoom> endedRooms) async {
    if (endedRooms.isEmpty || _clearingEndedRooms) return;
    final hasPersistent = RoomService.instance.myRooms.any((r) => r.room.persistent);
    final confirmed = await showGlassDialog<bool>(
      context: context,
      width: 420,
      builder: (_) =>
          ClearEndedRoomsDialog(count: endedRooms.length, hasPersistentRooms: hasPersistent),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _clearingEndedRooms = true);
    var succeeded = 0;
    var failed = 0;

    try {
      for (final entry in endedRooms) {
        try {
          await RoomService.instance.deleteRoom(entry.room.id);
          await LocalMediaStore.instance.forget(entry.room.id);
          succeeded++;
        } catch (e, s) {
          failed++;
          final failure = RoomErrorCode.fromError(e);
          if (failure == .unknown) {
            reportNonFatal(e, s, during: 'clearing ended room ${entry.room.id}');
          }
        }
      }

      if (mounted) {
        if (failed == 0) {
          _snack('Cleared $succeeded ended ${succeeded == 1 ? 'room' : 'rooms'}.', kind: .success);
        } else if (succeeded > 0) {
          _snack(
            'Cleared $succeeded ended ${succeeded == 1 ? 'room' : 'rooms'} ($failed failed).',
            kind: .info,
          );
        } else {
          _snack('Could not clear ended rooms. Please try again.');
        }
      }
    } finally {
      if (mounted) setState(() => _clearingEndedRooms = false);
      unawaited(_loadMyRooms());
    }
  }

  Widget _myRoomsSection({bool compact = false}) {
    return MyRoomsSection(
      rooms: RoomService.instance.myRooms,
      serverNow: RoomService.instance.serverNow,
      busyRoomId: _busyRoomId,
      clearingEnded: _clearingEndedRooms,
      compact: compact,
      framed: false,
      onOpen: _openMyRoom,
      onDelete: _deleteMyRoom,
      onClearEnded: _clearEndedRooms,
    );
  }

  void _snack(String message, {PTSnackKind kind = PTSnackKind.error}) =>
      showPTSnack(context, message, kind: kind);

  Future<bool> _endBlockingRoom(Room live) async {
    try {
      await RoomService.instance.endRoom(live.id);
      if (mounted) _snack('House lights up. Your old room has ended.', kind: .success);
      return true;
    } catch (e, s) {
      final failure = RoomErrorCode.fromError(e);
      if (failure == .unknown) reportNonFatal(e, s, during: 'ending room ${live.id}');
      if (mounted) _snack(failure.message);
      return false;
    } finally {
      unawaited(_loadMyRooms());
    }
  }

  Future<bool> _showGuestLimitDialog() async {
    final live = await RoomService.instance.fetchLiveHostedRoom();
    trace(
      'guest room limit hit',
      category: 'room',
      data: {'blocking_room_id': live?.id, 'resolved': live != null},
    );
    if (!mounted) return false;
    if (live == null) {
      reportNonFatal(
        StateError('guest_room_limit with no readable blocking room'),
        StackTrace.current,
        during: 'resolving the room blocking a guest create',
      );
      _snack('Your other room is still running, but we could not load it. Try again in a moment.');
      return false;
    }
    Future<bool>? ending;
    await showGlassDialog(
      context: context,
      width: 400,
      builder: (dialogContext) => _GuestLimitDialogBody(
        roomName: live.name,
        onEnd: () {
          Navigator.of(dialogContext).pop();
          ending = _endBlockingRoom(live);
        },
        onRejoin: () {
          Navigator.of(dialogContext).pop();
          unawaited(_join(live.code, via: .code));
        },
      ),
    );
    return await ending ?? false;
  }

  @override
  Widget build(BuildContext context) {
    // Anything reading the profile must do so *inside* this builder - the
    // enclosing build() doesn't re-run when the profile lands, so a value
    // captured out here stays stale until an unrelated setState.
    return Scaffold(
      body: AmbientBackground(
        child: ListenableBuilder(
          listenable: Listenable.merge([
            ProfileService.instance,
            UpdateService.instance,
            RoomService.instance,
            EntitlementService.instance,
            RewardsService.instance,
          ]),
          builder: (context, _) => PTResponsive(
            desktop: (_) => _desktop(),
            portrait: (_) => _portrait(),
            landscape: (_) => _landscape(),
          ),
        ),
      ),
    );
  }

  /// The lobby's one-row header: wordmark on the left, actions right-aligned.
  ///
  /// It never wraps. [FirstFit] tries progressively tighter action sets and
  /// keeps the first that fits the measured width - full pills, then compact
  /// chips, then the avatar's account menu absorbing logout, quota, premium
  /// and finally the streak - so a phone shows the wordmark, a chip or two and
  /// the avatar, and a narrow desktop window never drops a button to a second
  /// line. Touch layouts start at the account-menu level: phones have never had
  /// a bare logout button in the header.
  Widget _header({required bool compact}) {
    final touch = compact;
    final levels = touch ? const [2, 3, 4] : const [0, 1, 2, 3, 4];
    // The wordmark is not a flex child: two flex children would split the row
    // 50/50 and starve the actions of the wordmark's unused half. It keeps its
    // natural width, only scaling down past 60% of the row (320 at 2x text).
    return LayoutBuilder(
      builder: (context, box) => Row(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: box.maxWidth * 0.6),
            child: FittedBox(
              fit: .scaleDown,
              alignment: .centerLeft,
              child: _Wordmark(compact: compact),
            ),
          ),
          SizedBox(width: compact ? 12 : 24),
          Expanded(
            child: FirstFit(
              children: [
                for (final level in levels)
                  Row(
                    mainAxisSize: .min,
                    mainAxisAlignment: .end,
                    children: [_actions(level, avatarSize: _glyph(compact ? 36 : 42))],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// One candidate action set for [_header]. Levels, widest first:
  /// 0 full pills + profile pill + logout; 1 compact chips + avatar + logout;
  /// 2 compact chips + crown-only premium + account menu (logout moves in);
  /// 3 streak + account menu (quota, premium move in); 4 account menu alone.
  Widget _actions(int level, {required double avatarSize}) {
    final compact = level >= 1;
    return Row(
      mainAxisSize: .min,
      spacing: compact ? 8 : 12,
      children: [
        if (_showStreakChip && level <= 3) _streakChip(compact: compact),
        if (_showQuotaChip && level <= 2) _mediaQuotaChip(compact: compact),
        if (_showPremiumChip && level <= 2) _premiumChip(iconOnly: level == 2),
        if (level == 0)
          _profilePill()
        else if (level == 1)
          _avatarButton(size: avatarSize)
        else
          _avatarButton(size: avatarSize, menuLevel: level),
        if (level <= 1)
          PTIconButton(
            icon: BoothIcons.logout,
            iconSize: _glyph(20),
            size: avatarSize,
            tooltip: 'Log out',
            onPressed: AuthService.instance.signOut,
          ),
      ],
    );
  }

  /// Icon and avatar sizes that grow with the text, capped: at 2x text a 16px
  /// glyph beside 26px type reads as a stray dot, but doubling every avatar
  /// would crowd the header just as much.
  double _glyph(double size) =>
      MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.6).scale(size);

  Future<void> _openAccountMenu(BuildContext anchorContext, int level) {
    final box = anchorContext.findRenderObject()! as RenderBox;
    final anchor = box.localToGlobal(Offset.zero) & box.size;
    final profile = ProfileService.instance.profile;
    final entitlement = EntitlementService.instance;
    final guest = profile?.isGuest ?? true;
    final streak = RewardsService.instance.state.streak;
    return showLobbyAccountMenu(
      context: context,
      anchor: anchor,
      header: Row(
        spacing: 12,
        children: [
          PTAvatar(
            userId: profile?.id ?? '',
            displayName: profile?.displayName ?? '?',
            avatarUrl: profile?.avatarUrl,
            size: 40,
            premium: entitlement.isPremium,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              mainAxisSize: .min,
              spacing: 2,
              children: [
                Text(
                  profile?.displayName ?? '…',
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: PTText.body.copyWith(fontSize: 15, fontWeight: .w600),
                ),
                Text(
                  guest
                      ? 'Guest'
                      : entitlement.isPremium
                      ? 'Patron seat'
                      : 'Free seat',
                  style: PTText.caption.copyWith(
                    color: entitlement.isPremium ? PTColors.premium : PTColors.white(0.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      items: [
        if (_showStreakChip && level >= 4)
          LobbyMenuItem(
            icon: BoothIcons.fire,
            color: guest || streak.current == 0 ? null : PTColors.streak,
            label: guest
                ? 'Sign in for streaks'
                : streak.current > 0
                ? 'Streak'
                : 'Start a streak',
            detail: !guest && streak.current > 0 ? '${streak.current} days' : null,
            onTap: () => context.go('/lobby/leaderboard'),
          ),
        if (_showQuotaChip && level >= 3)
          LobbyMenuItem(
            icon: entitlement.isPremium ? BoothIcons.crown : Symbols.cloud_queue_rounded,
            label: 'Upload quota',
            detail: _quotaLabel(compact: true),
            color: entitlement.isPremium ? PTColors.textAccent : null,
            onTap: () => showMediaQuotaDialog(context),
          ),
        if (_showPremiumChip && level >= 3)
          LobbyMenuItem(
            icon: BoothIcons.crown,
            label: 'Get a Patron seat',
            color: PTColors.textAccent,
            onTap: () => context.go('/lobby/subscribe?source=lobby_chip'),
          ),
      ],
      footer: [
        LobbyMenuItem(
          icon: BoothIcons.person,
          label: 'Profile & settings',
          onTap: () => context.go('/lobby/profile'),
        ),
        const LobbyMenuItem(
          icon: BoothIcons.logout,
          label: 'Log out',
          danger: true,
          onTap: _signOut,
        ),
      ],
    );
  }

  static void _signOut() => AuthService.instance.signOut();

  /// Desktop, and tablets through the `tablet → desktop` fallback. The Booth
  /// Light lobby: the header across the top, then two columns split by a
  /// hairline - what you can *do* on the left (open a room, take a seat), what
  /// you already *have* on the right (your tickets). Below [kLobbySplitWidth]
  /// the columns would starve each other, so it stacks into one column.
  Widget _desktop() {
    final width = MediaQuery.sizeOf(context).width;
    if (width < kLobbySplitWidth) return _stacked();
    final left = (width * 0.42).clamp(420.0, 560.0);
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 20, 40, 20),
            child: _header(compact: false),
          ),
          const Divider(height: 1, color: PTColors.aisle),
          Expanded(
            child: Row(
              crossAxisAlignment: .stretch,
              children: [
                SizedBox(
                  width: left,
                  child: ScrollFadeEdge(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(56, 56, 44, 48),
                      child: _doColumn(headlineSize: width > 1280 ? 72 : 60),
                    ),
                  ),
                ),
                const VerticalDivider(width: 1, color: PTColors.aisle),
                Expanded(
                  child: ScrollFadeEdge(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(44, 48, 56, 48),
                      child: _haveColumn(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// One centred column: narrow desktop windows and portrait tablets.
  Widget _stacked() {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 18, 28, 18),
            child: _header(compact: false),
          ),
          const Divider(height: 1, color: PTColors.aisle),
          Expanded(
            child: ScrollFadeEdge(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 40, 28, 48),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: Column(
                      crossAxisAlignment: .stretch,
                      children: [
                        _doColumn(headlineSize: 52),
                        const SizedBox(height: 48),
                        _haveColumn(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _portrait() {
    // Edge-to-edge: the list scrolls under the home indicator / nav bar, and
    // the bottom inset pads the content so its last item still clears it.
    return SafeArea(
      bottom: false,
      child: ScrollFadeEdge(
        height: 48,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 10, 20, 40 + MediaQuery.paddingOf(context).bottom),
          child: Column(
            crossAxisAlignment: .stretch,
            spacing: 22,
            children: [
              _header(compact: true),
              if (UpdateService.instance.hasUpdate) _updateBanner(),
              _doColumn(headlineSize: 40, compact: true),
              _haveColumn(compact: true),
            ],
          ),
        ),
      ),
    );
  }

  Widget _landscape() {
    return SafeArea(
      minimum: const EdgeInsets.symmetric(horizontal: 44),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(
          crossAxisAlignment: .stretch,
          spacing: 12,
          children: [
            _header(compact: true),
            if (UpdateService.instance.hasUpdate) _updateBanner(),
            Expanded(
              child: Row(
                crossAxisAlignment: .stretch,
                spacing: 24,
                children: [
                  Expanded(
                    child: ScrollFadeEdge(
                      height: 40,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: _doColumn(headlineSize: 30, compact: true),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ScrollFadeEdge(
                      height: 40,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: _haveColumn(compact: true),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // The "do" column: eyebrow, headline, open a room, take a seat.

  Widget _doColumn({required double headlineSize, bool compact = false}) {
    final scaled = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        if (!compact && UpdateService.instance.hasUpdate) ...[
          _updateBanner(),
          const SizedBox(height: 28),
        ],
        _intro(child: const _Eyebrow()),
        SizedBox(height: compact ? 10 : 14),
        _intro(
          delay: const Duration(milliseconds: 60),
          child: Text(
            'What are we watching?',
            textScaler: scaled,
            style: PTText.display.copyWith(
              fontSize: headlineSize,
              height: 0.95,
              letterSpacing: -headlineSize * 0.045,
            ),
          ),
        ),
        SizedBox(height: compact ? 22 : 36),
        if (compact)
          _intro(delay: const Duration(milliseconds: 120), child: _compactActions())
        else ...[
          _intro(delay: const Duration(milliseconds: 120), child: _openForm(compact: false)),
          const SizedBox(height: 34),
          _intro(delay: const Duration(milliseconds: 180), child: _joinForm(compact: false)),
        ],
      ],
    );
  }

  /// Phones: two buttons, and the chosen one unfolds its form underneath -
  /// the room name and duration only when you are actually opening a room.
  Widget _compactActions() {
    final open = _phonePanel == _PhonePanel.open;
    final join = _phonePanel == _PhonePanel.join;
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Row(
          spacing: 10,
          children: [
            Expanded(
              child: PTButton(
                label: 'Open a room',
                variant: open ? .primary : (join ? .secondary : .primary),
                onPressed: () => setState(() => _phonePanel = open ? .none : .open),
              ),
            ),
            Expanded(
              child: PTButton(
                label: 'Enter a code',
                variant: join ? .primary : .secondary,
                onPressed: () => setState(() => _phonePanel = join ? .none : .join),
              ),
            ),
          ],
        ),
        // The chosen form unfolds under the buttons: size and cross-fade run
        // together, so the page grows into the form rather than jumping.
        AnimatedSize(
          duration: PTMotion.functional(context, PTMotion.panel),
          curve: PTMotion.emphasized,
          alignment: .topCenter,
          child: AnimatedSwitcher(
            duration: PTMotion.functional(context, PTMotion.state),
            switchInCurve: PTMotion.enter,
            switchOutCurve: PTMotion.exit,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, -0.04), end: Offset.zero).animate(animation),
                child: child,
              ),
            ),
            child: switch (_phonePanel) {
              _PhonePanel.none => const SizedBox(key: ValueKey('none'), width: double.infinity),
              _PhonePanel.open => Padding(
                key: const ValueKey('open'),
                padding: const EdgeInsets.only(top: 18),
                child: _openForm(compact: true),
              ),
              _PhonePanel.join => Padding(
                key: const ValueKey('join'),
                padding: const EdgeInsets.only(top: 18),
                child: _joinForm(compact: true),
              ),
            },
          ),
        ),
      ],
    );
  }

  Widget _openForm({required bool compact}) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      spacing: compact ? 14 : 18,
      children: [
        // Deliberately unvalidated: create_room defaults a blank name to "Watch
        // party". The 60 mirrors the server's cap so the field stops short of
        // silent truncation.
        PTTextField(
          controller: _nameController,
          label: 'Name your room',
          hint: 'Friday movie night',
          maxLength: 60,
        ),
        Column(
          crossAxisAlignment: .stretch,
          spacing: 10,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('RUNS FOR', overflow: .ellipsis, style: PTText.label),
                ),
                // Ticks over as the slider moves - the label the user is
                // actually looking at while choosing.
                AnimatedSwitcher(
                  duration: PTMotion.functional(context, PTMotion.hover),
                  switchInCurve: PTMotion.enter,
                  switchOutCurve: PTMotion.exit,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0, 0.35),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: Text(
                    _durationLabel,
                    key: ValueKey(_durationLabel),
                    style: PTText.mono.copyWith(
                      fontSize: compact ? 14 : 15,
                      fontWeight: .w600,
                      color: PTColors.textAccent,
                    ),
                  ),
                ),
              ],
            ),
            PTSlider(
              value: ((_durationMinutes - 5) / (_durationCap - 5)).clamp(0.0, 1.0),
              onChanged: (v) =>
                  setState(() => _durationMinutes = 5 + ((v * (_durationCap - 5)) / 5).round() * 5),
            ),
            Row(
              mainAxisAlignment: .spaceBetween,
              children: [
                Flexible(child: Text('5 MIN', style: PTText.label.copyWith(fontSize: 10))),
                Text(
                  '${_durationCapLabel.toUpperCase()} MAX',
                  style: PTText.label.copyWith(fontSize: 10),
                ),
              ],
            ),
          ],
        ),
        _stagedMediaSection(compact),
        const SizedBox(height: 2),
        PTButton(
          label: 'Open a room',
          height: compact ? 50 : 56,
          loading: _creating,
          onPressed: (_creating || _stagingUpload) ? null : _create,
        ),
      ],
    );
  }

  Widget _joinForm({required bool compact}) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      spacing: 12,
      children: [
        if (!compact)
          Row(
            spacing: 12,
            children: [
              Flexible(
                child: Text(
                  'OR ENTER A TICKET CODE',
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: PTText.label,
                ),
              ),
              const Expanded(child: Divider(height: 1, color: PTColors.aisle)),
            ],
          ),
        PTShake(
          trigger: _codeShake,
          child: PTCodeInput(
            key: _codeKey,
            boxHeight: compact ? 52 : 56,
            onChanged: (v) => _code = v,
          ),
        ),
        PTButton(
          label: 'Take your seat',
          trailingIcon: BoothIcons.arrowForward,
          variant: .secondary,
          height: compact ? 50 : 52,
          loading: _joining,
          onPressed: _joining ? null : () => _join(_code),
        ),
        Text(
          'Got an invite link instead? It opens the room by itself.',
          style: PTText.caption.copyWith(fontSize: 12, color: PTColors.white(0.45)),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // The "have" column: your tickets.

  Widget _haveColumn({bool compact = false}) {
    final rooms = RoomService.instance.myRooms;
    return _intro(
      delay: const Duration(milliseconds: 200),
      fade: false,
      child: rooms.isEmpty ? _noTickets(compact: compact) : _myRoomsSection(compact: compact),
    );
  }

  /// The empty state is a ticket too - an unprinted one, so the right column
  /// reads as "this is where they go" rather than as a blank.
  Widget _noTickets({required bool compact}) {
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 16,
      children: [
        Text('YOUR TICKETS', style: PTText.label),
        Opacity(
          opacity: 0.7,
          child: PTTicket(
            stubWidth: compact ? 92 : 116,
            body: Padding(
              padding: EdgeInsets.fromLTRB(compact ? 16 : 20, 18, 12, 18),
              child: Column(
                crossAxisAlignment: .start,
                mainAxisSize: .min,
                spacing: 6,
                children: [
                  Text('NOTHING PRINTED YET', style: PTText.label.copyWith(fontSize: 10)),
                  Text(
                    'Your next room',
                    style: PTText.cardHeading.copyWith(color: PTColors.white(0.55)),
                  ),
                  Text(
                    'Open one and its ticket prints here.',
                    style: PTText.caption.copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
            stub: Center(
              child: Text(
                '······',
                style: PTText.mono.copyWith(
                  fontSize: 16,
                  letterSpacing: 2,
                  color: PTColors.white(0.35),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _updateBanner() {
    final updates = UpdateService.instance;
    final String subtitle;
    final String buttonLabel;
    final bool isLoading;

    if (updates.isInstalling) {
      subtitle = 'Restarting SyncTogether with the new version...';
      buttonLabel = 'Restarting...';
      isLoading = true;
    } else if (updates.isDownloading) {
      final percent = (updates.downloadProgress * 100).clamp(0, 100).toInt();
      subtitle = 'Downloading update in the background...';
      buttonLabel = percent > 0 ? 'Downloading $percent%' : 'Downloading...';
      isLoading = true;
    } else if (updates.isDownloaded) {
      subtitle = 'Downloaded and ready. SyncTogether will restart itself.';
      buttonLabel = 'Update & restart';
      isLoading = false;
    } else {
      subtitle = 'Grab it now. SyncTogether will restart itself.';
      buttonLabel = 'Update & restart';
      isLoading = false;
    }

    return PTEntrance(
      offset: -8,
      duration: PTMotion.state,
      child: PTBanner(
        kind: .info,
        icon: Symbols.rocket_launch_rounded,
        title: 'v${updates.availableVersion} is ready',
        subtitle: subtitle,
        trailing: PTButton(
          label: buttonLabel,
          height: 38,
          expand: false,
          loading: isLoading,
          onPressed: isLoading ? null : _installUpdate,
        ),
        onDismiss: updates.dismiss,
      ),
    );
  }

  Future<void> _installUpdate() async {
    final started = await UpdateService.instance.installAndRestart();
    if (!started && mounted) {
      _snack("Hmm, the updater wouldn't start. You can grab the new version from GitHub instead.");
    }
  }

  bool get _showPremiumChip => !EntitlementService.instance.isPremium;

  bool get _showQuotaChip {
    final profile = ProfileService.instance.profile;
    return profile != null && !profile.isGuest;
  }

  /// Guests get a dimmed one rather than none. A guest cannot hold a streak -
  /// the account is purged in three days - but they also cannot discover a
  /// reason to sign in from a chip that is not there, and the board it opens is
  /// where that offer actually lives.
  bool get _showStreakChip {
    final profile = ProfileService.instance.profile;
    if (profile == null) return false;
    return profile.isGuest || RewardsService.instance.loaded;
  }

  Widget _streakChip({bool compact = false}) {
    final guest = ProfileService.instance.profile?.isGuest ?? false;
    final streak = RewardsService.instance.state.streak;
    return StreakChip(
      streak: streak,
      compact: compact,
      locked: guest,
      atRisk: !guest && streakAtRisk(streak, DateTime.now()),
      onTap: () => context.go('/lobby/leaderboard'),
    );
  }

  Widget _premiumChip({bool iconOnly = false}) {
    final crown = Icon(BoothIcons.crown, size: _glyph(16), fill: 1, color: PTColors.textAccent);
    if (iconOnly) {
      return Tooltip(
        message: 'Get a Patron seat',
        child: GlassPill(
          onTap: () => context.go('/lobby/subscribe?source=lobby_chip'),
          padding: const EdgeInsets.all(8),
          child: crown,
        ),
      );
    }
    return GlassPill(
      onTap: () => context.go('/lobby/subscribe?source=lobby_chip'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        mainAxisSize: .min,
        spacing: 6,
        children: [
          crown,
          Text(
            'Patron',
            maxLines: 1,
            style: PTText.body.copyWith(
              fontSize: 13,
              fontWeight: .w600,
              color: PTColors.textAccent,
            ),
          ),
        ],
      ),
    );
  }

  /// Remaining weekly upload allowance. Compact drops the noun - the cloud
  /// icon and the tooltip carry it.
  String _quotaLabel({required bool compact}) {
    final profile = ProfileService.instance.profile;
    final limits = EntitlementService.instance.limitsOrFallback;
    if (EntitlementService.instance.isPremium) return compact ? 'Unlimited' : 'Unlimited quota';
    final weeklyLimit = limits.mediaSharingWeeklyBytes;
    final remaining = profile?.remainingWeeklyBytes(weeklyLimit) ?? weeklyLimit;
    final bytes = Profile.formatBytes(remaining);
    return compact ? bytes : '$bytes quota';
  }

  Widget _mediaQuotaChip({bool compact = false}) {
    final profile = ProfileService.instance.profile;
    final limits = EntitlementService.instance.limitsOrFallback;
    final isPrem = EntitlementService.instance.isPremium;
    final isGuest = profile?.isGuest ?? true;

    final weeklyLimit = limits.mediaSharingWeeklyBytes;
    final remainingBytes = profile?.remainingWeeklyBytes(weeklyLimit) ?? weeklyLimit;
    final isLow = remainingBytes < 1024 * 1024 * 1024 && !isGuest && !isPrem;
    final colour = isPrem
        ? PTColors.textAccent
        : isLow
        ? PTColors.warning
        : null;

    final chip = GlassPill(
      onTap: () => showMediaQuotaDialog(context),
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12, vertical: 7),
      child: Row(
        mainAxisSize: .min,
        spacing: 6,
        children: [
          Icon(
            isPrem ? BoothIcons.crown : Symbols.cloud_queue_rounded,
            size: _glyph(16),
            fill: 1,
            color: colour ?? PTColors.white(0.75),
          ),
          Text(
            _quotaLabel(compact: compact),
            maxLines: 1,
            style: PTText.body.copyWith(
              fontSize: 13,
              fontWeight: .w600,
              color: colour ?? PTColors.white(0.85),
            ),
          ),
        ],
      ),
    );
    return compact ? Tooltip(message: 'Weekly upload quota', child: chip) : chip;
  }

  Widget _profilePill() {
    final profile = ProfileService.instance.profile;
    return GlassPill(
      onTap: () => context.go('/lobby/profile'),
      padding: const EdgeInsets.fromLTRB(6, 5, 16, 5),
      child: Row(
        mainAxisSize: .min,
        spacing: 10,
        children: [
          PTAvatar(
            userId: profile?.id ?? '',
            displayName: profile?.displayName ?? '?',
            avatarUrl: profile?.avatarUrl,
            size: _glyph(30),
            premium: EntitlementService.instance.isPremium,
          ),
          // Capped rather than Flexible: the header measures candidates at
          // their natural width, and a very long name should ellipsize here
          // instead of collapsing the whole header to the account menu.
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.textScalerOf(context).scale(180)),
            child: Text(
              profile?.displayName ?? '…',
              maxLines: 1,
              overflow: .ellipsis,
              style: PTText.body.copyWith(fontSize: 14, fontWeight: .w500),
            ),
          ),
        ],
      ),
    );
  }

  /// [menuLevel] set: the avatar opens the account menu holding whatever that
  /// header level left out. Unset: it goes straight to the profile.
  Widget _avatarButton({double size = 40, int? menuLevel}) {
    final profile = ProfileService.instance.profile;
    return Builder(
      builder: (anchor) => Semantics(
        button: true,
        label: menuLevel == null ? 'Profile' : 'Account menu',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: menuLevel == null
                ? () => context.go('/lobby/profile')
                : () => _openAccountMenu(anchor, menuLevel),
            child: PTAvatar(
              userId: profile?.id ?? '',
              displayName: profile?.displayName ?? '?',
              avatarUrl: profile?.avatarUrl,
              size: size,
              ringColor: PTColors.white(0.15),
              premium: EntitlementService.instance.isPremium,
            ),
          ),
        ),
      ),
    );
  }

  Widget _stagedMediaSection(bool compact) {
    if (_stagedSession != null && _stagedFile != null) {
      final fileName = p.basename(_stagedFile!.path);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: PTColors.glass(0.3),
          borderRadius: BorderRadius.circular(PTRadius.control),
          border: Border.all(color: PTColors.online.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Symbols.check_circle_rounded, color: PTColors.online, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    style: PTText.body.copyWith(fontSize: 12, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  Text(
                    'Pre-uploaded & ready for guests',
                    style: PTText.caption.copyWith(fontSize: 10, color: PTColors.online),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Remove staged video',
              icon: Icon(BoothIcons.close, size: 18, color: PTColors.white(0.6)),
              onPressed: _creating ? null : _cancelStagedMedia,
            ),
          ],
        ),
      );
    }

    if (_stagingUpload && _stagedFile != null) {
      final fileName = p.basename(_stagedFile!.path);
      final fraction = _stagingProgress?.fraction ?? 0.0;
      final percent = (fraction * 100).toInt();
      final speedMb = ((_stagingProgress?.speedBps ?? 0) / (1024 * 1024)).toStringAsFixed(1);
      final eta = _stagingProgress?.etaSeconds ?? 0;

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: PTColors.glass(0.3),
          borderRadius: BorderRadius.circular(PTRadius.control),
          border: Border.all(color: PTColors.white(0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Row(
              children: [
                const PTLoader(size: 14),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Pre-uploading $fileName...',
                    style: PTText.body.copyWith(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                Text(
                  '$percent%',
                  style: PTText.mono.copyWith(fontSize: 11, color: PTColors.textAccent),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Cancel upload',
                  icon: Icon(BoothIcons.close, size: 16, color: PTColors.white(0.6)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                  onPressed: _creating ? null : _cancelStagedMedia,
                ),
              ],
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: fraction,
                backgroundColor: PTColors.white(0.1),
                valueColor: const AlwaysStoppedAnimation<Color>(PTColors.textAccent),
                minHeight: 4,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$speedMb MB/s',
                  style: PTText.mono.copyWith(fontSize: 10, color: PTColors.white(0.4)),
                ),
                Text(
                  'ETA ${eta}s',
                  style: PTText.mono.copyWith(fontSize: 10, color: PTColors.white(0.4)),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final profile = ProfileService.instance.profile;
    final limits = EntitlementService.instance.limitsOrFallback;
    final isPrem = EntitlementService.instance.isPremium;
    final isGuest = profile?.isGuest ?? true;
    final weeklyLimit = limits.mediaSharingWeeklyBytes;
    final remainingBytes = profile?.remainingWeeklyBytes(weeklyLimit) ?? weeklyLimit;
    final isLow = remainingBytes < 1024 * 1024 * 1024 && !isGuest && !isPrem;

    final quotaSubtitle = isPrem
        ? 'Unlimited uploads with Premium • Up to 10 GB'
        : isGuest
        ? 'Sign in for free 2.5 GB streaming'
        : '${Profile.formatBytes(remainingBytes)} weekly quota available • Up to 2 GB';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _creating ? null : _pickStagedMedia,
        borderRadius: BorderRadius.circular(PTRadius.control),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: PTColors.glass(0.2),
            borderRadius: BorderRadius.circular(PTRadius.control),
            border: Border.all(color: PTColors.white(0.08)),
          ),
          child: Row(
            children: [
              Icon(BoothIcons.film, color: PTColors.textAccent, size: _glyph(20)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pre-upload video (optional)',
                      style: PTText.body.copyWith(fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    // Two lines, not one: the quota and the per-file cap are both
                    // the point, and one line cut the cap to "Up t…" on phones.
                    Text(
                      quotaSubtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: PTText.caption.copyWith(
                        fontSize: 11,
                        color: isLow ? PTColors.warning : PTColors.white(0.5),
                      ),
                    ),
                  ],
                ),
              ),
              if (isGuest)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: PTColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: PTColors.accentBorderSoft),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 4,
                    children: [
                      const Icon(BoothIcons.lock, size: 14, fill: 1, color: PTColors.textAccent),
                      Text(
                        'Unlock',
                        style: PTText.caption.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: PTColors.textAccent,
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                IconButton(
                  tooltip: 'Bandwidth quota info',
                  icon: const Icon(BoothIcons.info, size: 18, color: PTColors.textAccent),
                  onPressed: () => showMediaQuotaDialog(context),
                ),
                Icon(BoothIcons.add, color: PTColors.white(0.6), size: 18),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _intro({required Widget child, Duration delay = Duration.zero, bool fade = true}) {
    return PTEntrance(enabled: _playIntro, delay: delay, fade: fade, offset: 14, child: child);
  }
}

/// The lobby's kicker: day, time and a greeting in the mono label voice -
/// "FRI · 21:40 · GOOD EVENING, MAYA". Subscribes to [ProfileService] itself so
/// the name can't be captured in a scope that never rebuilds.
class _Eyebrow extends StatelessWidget {
  const _Eyebrow();

  static const _days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ProfileService.instance,
      builder: (context, _) {
        final now = DateTime.now();
        final name = ProfileService.instance.profile?.displayName.split(' ').first;
        final part = now.hour < 5
            ? 'LATE SHOW'
            : now.hour < 12
            ? 'GOOD MORNING'
            : now.hour < 18
            ? 'GOOD AFTERNOON'
            : 'GOOD EVENING';
        final time =
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
        return AnimatedSwitcher(
          duration: PTMotion.functional(context, PTMotion.state),
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.centerLeft,
            children: [...previous, if (current != null) current],
          ),
          child: Text(
            '${_days[now.weekday - 1]} · $time · $part${name == null ? '' : ', ${name.toUpperCase()}'}',
            key: ValueKey(name),
            maxLines: 1,
            overflow: .ellipsis,
            style: PTText.label,
          ),
        );
      },
    );
  }
}

enum _PhonePanel { none, open, join }

class _GuestLimitDialogBody extends StatelessWidget {
  const _GuestLimitDialogBody({
    required this.roomName,
    required this.onEnd,
    required this.onRejoin,
  });

  final String roomName;
  final VoidCallback onEnd;
  final VoidCallback onRejoin;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      spacing: 12,
      children: [
        Row(
          spacing: 13,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: PTColors.warningBorder.withValues(alpha: 0.12),
                border: Border.all(color: PTColors.warningBorder.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(PTRadius.panel),
              ),
              child: const Icon(
                Symbols.hourglass_top_rounded,
                size: 24,
                fill: 1,
                color: PTColors.warning,
              ),
            ),
            Text('One room at a time', style: PTText.cardHeading),
          ],
        ),
        Text.rich(
          TextSpan(
            text: 'Guests can host one live room at a time. ',
            children: [
              TextSpan(
                text: roomName,
                style: TextStyle(color: PTColors.white(0.85)),
              ),
              const TextSpan(text: ' is still running. End it first, or sign in to host more.'),
            ],
          ),
          style: PTText.body.copyWith(fontSize: 14, color: PTColors.white(0.6), height: 1.55),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            spacing: 11,
            children: [
              Expanded(
                child: PTButton(
                  label: 'End that room',
                  variant: .secondary,
                  height: 48,
                  onPressed: onEnd,
                ),
              ),
              Expanded(
                child: PTButton(label: 'Rejoin it', height: 48, onPressed: onRejoin),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: .min,
      crossAxisAlignment: .center,
      spacing: 12,
      children: [
        PTWordmark(size: compact ? 20 : 22),
        if (AppVersion.label case final version?)
          // Demo mode is mocked end to end, so the local stack is not what it
          // is exercising - and it is what shoots the marketing screenshots.
          Text(
            _flagLocal ? '$version · local' : version,
            style: PTText.mono.copyWith(
              fontSize: 11,
              color: _flagLocal ? PTColors.warning : PTColors.white(0.4),
            ),
          ),
      ],
    );
  }
}

bool get _flagLocal => Env.usingLocalStack && !kDemoMode;
