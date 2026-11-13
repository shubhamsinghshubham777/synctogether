import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:synctogether/diagnostics.dart';

import '../contract.dart';
import '../feedback_services.dart';
import 'discovery_logic.dart';
import 'discovery_prefs.dart';

/// Owns what discovery currently wants on screen: the coach mark, one nudge
/// banner, the "fixed" banner. [DiscoveryHost] draws it; the rest of the app
/// only calls [notify] (something went wrong), [noteRoomVisited] and
/// [shouldAskReview] (a film finished).
///
/// Never on a timer and never in a per-frame path: every change here is a
/// human-scale transition, which is also why each one gets a `trace`.
class DiscoveryTriggers extends ChangeNotifier {
  DiscoveryTriggers({DiscoveryPrefs? prefs, DateTime Function()? clock})
    : _prefs = prefs ?? DiscoveryPrefs(),
      _now = clock ?? DateTime.now;

  static DiscoveryTriggers instance = DiscoveryTriggers();

  /// The platform's own rating sheet. No review package is in the app yet, so
  /// this is a seam: until something sets it, no Rate row or "Great" button
  /// shows. Never invent a store URL here (operator values stay out of the client).
  static VoidCallback? onRate;

  /// Opens the store page of a newer build. Same story as [onRate].
  static VoidCallback? onUpdate;

  final DiscoveryPrefs _prefs;
  final DateTime Function() _now;
  StreamSubscription<List<BugReportRow>>? _sub;
  bool _started = false;
  bool _shownNudgeThisSession = false;

  NudgeReason? _nudge;
  BugReportRow? _fixed;
  bool _coach = false;
  bool _coachAnchorMounted = false;
  List<BugReportRow> _rows = const [];

  NudgeReason? get nudge => _nudge;
  BugReportRow? get fixedBanner => _fixed;
  List<BugReportRow> get rows => _rows;

  /// The coach mark shows only while its anchor (the bug button) is on screen.
  bool get coachVisible => _coach && _coachAnchorMounted;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _prefs.load();
    await _prefs.bumpLaunches();
    _coach = coachDue(
      alreadyShown: _prefs.coachShown,
      launches: _prefs.launches,
      roomsVisited: _prefs.roomsVisited,
    );
    _sub = FeedbackServices.instance.watchMine().listen((rows) {
      _rows = rows;
      final next = newlyFixed(rows, _prefs.fixedTold);
      if (next?.code != _fixed?.code) {
        _fixed = next;
        if (next != null) {
          trace('fixed banner', category: 'feedback', data: {'code': next.code});
        }
      }
      notifyListeners();
    }, onError: (Object e, StackTrace s) => reportNonFatal(e, s, during: 'watching bug reports'));
    notifyListeners();
  }

  /// The bug button mounted or unmounted.
  void anchorChanged(bool mounted) {
    if (_coachAnchorMounted == mounted) return;
    _coachAnchorMounted = mounted;
    notifyListeners();
  }

  Future<void> dismissCoach() async {
    if (!_coach) return;
    _coach = false;
    await _prefs.setCoachShown();
    trace('coach mark done', category: 'feedback');
    notifyListeners();
  }

  /// A film room was entered (coach-mark eligibility only).
  Future<void> noteRoomVisited() async {
    await _prefs.load();
    await _prefs.bumpRooms();
    if (!_coach &&
        coachDue(
          alreadyShown: _prefs.coachShown,
          launches: _prefs.launches,
          roomsVisited: _prefs.roomsVisited,
        )) {
      _coach = true;
      notifyListeners();
    }
  }

  /// The app noticed trouble. Offers a report at most once a session and not
  /// again within the cooldown after the last answer.
  void notify(NudgeReason reason) {
    if (_nudge != null) return;
    if (!nudgeAllowed(
      now: _now(),
      shownThisSession: _shownNudgeThisSession,
      lastAnsweredAt: _prefs.nudgeAnsweredAt,
    )) {
      return;
    }
    _shownNudgeThisSession = true;
    _nudge = reason;
    trace('nudge shown', category: 'feedback', data: {'reason': reason.name});
    notifyListeners();
  }

  /// [accepted] is the user tapping the button; otherwise it was dismissed or
  /// timed out. Both start the cooldown.
  Future<void> answerNudge({required bool accepted}) async {
    final reason = _nudge;
    if (reason == null) return;
    _nudge = null;
    await _prefs.setNudgeAnswered(_now());
    trace(
      'nudge answered',
      category: 'feedback',
      data: {'reason': reason.name, 'accepted': accepted},
    );
    notifyListeners();
  }

  Future<void> dismissFixed() async {
    final r = _fixed;
    if (r == null) return;
    _fixed = null;
    await _prefs.addFixedTold(r.code);
    notifyListeners();
  }

  /// After a finished film. True at most twice a year, and only when the store
  /// seam exists; the caller shows the prompt and calls [recordReviewAsked].
  Future<bool> shouldAskReview() async {
    if (onRate == null) return false;
    await _prefs.load();
    return reviewAllowed(now: _now(), asked: _prefs.reviewsAsked);
  }

  Future<void> recordReviewAsked() => _prefs.addReviewAsked(_now());

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }
}
