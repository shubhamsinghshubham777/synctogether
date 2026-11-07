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
    this.isLoaded = true,
  }) : _fakePair = pair,
       _fakePending = pending,
       _fakeSent = sent,
       _fakeNights = nights,
       _fakeStats = stats,
       _fakeHistory = history,
       _fakePrefs = prefs;

  final bool account;
  final bool online;
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
  void dismissBanner(String code) => calls.add('dismissBanner:$code');

  @override
  Future<void> setReunion(DateTime? on, String? label) async => calls.add('setReunion:$on:$label');

  @override
  Future<bool> callPartner() async {
    calls.add('callPartner');
    return true;
  }

  @override
  Future<DateNight> planNight({required String title, required DateTime startsAt}) async {
    calls.add('planNight:$title');
    final night = DateNight(
      id: 'n-${_fakeNights.length}',
      title: title,
      startsAt: startsAt.toUtc(),
      proposedBy: 'me',
      status: DateNightStatus.proposed,
    );
    _fakeNights = [..._fakeNights, night];
    notifyListeners();
    return night;
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
  String partnerZone = 'America/New_York',
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
