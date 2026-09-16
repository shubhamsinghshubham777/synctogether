import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:synctogether/analytics_consent.dart';
import 'package:synctogether/diagnostics.dart';

import 'rewards_logic.dart';
import 'rewards_models.dart';

/// Base of the shareable web surface. Every public artefact this feature mints -
/// a recap, a profile card, the board - is an https URL, because the app's
/// `synctogether://` scheme does not linkify anywhere a person would post it and
/// is a dead end for anyone who has not installed the app yet.
String get rewardsSiteBase => kDebugMode ? 'http://localhost:3000' : 'https://synctogether.app';

String recapUrl(String id) => '$rewardsSiteBase/r/$id';

String profileUrl(String handle) => '$rewardsSiteBase/u/$handle';

/// Reads the ledger, streak, badges and boards, and carries the one write the
/// room makes - the heartbeat.
///
/// Shaped like [EntitlementService]: a `ChangeNotifier` singleton whose failure
/// mode is to *understate*. A client that could not load shows no streak, never
/// a streak the server does not agree with.
class RewardsService extends ChangeNotifier {
  RewardsService();
  RewardsService._();
  static RewardsService instance = RewardsService._();

  SupabaseClient get _client => Supabase.instance.client;

  /// Null when Supabase has not been initialized - a widget test, or a build
  /// with no backend configured. Every *read* path goes through this, because
  /// reporting an uninitialized backend would turn a condition that is not a
  /// bug into a failure on every test that happens to mount a screen.
  SupabaseClient? get _clientOrNull {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  RewardState _state = RewardState.empty;
  RewardState get state => _state;

  bool _loading = false;
  bool get loading => _loading;

  bool _loaded = false;
  bool get loaded => _loaded;

  final _unlockController = StreamController<Achievement>.broadcast();

  /// Newly crossed achievements, in the order the server reported them. The
  /// toast that renders these is also where the single `achievement_unlocked`
  /// analytics event is emitted - see the note on that event in the room.
  Stream<Achievement> get unlocks => _unlockController.stream;

  StreakState get streak => _state.streak;

  bool get hasStreak => _state.streak.current > 0;

  Future<RewardState?> load() async {
    final client = _clientOrNull;
    if (client == null) return null;
    if (client.auth.currentUser == null) {
      clear();
      return null;
    }
    if (_loading) return _state;
    _loading = true;
    try {
      final row = await client.rpc('my_rewards');
      if (row == null) return _state;
      _state = RewardState.fromJson((row as Map).cast<String, dynamic>());
      _loaded = true;
      notifyListeners();
      return _state;
    } catch (e, s) {
      reportNonFatal(e, s, during: 'loading the reward state');
      return _state;
    } finally {
      _loading = false;
    }
  }

  Future<RewardState?> refresh() => load();

  /// The room's 60 s heartbeat. Everything that decides whether a second is
  /// earned happens server-side; `localDay` and `localHour` are the only things
  /// the client is trusted with, and both are range-checked there.
  ///
  /// Deliberately silent about its own failures: a lost minute is not worth a
  /// snackbar over a video, and the next beat re-anchors anyway.
  ///
  /// Gated on the usage-data switch, and that coupling is deliberate. A person
  /// who turns off data collection has said something about how they want to be
  /// treated, and quietly carrying on writing what they watched and with whom -
  /// under the excuse that it is a product feature rather than telemetry - is
  /// exactly the manoeuvre that makes privacy switches untrustworthy. The switch
  /// stops everything, the UI says so plainly, and the streak is paused rather
  /// than broken.
  Future<HeartbeatResult> recordProgress(String roomId, {DateTime? now}) async {
    if (AnalyticsConsent.instance.optedOut) {
      return const HeartbeatResult(outcome: HeartbeatOutcome.optedOut);
    }
    final at = now ?? DateTime.now();
    final client = _clientOrNull;
    if (client == null) return HeartbeatResult.none;
    try {
      final row = await client.rpc(
        'record_watch_progress',
        params: {
          'p_room_id': roomId,
          'p_local_day':
              '${at.year.toString().padLeft(4, '0')}-'
              '${at.month.toString().padLeft(2, '0')}-'
              '${at.day.toString().padLeft(2, '0')}',
          'p_local_hour': at.hour,
        },
      );
      if (row == null) return HeartbeatResult.none;
      final result = HeartbeatResult.fromJson((row as Map).cast<String, dynamic>());
      _applyHeartbeat(result);
      return result;
    } catch (e, s) {
      reportNonFatal(e, s, during: 'recording watch progress');
      return HeartbeatResult.none;
    }
  }

  void _applyHeartbeat(HeartbeatResult result) {
    for (final unlocked in result.unlocked) {
      _unlockController.add(unlocked);
    }
    if (result.outcome == .guest || result.outcome == .disabled || result.outcome == .optedOut) {
      return;
    }
    if (!result.credited && result.unlocked.isEmpty) return;

    // Keep the in-memory state in step without a second round trip; the next
    // full load reconciles anything this misses.
    final unlockedIds = {for (final a in result.unlocked) a.id};
    _state = RewardState(
      enabled: _state.enabled,
      tier: _state.tier,
      publicProfile: _state.publicProfile,
      handle: _state.handle,
      equippedFrame: _state.equippedFrame,
      streak: StreakState(
        current: result.streak,
        longest: result.longestStreak,
        freezes: result.freezes,
        secondsToday: result.secondsToday,
        minMinutes: _state.streak.minMinutes,
        qualifiedToday: result.dayQualified,
        lastDay: result.dayQualified ? DateTime.now() : _state.streak.lastDay,
        lastFreezeDay: _state.streak.lastFreezeDay,
      ),
      totals: _state.totals,
      points: RewardPoints(
        today: result.pointsToday,
        week: _state.points.week,
        month: _state.points.month,
        all: _state.points.all,
      ),
      weekRank: _state.weekRank,
      circleRank: _state.circleRank,
      globalBoard: _state.globalBoard,
      achievements: [
        for (final a in _state.achievements)
          if (unlockedIds.contains(a.id))
            Achievement(
              id: a.id,
              title: a.title,
              description: a.description,
              icon: a.icon,
              grade: a.grade,
              metric: a.metric,
              threshold: a.threshold,
              frame: a.frame,
              unlocked: true,
              unlockedAt: DateTime.now(),
            )
          else
            a,
      ],
      metrics: _state.metrics,
      frames: {
        ..._state.frames,
        for (final a in result.unlocked)
          if (a.frame case final f?) f,
      },
      seasons: _state.seasons,
    );
    notifyListeners();
  }

  Future<List<LeaderboardRow>> leaderboard({
    LeaderboardScope scope = LeaderboardScope.circle,
    LeaderboardPeriod period = LeaderboardPeriod.week,
    int limit = 100,
  }) async {
    final client = _clientOrNull;
    if (client == null) return const [];
    try {
      final rows = await client.rpc(
        'leaderboard',
        params: {'p_scope': scope.wire, 'p_period': period.wire, 'p_limit': limit},
      );
      if (rows is! List) return const [];
      return [
        for (final row in rows) LeaderboardRow.fromJson((row as Map).cast<String, dynamic>()),
      ];
    } catch (e, s) {
      reportNonFatal(e, s, during: 'loading the leaderboard');
      return const [];
    }
  }

  /// Consent to be published. Server-side, because the server is what publishes
  /// and therefore what must be able to refuse.
  Future<bool> setPublicProfile(bool value) async {
    final previous = _state.publicProfile;
    try {
      final result = await _client.rpc('set_public_profile', params: {'p_value': value});
      final applied = result as bool? ?? value;
      _state = _copy(publicProfile: applied);
      notifyListeners();
      trace('leaderboard visibility changed', category: 'rewards', data: {'public': applied});
      return applied;
    } catch (e, s) {
      reportNonFatal(e, s, during: 'changing leaderboard visibility');
      return previous;
    }
  }

  /// Throws [RewardsFailure] so the caller can show the right copy - a taken
  /// handle and a reserved handle need different advice, and "try again" is
  /// wrong for both.
  Future<String> claimHandle(String handle) async {
    try {
      final result = await _client.rpc('claim_handle', params: {'p_handle': handle});
      final claimed = result as String? ?? handle.trim().toLowerCase();
      _state = _copy(handle: claimed);
      notifyListeners();
      return claimed;
    } catch (e, s) {
      final failure = RewardsFailure.from(e);
      if (failure.code == RewardErrorCode.unknown) {
        reportNonFatal(e, s, during: 'claiming a handle');
      }
      throw failure;
    }
  }

  Future<void> equipFrame(AvatarFrame? frame) async {
    try {
      await _client.rpc('equip_frame', params: {'p_frame': frame?.name});
      _state = _copy(equippedFrame: frame, clearFrame: frame == null);
      notifyListeners();
    } catch (e, s) {
      final failure = RewardsFailure.from(e);
      if (failure.code == RewardErrorCode.unknown) {
        reportNonFatal(e, s, during: 'equipping an avatar frame');
      }
      throw failure;
    }
  }

  int _referrals = 0;

  /// How many people first walked into a room of ours. Computed server-side from
  /// `profiles.referred_by`, which `join_room` stamps once and never overwrites -
  /// desktop has no install-referrer, so this is the attribution that is actually
  /// knowable, and it is unfakeable.
  int get referrals => _referrals;

  Future<int> loadReferrals() async {
    final client = _clientOrNull;
    if (client == null || client.auth.currentUser == null) return _referrals;
    try {
      final row = await client.rpc('my_referrals');
      if (row == null) return _referrals;
      final total = ((row as Map)['total'] as num?)?.toInt() ?? 0;
      if (total == _referrals) return _referrals;
      _referrals = total;
      notifyListeners();
      return _referrals;
    } catch (e, s) {
      reportNonFatal(e, s, during: 'loading the referral count');
      return _referrals;
    }
  }

  Future<List<SharedRecap>> loadSharedRecaps() async {
    final client = _clientOrNull;
    if (client == null) return const [];
    try {
      final rows = await client.rpc('my_recaps');
      if (rows is! List) return const [];
      return [for (final row in rows) SharedRecap.fromJson((row as Map).cast<String, dynamic>())];
    } catch (e, s) {
      reportNonFatal(e, s, during: 'loading shared recaps');
      return const [];
    }
  }

  /// Immediate and total - the row goes, so the public page 404s straight away
  /// rather than waiting out the ninety-day sweep. Somebody taking a link back
  /// is not asking us to schedule it.
  Future<bool> deleteSharedRecap(String id) async {
    final client = _clientOrNull;
    if (client == null) return false;
    try {
      final result = await client.rpc('delete_recap', params: {'p_id': id});
      final deleted = result as bool? ?? false;
      if (deleted) trace('recap deleted', category: 'rewards');
      return deleted;
    } catch (e, s) {
      reportNonFatal(e, s, during: 'deleting a shared recap');
      return false;
    }
  }

  Future<void> markSeen(Iterable<String> ids) async {
    if (ids.isEmpty) return;
    try {
      await _client.rpc('mark_achievements_seen', params: {'p_ids': ids.toList()});
    } catch (e, s) {
      reportNonFatal(e, s, during: 'marking achievements as seen');
    }
  }

  /// Mints the public page a session recap is shared as, and returns its URL.
  ///
  /// The payload is deliberately thin and the server rebuilds it anyway: no
  /// media name, no file path, no YouTube id, no chat content. Co-watchers who
  /// have not opted into a public profile are rendered anonymously by the
  /// server, not by us.
  Future<String?> shareRecap(SessionRecap recap) async {
    try {
      final row = await _client.rpc(
        'create_recap',
        params: {
          'p_room_id': recap.roomId,
          'p_seconds': recap.length.inSeconds,
          'p_peak_members': recap.peakMembers,
          'p_messages': recap.messages,
          'p_reactions': recap.reactions,
          'p_top_emoji': recap.topEmoji,
          'p_modes': recap.modes.toList()..sort(),
          'p_facecam': recap.facecamUsed,
          'p_clean_gate': recap.cleanGate,
          'p_participants': recap.participantIds,
          'p_superlatives': [for (final s in recap.superlatives) s.toWire()],
        },
      );
      if (row == null) return null;
      final map = (row as Map).cast<String, dynamic>();
      for (final unlocked in (map['unlocked'] as List?) ?? const []) {
        _unlockController.add(
          Achievement.fromJson({...(unlocked as Map).cast<String, dynamic>(), 'unlocked': true}),
        );
      }
      final id = map['id'] as String?;
      if (id == null) return null;
      trace('recap minted', category: 'rewards', data: {'room_id': recap.roomId});
      return recapUrl(id);
    } catch (e, s) {
      final failure = RewardsFailure.from(e);
      if (failure.code == RewardErrorCode.unknown) {
        reportNonFatal(e, s, during: 'sharing a session recap');
      }
      throw failure;
    }
  }

  void clear() {
    if (_state == RewardState.empty && !_loaded && _referrals == 0) return;
    _state = RewardState.empty;
    _referrals = 0;
    _loaded = false;
    notifyListeners();
  }

  @visibleForTesting
  void setStateForTesting(RewardState state) {
    _state = state;
    _loaded = true;
    notifyListeners();
  }

  RewardState _copy({
    bool? publicProfile,
    String? handle,
    AvatarFrame? equippedFrame,
    bool clearFrame = false,
  }) => RewardState(
    enabled: _state.enabled,
    tier: _state.tier,
    publicProfile: publicProfile ?? _state.publicProfile,
    handle: handle ?? _state.handle,
    equippedFrame: clearFrame ? null : (equippedFrame ?? _state.equippedFrame),
    streak: _state.streak,
    totals: _state.totals,
    points: _state.points,
    weekRank: _state.weekRank,
    circleRank: _state.circleRank,
    globalBoard: _state.globalBoard,
    achievements: _state.achievements,
    metrics: _state.metrics,
    frames: _state.frames,
    seasons: _state.seasons,
  );

  @override
  void dispose() {
    _unlockController.close();
    super.dispose();
  }
}

enum RewardErrorCode {
  guestNotEligible('guest_not_eligible', 'Sign in to unlock streaks and leaderboards.'),
  premiumRequired('premium_required', 'Handles are a Premium thing - your rank works either way.'),
  invalidHandle('invalid_handle', 'Handles are 3-20 letters, numbers or underscores.'),
  handleTaken('handle_taken', 'Someone already has that one. Try another?'),
  handleReserved('handle_reserved', "That one's spoken for. Try another?"),
  frameLocked('frame_locked', "You haven't unlocked that look yet."),
  notAMember('not_a_member', "You weren't in that room, so there's nothing to share."),
  notAuthenticated('not_authenticated', 'Your session has expired. Please sign in again.'),
  unknown('unknown', 'Something went sideways. Give it another try.');

  const RewardErrorCode(this.code, this.message);

  final String code;
  final String message;

  static RewardErrorCode fromError(Object error) {
    final text = error.toString();
    for (final value in values) {
      if (value != unknown && text.contains(value.code)) return value;
    }
    return unknown;
  }
}

class RewardsFailure implements Exception {
  const RewardsFailure(this.code);

  factory RewardsFailure.from(Object error) => RewardsFailure(RewardErrorCode.fromError(error));

  final RewardErrorCode code;

  String get message => code.message;

  @override
  String toString() => 'RewardsFailure(${code.code})';
}
