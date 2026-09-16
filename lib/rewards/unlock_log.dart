import 'package:shared_preferences/shared_preferences.dart';

import '../diagnostics.dart';

const _kShownKey = 'pt.rewards.badges_announced';

/// Remembers which badges this device has already announced.
///
/// This exists for one reason: `achievement_unlocked` is the most valuable
/// product event in the whole feature, and it is also the one most at risk of
/// being counted twice. A reconnect, a reinstall, a second device or a replayed
/// `my_rewards` can all surface the same unlock again, and every one of those
/// would inflate the funnel. The event fires once per badge per account, at the
/// moment the toast is first shown, and never from an observer's client.
class UnlockLog {
  UnlockLog._();
  static final instance = UnlockLog._();

  Set<String>? _shown;

  Future<Set<String>> _load() async {
    final cached = _shown;
    if (cached != null) return cached;
    try {
      final prefs = await SharedPreferences.getInstance();
      return _shown = (prefs.getStringList(_kShownKey) ?? const <String>[]).toSet();
    } catch (e, s) {
      reportNonFatal(e, s, during: 'reading the announced-badge log');
      return _shown = <String>{};
    }
  }

  /// True the first time a badge is announced, false every time after.
  Future<bool> markAnnounced(String achievementId) async {
    final shown = await _load();
    if (!shown.add(achievementId)) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kShownKey, shown.toList());
    } catch (e, s) {
      reportNonFatal(e, s, during: 'saving the announced-badge log');
    }
    return true;
  }

  /// Sign-out and account deletion: a second account on the same machine must
  /// not inherit the first one's announcements.
  Future<void> clear() async {
    _shown = <String>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kShownKey);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'clearing the announced-badge log');
    }
  }
}
