import 'package:synctogether/pairing/pair_models.dart';
import 'package:synctogether/pairing/pair_service.dart';

/// A [PairService] with its state handed in, so a screen can be pumped with no
/// backend. Nothing here touches Supabase: every read returns what the test set,
/// every write is recorded in [calls] and otherwise does nothing.
class FakePairService extends PairService {
  FakePairService({
    this.account = true,
    PairInfo? pair,
    PairInvite? pending,
    PairInvite? sent,
    this._preview,
    List<DateNight> nights = const [],
    PairStats stats = PairStats.empty,
    PairHistory history = PairHistory.empty,
    PushPrefs prefs = const PushPrefs(),
    this.online = false,
    this.failInviteWith,
    this.isLoaded = true,
    this.failCreateInvite = false,
    this.nightsAreLoaded = true,
    this.nightsDidFail = false,
  }) : _fakePair = pair,
       _fakePending = pending,
       _fakeSent = sent,
       _fakeNights = nights,
       _fakeStats = stats,
       _fakeHistory = history,
       _fakePrefs = prefs;

  final bool account;
  final bool online;

  /// Makes `inviteByEmail` throw, to drive the error copy.
  final Object? failInviteWith;

  /// Makes `createInvite` fail, as it would offline.
  bool failCreateInvite;

  /// Whether the nights list has been fetched, and whether that failed: the
  /// skeleton and error states of the Date nights screen.
  bool nightsAreLoaded;
  bool nightsDidFail;
  final bool isLoaded;
  PairInfo? _fakePair;
  final PairInvite? _fakePending;
  PairInvite? _fakeSent;
  final PairInvite? _preview;
  List<DateNight> _fakeNights;
  final PairStats _fakeStats;
  final PairHistory _fakeHistory;
  PushPrefs _fakePrefs;

  /// Every write, as `name` or `name:argument`, in order.
  final calls = <String>[];

  @override
  bool get isSignedInAccount => account;

  @override
  bool get loaded => isLoaded;

  @override
  bool get nightsLoaded => nightsAreLoaded;

  @override
  bool get nightsFailed => nightsDidFail;

  @override
  Future<void> retryNights() async {
    calls.add('retryNights');
    nightsAreLoaded = true;
    nightsDidFail = false;
    notifyListeners();
  }

  @override
  PairInfo? get pair => _fakePair;

  @override
  bool get isPaired => _fakePair != null;

  @override
  PairInvite? get pendingInvite => _fakePending;

  @override
  PairInvite? get bannerInvite => isPaired ? null : _fakePending;

  @override
  PairInvite? get sentInvite => _fakeSent;

  @override
  List<DateNight> get nights => _fakeNights;

  @override
  PairStats get stats => _fakeStats;

  @override
  PairHistory get history => _fakeHistory;

  @override
  PushPrefs get prefs => _fakePrefs;

  @override
  bool get partnerOnline => online;

  @override
  Future<void> load() async {}

  @override
  Future<void> syncTimezone() async {}

  @override
  Future<PairHistory> loadHistory() async => _fakeHistory;

  @override
  Future<void> loadPrefs() async {}

  @override
  Future<PairStats> loadStatsForYear(int year) async => _fakeStats;

  @override
  Future<PairInvite> createInvite() async {
    calls.add('createInvite');
    if (failCreateInvite) throw StateError('offline');
    _fakeSent ??= PairInvite(
      code: 'M4YA7K',
      inviter: const PairPartner(id: 'me', displayName: 'You'),
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 46)),
      isMine: true,
    );
    notifyListeners();
    return _fakeSent!;
  }

  @override
  Future<PairInvite> inviteByEmail(String email) async {
    calls.add('inviteByEmail:$email');
    if (failInviteWith != null) throw failInviteWith!;
    return createInvite();
  }

  @override
  Future<void> cancelInvite() async {
    calls.add('cancelInvite');
    _fakeSent = null;
    notifyListeners();
  }

  @override
  Future<PairInvite> previewInvite(String code) async {
    calls.add('previewInvite:$code');
    final p = _preview;
    if (p == null) throw Exception('invite_not_found');
    return p;
  }

  @override
  Future<void> acceptInvite(String code) async {
    calls.add('acceptInvite:$code');
  }

  @override
  Future<void> unpair() async {
    calls.add('unpair');
    _fakePair = null;
    notifyListeners();
  }

  @override
  Future<void> setPartnerNickname(String? name) async {
    calls.add('setPartnerNickname:${name ?? ''}');
    final pair = _fakePair;
    if (pair != null) {
      _fakePair = PairInfo(
        pairId: pair.pairId,
        since: pair.since,
        partner: pair.partner.withNickname(name),
        reunionOn: pair.reunionOn,
        reunionLabel: pair.reunionLabel,
        patron: pair.patron,
        roomId: pair.roomId,
        roomCode: pair.roomCode,
      );
    }
    notifyListeners();
  }

  @override
  void dismissBanner(String code) => calls.add('dismissBanner:$code');

  @override
  Future<void> setReunion(DateTime? on, String? label) async => calls.add('setReunion:$on:$label');

  @override
  Future<bool> callPartner() async {
    calls.add('callPartner');
    return true;
  }

  @override
  Future<DateNight> planNight({
    required String title,
    required DateTime startsAt,
    String? youtubeUrl,
    String? stagedId,
  }) async {
    calls.add('planNight:$title:${youtubeUrl ?? ''}:${stagedId ?? ''}');
    final night = DateNight(
      id: 'n-${_fakeNights.length}',
      title: title,
      startsAt: startsAt.toUtc(),
      proposedBy: 'me',
      status: DateNightStatus.proposed,
      attachKind: stagedId != null
          ? 'file'
          : youtubeUrl == null
          ? 'none'
          : 'youtube',
      youtubeUrl: youtubeUrl,
      fileName: stagedId == null ? null : 'film.mkv',
      fileSize: stagedId == null ? null : 1000,
      uploadState: stagedId == null ? 'none' : 'uploading',
    );
    _fakeNights = [..._fakeNights, night];
    notifyListeners();
    return night;
  }

  @override
  Future<void> attachStagedFile(String nightId, String stagedId) async =>
      calls.add('attachStagedFile:$nightId:$stagedId');

  @override
  Future<void> reportUploadProgress(String nightId, int bytes, {bool stopped = false}) async =>
      calls.add('reportUploadProgress:$nightId:$bytes:$stopped');

  @override
  Future<void> setNightAttachment(String id, String? youtubeUrl) async {
    calls.add('setNightAttachment:$id:${youtubeUrl ?? ''}');
    _fakeNights = [
      for (final n in _fakeNights)
        if (n.id == id)
          DateNight(
            id: n.id,
            title: n.title,
            startsAt: n.startsAt,
            proposedBy: n.proposedBy,
            status: n.status,
            attachKind: youtubeUrl == null ? 'none' : 'youtube',
            youtubeUrl: youtubeUrl,
          )
        else
          n,
    ];
    notifyListeners();
  }

  @override
  Future<void> answerNight(String id, {required bool accept}) async =>
      calls.add('answerNight:$id:$accept');

  @override
  Future<void> rescheduleNight(String id, DateTime startsAt) async =>
      calls.add('rescheduleNight:$id');

  @override
  Future<void> cancelNight(String id) async => calls.add('cancelNight:$id');

  @override
  Future<void> setPref(String key, bool value) async {
    calls.add('setPref:$key:$value');
    _fakePrefs = _fakePrefs.withKey(key, value);
    notifyListeners();
  }

  @override
  Future<List<PairSession>> exportHistory() async {
    calls.add('exportHistory');
    return _fakeHistory.items;
  }
}

PairInfo samePairInfo({
  String? partnerZone = 'America/New_York',
  bool patron = false,
  DateTime? reunionOn,
  String? reunionLabel,
}) => PairInfo(
  pairId: 'pair-1',
  since: DateTime.utc(2026, 3, 2),
  patron: patron,
  reunionOn: reunionOn,
  reunionLabel: reunionLabel,
  partner: PairPartner(id: 'sam', displayName: 'Sam Rivera', timezone: partnerZone),
);
