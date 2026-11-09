import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:synctogether/analytics.dart';
import 'package:synctogether/diagnostics.dart';
import 'package:synctogether/rewards/rewards_service.dart' show rewardsSiteBase;
import 'package:synctogether/rooms/room_models.dart';
import 'package:synctogether/rooms/room_service.dart';

import 'pair_logic.dart';
import 'pair_models.dart';

/// Everything about "your person": the pair, its invite, Our Room, the shared
/// date nights and what you watched together.
///
/// Shaped like [RewardsService]: a `ChangeNotifier` singleton that reads through
/// RPCs and whose failure mode is to *understate*. A client that could not load
/// shows nobody paired rather than a pairing the server does not agree with.
/// Every rule that matters (who may schedule, how much history shows, who may
/// enter Our Room) is enforced in `security definer` RPCs; this class only
/// carries the calls and keeps state fresh.
class PairService extends ChangeNotifier {
  PairService();
  PairService._();
  static PairService instance = PairService._();

  SupabaseClient? get _clientOrNull {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  SupabaseClient get _client => Supabase.instance.client;

  /// An invite code parked until the person is signed in and the lobby can show
  /// the accept screen (`synctogether://pair/<code>` opened signed out).
  String? pendingPairCode;

  PairInfo? _pair;
  PairInfo? get pair => _pair;
  bool get isPaired => _pair != null;

  /// An invite I opened and have not answered: the lobby banner.
  PairInvite? _pending;
  PairInvite? get pendingInvite => _pending;

  /// The invite I sent and is still waiting.
  PairInvite? _sent;
  PairInvite? get sentInvite => _sent;

  List<DateNight> _nights = const [];
  List<DateNight> get nights => _nights;

  /// Whether the nights list has been fetched at least once, and whether the
  /// last fetch failed. The screen needs the difference between "none yet" and
  /// "could not ask": a skeleton, an empty state and an error are three screens.
  bool _nightsLoaded = false;
  bool get nightsLoaded => _nightsLoaded;
  bool _nightsFailed = false;
  bool get nightsFailed => _nightsFailed;

  PairStats _stats = PairStats.empty;
  PairStats get stats => _stats;

  PairHistory _history = PairHistory.empty;
  PairHistory get history => _history;

  PushPrefs _prefs = const PushPrefs();
  PushPrefs get prefs => _prefs;

  bool _loaded = false;
  bool get loaded => _loaded;

  /// Banner invites the person said "Not now" to, for this run. The server keeps
  /// the invite for its 48 hours; the banner only stops nagging.
  final Set<String> _dismissed = {};

  PairInvite? get bannerInvite {
    final p = _pending;
    if (p == null || _dismissed.contains(p.code) || isPaired) return null;
    return p.isLiveAt(DateTime.now().toUtc()) ? p : null;
  }

  RealtimeChannel? _channel;
  Timer? _debounce;
  String? _channelUser;

  RealtimeChannel? _live;
  String? _liveFor;
  bool _partnerOnline = false;

  /// Whether the partner has the app open right now (private presence on the
  /// pair channel). False when unknown - the Call button then stays hidden,
  /// which understates rather than rings someone who is not there.
  bool get partnerOnline => _partnerOnline;

  String? get _uid => _clientOrNull?.auth.currentUser?.id;
  bool get isSignedInAccount {
    final user = _clientOrNull?.auth.currentUser;
    return user != null && !user.isAnonymous;
  }

  // ---------------------------------------------------------------- loading

  /// Loads the pair and, when paired, the shared lists. Safe to call often: it
  /// is what a realtime nudge, a resume and a sign-in all run.
  Future<void> load() async {
    final client = _clientOrNull;
    if (client == null) return;
    if (!isSignedInAccount) {
      clear();
      return;
    }
    try {
      final pairRow = await client.rpc('my_pair');
      _pair = pairRow == null ? null : PairInfo.fromJson((pairRow as Map).cast<String, dynamic>());

      if (_pair == null) {
        final pending = await client.rpc('my_pending_pair_invite');
        _pending = pending == null
            ? null
            : PairInvite.fromJson({
                ...(pending as Map).cast<String, dynamic>(),
                'status': 'pending',
              });
        await _loadSentInvite(client);
        _nights = const [];
        _nightsLoaded = false;
        _nightsFailed = false;
        _stats = PairStats.empty;
        _history = PairHistory.empty;
      } else {
        _pending = null;
        _sent = null;
        await Future.wait([_loadNights(client), _loadStats(client)]);
      }
      _loaded = true;
      _ensureRealtime();
      _ensureLive();
      notifyListeners();
    } catch (e, s) {
      reportNonFatal(e, s, during: 'loading the pair');
    }
  }

  Future<void> _loadSentInvite(SupabaseClient client) async {
    final uid = _uid;
    if (uid == null) return;
    final rows = await client
        .from('pair_invites')
        .select()
        .eq('inviter_id', uid)
        .eq('status', 'pending')
        .gt('expires_at', DateTime.now().toUtc().toIso8601String())
        .limit(1);
    _sent = rows.isEmpty
        ? null
        : PairInvite.mine(rows.first, PairPartner(id: uid, displayName: 'You'));
  }

  Future<void> _loadNights(SupabaseClient client) async {
    try {
      final rows = await client
          .from('date_nights')
          .select()
          .gte(
            'starts_at',
            DateTime.now().toUtc().subtract(const Duration(days: 1)).toIso8601String(),
          )
          .order('starts_at');
      _nights = [for (final r in rows) DateNight.fromJson(r)];
      _nightsFailed = false;
    } catch (e, s) {
      // Only the list failed: keep what we had, say so, and let the person retry.
      _nightsFailed = true;
      reportNonFatal(e, s, during: 'loading date nights');
    } finally {
      _nightsLoaded = true;
    }
  }

  /// Ask again after a failure, showing the skeleton while it runs.
  Future<void> retryNights() async {
    _nightsLoaded = false;
    _nightsFailed = false;
    notifyListeners();
    await _loadNights(_client);
    notifyListeners();
  }

  Future<void> _loadStats(SupabaseClient client) async {
    final row = await client.rpc('pair_stats');
    _stats = row == null
        ? PairStats.empty
        : PairStats.fromJson((row as Map).cast<String, dynamic>());
  }

  Future<PairHistory> loadHistory() async {
    try {
      final row = await _client.rpc('pair_history');
      _history = PairHistory.fromJson((row as Map).cast<String, dynamic>());
      notifyListeners();
    } catch (e, s) {
      reportNonFatal(e, s, during: 'loading the pair history');
    }
    return _history;
  }

  Future<PairStats> loadStatsForYear(int year) async {
    try {
      final row = await _client.rpc('pair_stats', params: {'p_year': year});
      return PairStats.fromJson((row as Map).cast<String, dynamic>());
    } catch (e, s) {
      reportNonFatal(e, s, during: 'loading the year recap stats');
      return PairStats.empty;
    }
  }

  Future<List<PairSession>> exportHistory() async {
    final rows = await _client.rpc('pair_history_export');
    return [
      for (final r in (rows as List)) PairSession.fromJson((r as Map).cast<String, dynamic>()),
    ];
  }

  Future<void> loadPrefs() async {
    try {
      final row = await _client.rpc('my_push_prefs');
      _prefs = PushPrefs.fromJson((row as Map).cast<String, dynamic>());
      notifyListeners();
    } catch (e, s) {
      reportNonFatal(e, s, during: 'loading push preferences');
    }
  }

  // --------------------------------------------------------------- realtime

  /// One channel, four tables. A change to any of them is a nudge to reload,
  /// debounced: an accept touches `pair_members` twice and `pair_invites` once.
  void _ensureRealtime() {
    final uid = _uid;
    if (uid == null || (_channel != null && _channelUser == uid)) return;
    _closeChannel();
    try {
      final channel = _client.channel('pair-state:$uid');
      void nudge(String table) {
        trace('pair realtime nudge', category: 'room', data: {'table': table});
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 250), load);
      }

      for (final table in const ['pair_members', 'pair_invites', 'date_nights']) {
        channel.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: table,
          callback: (_) => nudge(table),
        );
      }
      _channel = channel..subscribe();
      _channelUser = uid;
    } catch (e, s) {
      reportNonFatal(e, s, during: 'subscribing to pair changes');
    }
  }

  /// Private channel `pair:<id>`: presence for "is my person on", and
  /// authorised by the same `my_pair_id()` rule as
  /// every read, so an outsider cannot join it even holding the id.
  void _ensureLive() {
    final uid = _uid;
    final pairId = _pair?.pairId;
    if (uid == null || pairId == null) {
      _closeLive();
      return;
    }
    if (_live != null && _liveFor == pairId) return;
    _closeLive();
    try {
      final channel = _client.channel(
        'pair:$pairId',
        opts: RealtimeChannelConfig(private: true, key: uid),
      );
      channel
        ..onPresenceSync((_) {
          final partnerId = _pair?.partner.id;
          final online =
              partnerId != null &&
              channel.presenceState().any(
                (state) => state.presences.any((p) => p.payload['user_id'] == partnerId),
              );
          if (online != _partnerOnline) {
            _partnerOnline = online;
            // A transition, not the sync itself (those come in bursts).
            trace('pair presence changed', category: 'room', data: {'partner_online': online});
            notifyListeners();
          }
        })
        ..subscribe((status, error) {
          // Edges only: this fires on every (re)join.
          trace('pair presence channel', category: 'room', data: {'status': status.name});
          switch (status) {
            case RealtimeSubscribeStatus.subscribed:
              _liveFailures = 0;
              unawaited(_trackPresence(channel, uid, pairId));
            case RealtimeSubscribeStatus.channelError || RealtimeSubscribeStatus.timedOut:
              // The library rejoins an errored channel itself; this is only the
              // record that it had to, and the alarm if it keeps having to.
              _liveFailures++;
              if (_liveFailures == 4) {
                reportNonFatal(
                  StateError('pair presence channel keeps failing: ${error ?? status.name}'),
                  StackTrace.current,
                  during: 'joining the pair channel',
                  persistent: true,
                );
              }
            case RealtimeSubscribeStatus.closed:
              // Closed by us (the pair changed, or sign-out) clears `_liveFor`
              // first. Anything else was the server or the socket ending it, and
              // nothing would rejoin it: start a fresh one.
              if (_liveFor == pairId) _reopenLive(pairId);
          }
        });
      _live = channel;
      _liveFor = pairId;
    } catch (e, s) {
      reportNonFatal(e, s, during: 'joining the pair channel');
    }
  }

  int _liveFailures = 0;
  Timer? _liveReopen;

  /// Announce myself on the pair channel. `track` can fail without throwing
  /// (it answers with a status), and an unannounced device is invisible to its
  /// partner for as long as it stays on the channel, so check and try once more.
  Future<void> _trackPresence(RealtimeChannel channel, String uid, String pairId) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final result = await channel.track({'user_id': uid});
        if (result == ChannelResponse.ok) return;
        trace(
          'pair presence track refused',
          category: 'room',
          data: {'result': result.name, 'attempt': attempt + 1},
        );
      } catch (e, s) {
        reportNonFatal(e, s, during: 'announcing presence on the pair channel');
      }
      await Future<void>.delayed(Duration(seconds: 2 * (attempt + 1)));
      if (_liveFor != pairId) return;
    }
  }

  void _reopenLive(String pairId) {
    _liveReopen?.cancel();
    _liveReopen = Timer(const Duration(seconds: 3), () {
      if (_liveFor != pairId) return;
      _closeLive();
      _ensureLive();
    });
  }

  void _closeLive() {
    _liveReopen?.cancel();
    _liveReopen = null;
    final c = _live;
    _live = null;
    _liveFor = null;
    if (_partnerOnline) _partnerOnline = false;
    if (c != null) unawaited(_clientOrNull?.removeChannel(c));
  }

  void _closeChannel() {
    final c = _channel;
    _channel = null;
    _channelUser = null;
    if (c != null) unawaited(_clientOrNull?.removeChannel(c));
  }

  void clear() {
    _debounce?.cancel();
    _debounce = null;
    _closeChannel();
    _closeLive();
    _pair = null;
    _pending = null;
    _sent = null;
    _nights = const [];
    _nightsLoaded = false;
    _nightsFailed = false;
    _stats = PairStats.empty;
    _history = PairHistory.empty;
    _loaded = false;
    _dismissed.clear();
    pendingPairCode = null;
    notifyListeners();
  }

  // ------------------------------------------------------------- time zone

  String? _reportedZone;

  /// Tells the server this device's IANA zone so a partner's screens can show
  /// the right clock. Quiet by design: a device that cannot say simply has none.
  Future<void> syncTimezone() async {
    final client = _clientOrNull;
    if (client == null || !isSignedInAccount) return;
    try {
      final zone = (await FlutterTimezone.getLocalTimezone()).identifier;
      if (zone == _reportedZone) return;
      await client.rpc('set_my_timezone', params: {'p_timezone': zone});
      _reportedZone = zone;
    } on MissingPluginException {
      // A platform (or a test) with no native side: nothing to report.
    } catch (e, s) {
      reportNonFatal(e, s, during: 'reporting the time zone');
    }
  }

  // --------------------------------------------------------------- pairing

  /// A fresh or reused invite for me to send. Idempotent on the server, so
  /// "Share again" never mints a second code.
  Future<PairInvite> createInvite() async {
    try {
      final row = await _client.rpc('create_pair_invite');
      final invite = PairInvite.mine(
        (row as Map).cast<String, dynamic>(),
        PairPartner(id: _uid ?? '', displayName: 'You'),
      );
      _sent = invite;
      notifyListeners();
      Analytics.instance.track('pair_invite_created');
      trace('pair invite created', category: 'room');
      return invite;
    } catch (e, s) {
      _reportUnexpected(e, s, 'creating a pair invite');
      rethrow;
    }
  }

  /// Invites by email. The answer is the same whether or not an account matched -
  /// that is the point: a different one would let anybody test which addresses
  /// have accounts - so callers say "sent, if they have an account" and nothing
  /// more. The invite is also returned so the sender can always share its link.
  Future<PairInvite> inviteByEmail(String email) async {
    try {
      final row = await _client.rpc('invite_pair_by_email', params: {'p_email': email});
      final invite = PairInvite.mine(
        (row as Map).cast<String, dynamic>(),
        PairPartner(id: _uid ?? '', displayName: 'You'),
      );
      _sent = invite;
      notifyListeners();
      Analytics.instance.track('pair_invite_emailed');
      trace('pair invite sent by email', category: 'room');
      return invite;
    } catch (e, s) {
      _reportUnexpected(e, s, 'inviting a partner by email');
      rethrow;
    }
  }

  Future<void> cancelInvite() async {
    await _client.rpc('cancel_pair_invite');
    _sent = null;
    notifyListeners();
  }

  /// What the accept screen shows. Opening a link also remembers me as its
  /// latest viewer so the lobby banner can remind me if I walk away.
  Future<PairInvite> previewInvite(String code) async {
    try {
      final row = (await _client.rpc('get_pair_invite', params: {'p_code': code}) as Map)
          .cast<String, dynamic>();
      // A miss is an answer, not an error, so the server can count it against
      // the attempt budget (an exception would roll the count back).
      if (row['status'] == 'not_found') throw PostgrestException(message: 'invite_not_found');
      return PairInvite.fromJson(row);
    } catch (e, s) {
      _reportUnexpected(e, s, 'previewing a pair invite');
      rethrow;
    }
  }

  Future<void> acceptInvite(String code) async {
    try {
      final paired = await _client.rpc('accept_pair_invite', params: {'p_code': code});
      // Null is the server's "no such code", returned so the attempt counts.
      if (paired == null) throw PostgrestException(message: 'invite_not_found');
      Analytics.instance.track('pair_accepted');
      trace('pair accepted', category: 'room');
      await load();
      await syncTimezone();
    } catch (e, s) {
      _reportUnexpected(e, s, 'accepting a pair invite');
      rethrow;
    }
  }

  void dismissBanner(String code) {
    _dismissed.add(code);
    notifyListeners();
  }

  Future<void> unpair() async {
    try {
      await _client.rpc('unpair');
      Analytics.instance.track('pair_ended');
      trace('unpaired', category: 'room');
      _pair = null;
      _nights = const [];
      _nightsLoaded = false;
      _nightsFailed = false;
      _stats = PairStats.empty;
      _history = PairHistory.empty;
      notifyListeners();
      await load();
    } catch (e, s) {
      _reportUnexpected(e, s, 'unpairing');
      rethrow;
    }
  }

  /// What I call my person. Private to me: nobody else can read it, and an empty
  /// or null [name] goes back to the name they chose.
  Future<void> setPartnerNickname(String? name) async {
    try {
      await _client.rpc('set_partner_nickname', params: {'p_nickname': name});
      trace(
        'partner nickname set',
        category: 'room',
        data: {'cleared': (name ?? '').trim().isEmpty},
      );
      await load();
    } catch (e, s) {
      _reportUnexpected(e, s, 'setting the partner nickname');
      rethrow;
    }
  }

  Future<void> setReunion(DateTime? on, String? label) async {
    try {
      await _client.rpc(
        'set_reunion',
        params: {
          'p_on': on == null
              ? null
              : '${on.year.toString().padLeft(4, '0')}-${on.month.toString().padLeft(2, '0')}-${on.day.toString().padLeft(2, '0')}',
          'p_label': label,
        },
      );
      await load();
    } catch (e, s) {
      _reportUnexpected(e, s, 'setting the reunion date');
      rethrow;
    }
  }

  // -------------------------------------------------------------- Our Room

  /// Create-or-resume the pair's room, make me a member, and adopt it as the
  /// current room so the room screen finds it the way it finds any other.
  Future<Room> openOurRoom() async {
    try {
      final row = await _client.rpc('open_our_room');
      final map = row is List ? row.first as Map : row as Map;
      final room = Room.fromJson(map.cast<String, dynamic>());
      await RoomService.instance.joinRoom(room.code, via: .pair);
      Analytics.instance.track('our_room_opened');
      return room;
    } catch (e, s) {
      _reportUnexpected(e, s, 'opening Our Room');
      rethrow;
    }
  }

  /// Rings the partner. False when throttled (one a minute) - nothing to say to
  /// the person, the room is open for them either way.
  Future<bool> callPartner() async {
    try {
      final row = await _client.rpc('call_partner');
      final sent = ((row as Map)['sent'] as bool?) ?? false;
      if (sent) Analytics.instance.track('partner_called');
      return sent;
    } catch (e, s) {
      _reportUnexpected(e, s, 'calling the partner');
      rethrow;
    }
  }

  /// Logs a sitting spent together. Silent: a lost sitting is not worth a
  /// snackbar over a film, and both partners may report the same one.
  Future<void> logSession({
    required String? title,
    required DateTime startedAt,
    required Duration together,
  }) async {
    if (!isPaired || !isLoggableSitting(together)) return;
    try {
      await _client.rpc(
        'log_pair_session',
        params: {
          'p_title': title,
          'p_started_at': startedAt.toUtc().toIso8601String(),
          'p_seconds': together.inSeconds,
        },
      );
      trace('pair sitting logged', category: 'room', data: {'seconds': together.inSeconds});
    } catch (e, s) {
      reportNonFatal(e, s, during: 'logging a sitting together');
    }
  }

  // ----------------------------------------------------------- date nights

  Future<DateNight> planNight({
    required String title,
    required DateTime startsAt,
    String? youtubeUrl,
    String? stagedId,
  }) async {
    try {
      final row = await _client.rpc(
        'create_date_night',
        params: {
          'p_title': title,
          'p_starts_at': startsAt.toUtc().toIso8601String(),
          'p_youtube_url': youtubeUrl,
          'p_staged_id': stagedId,
        },
      );
      Analytics.instance.track('date_night_planned', {
        'attach': stagedId != null
            ? 'file'
            : youtubeUrl == null
            ? 'none'
            : 'youtube',
      });
      await _reloadNights();
      return DateNight.fromJson((row as Map).cast<String, dynamic>());
    } catch (e, s) {
      _reportUnexpected(e, s, 'planning a date night');
      rethrow;
    }
  }

  Future<void> answerNight(String id, {required bool accept}) async {
    try {
      await _client.rpc('respond_date_night', params: {'p_id': id, 'p_accept': accept});
      Analytics.instance.track('date_night_answered', {'accepted': accept});
      await _reloadNights();
    } catch (e, s) {
      _reportUnexpected(e, s, 'answering a date night');
      rethrow;
    }
  }

  Future<void> rescheduleNight(String id, DateTime startsAt) async {
    try {
      await _client.rpc(
        'reschedule_date_night',
        params: {'p_id': id, 'p_starts_at': startsAt.toUtc().toIso8601String()},
      );
      await _reloadNights();
    } catch (e, s) {
      _reportUnexpected(e, s, 'moving a date night');
      rethrow;
    }
  }

  /// "Change what we're watching": the planner swaps the attached YouTube link,
  /// or passes null to go back to choosing together.
  Future<void> setNightAttachment(String id, String? youtubeUrl) async {
    try {
      await _client.rpc(
        'set_date_night_attachment',
        params: {'p_id': id, 'p_youtube_url': youtubeUrl},
      );
      await _reloadNights();
    } catch (e, s) {
      _reportUnexpected(e, s, 'changing what a date night is watching');
      rethrow;
    }
  }

  /// Choose the file again (after a stopped upload, or to add one to a night
  /// that has none): adopt a fresh staged upload as the night's file.
  Future<void> attachStagedFile(String nightId, String stagedId) async {
    try {
      await _client.rpc(
        'date_night_attach_staged',
        params: {'p_night_id': nightId, 'p_staged_id': stagedId},
      );
      await _reloadNights();
    } catch (e, s) {
      _reportUnexpected(e, s, 'attaching a file to a date night');
      rethrow;
    }
  }

  /// The planner's app reporting how far the upload has got, or that it stopped.
  /// Best effort: a missed report costs a stale percentage, never the upload.
  Future<void> reportUploadProgress(String nightId, int bytes, {bool stopped = false}) async {
    try {
      await _client.rpc(
        'set_date_night_upload_progress',
        params: {
          'p_night_id': nightId,
          'p_bytes': bytes,
          'p_state': stopped ? 'stopped' : 'uploading',
        },
      );
    } catch (e, s) {
      _reportUnexpected(e, s, 'reporting date night upload progress');
    }
  }

  Future<void> cancelNight(String id) async {
    await _client.rpc('cancel_date_night', params: {'p_id': id});
    await _reloadNights();
  }

  Future<void> _reloadNights() async {
    await _loadNights(_client);
    notifyListeners();
  }

  // ---------------------------------------------------------------- prefs

  Future<void> setPref(String key, bool value) async {
    final before = _prefs;
    _prefs = before.withKey(key, value);
    notifyListeners();
    try {
      await _client.rpc('set_push_pref', params: {'p_key': key, 'p_value': value});
    } catch (e, s) {
      _prefs = before;
      notifyListeners();
      reportNonFatal(e, s, during: 'saving a notification switch');
    }
  }

  // ------------------------------------------------------------- reporting

  /// A mapped [PairErrorCode] is a normal answer; only the `unknown` fallback is
  /// worth a Sentry event.
  void _reportUnexpected(Object e, StackTrace s, String during) {
    if (PairErrorCode.fromError(e) == PairErrorCode.unknown) {
      reportNonFatal(e, s, during: during);
    }
  }
}

/// The link an invite carries. A web page when the build has a portal (it hands
/// off to the app, or offers the download), the app scheme link otherwise.
String pairInviteLink(String code) {
  final upper = code.toUpperCase();
  final base = rewardsSiteBase;
  return base == null ? 'synctogether://pair/$upper' : '$base/pair/$upper';
}
