import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/diagnostics.dart';

/// The small local memory behind discovery: what the user has already been
/// told, so nothing repeats. Local on purpose - per device, never synced.
class DiscoveryPrefs {
  DiscoveryPrefs({SharedPreferences? testPrefs}) : _prefs = testPrefs;

  static const _kCoach = 'feedback.coach_shown';
  static const _kLaunches = 'feedback.launches';
  static const _kRooms = 'feedback.rooms_visited';
  static const _kNudge = 'feedback.nudge_answered_ms';
  static const _kTold = 'feedback.fixed_told';
  static const _kReviews = 'feedback.review_asked_ms';

  SharedPreferences? _prefs;

  Future<void> load() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
    } catch (e, s) {
      reportNonFatal(e, s, during: 'loading discovery prefs');
    }
  }

  bool get coachShown => _prefs?.getBool(_kCoach) ?? false;
  int get launches => _prefs?.getInt(_kLaunches) ?? 0;
  int get roomsVisited => _prefs?.getInt(_kRooms) ?? 0;

  DateTime? get nudgeAnsweredAt {
    final ms = _prefs?.getInt(_kNudge);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Set<String> get fixedTold => (_prefs?.getStringList(_kTold) ?? const []).toSet();

  List<DateTime> get reviewsAsked => [
    for (final s in _prefs?.getStringList(_kReviews) ?? const [])
      if (int.tryParse(s) case final ms?) DateTime.fromMillisecondsSinceEpoch(ms),
  ];

  Future<void> setCoachShown() async => _prefs?.setBool(_kCoach, true);
  Future<void> bumpLaunches() async => _prefs?.setInt(_kLaunches, launches + 1);
  Future<void> bumpRooms() async => _prefs?.setInt(_kRooms, roomsVisited + 1);
  Future<void> setNudgeAnswered(DateTime at) async =>
      _prefs?.setInt(_kNudge, at.millisecondsSinceEpoch);
  Future<void> addFixedTold(String code) async =>
      _prefs?.setStringList(_kTold, {...fixedTold, code}.toList());
  Future<void> addReviewAsked(DateTime at) async => _prefs?.setStringList(_kReviews, [
    for (final t in reviewsAsked) '${t.millisecondsSinceEpoch}',
    '${at.millisecondsSinceEpoch}',
  ]);
}
