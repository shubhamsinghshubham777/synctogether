/// Recognises a deliberate shake in a stream of linear-acceleration samples
/// (gravity already removed, m/s²). Pure Dart, no sensor and no clock of its own:
/// the caller supplies each sample's timestamp, so the rule is testable as a table.
///
/// One *swing* is a firm movement: a run of samples above [threshold] pointing
/// the same way. The next swing points the other way. People count a shake as
/// a full down-and-up, which is two swings, and want two of them: so a shake is
/// [swings] consecutive swings (four, any direction), each starting within
/// [pauseLimit] of the one before.
///
/// If the user pauses longer than [pauseLimit], everything so far is dropped and
/// the next movement counts as swing one again. The detector keeps only the
/// current count, the direction of the swing in progress and when it started:
/// no history, no list of times. After a shake it is deaf for [cooldown] so one
/// shake never opens two sheets.
///
/// Calibration (linear acceleration, gravity removed): a hand shaking a phone by
/// +-2 cm at 3 Hz is ~7 m/s², +-5 cm at 4 Hz ~31; walking peaks at 3-4 and a
/// phone put down hard is one swing and a ring. Hence [threshold] 7: a gentle
/// but deliberate shake counts, walking does not. [pauseLimit] 400 ms means
/// anything slower than ~1.25 Hz (a wave of the arm, not a shake) is out.
/// Android only: iOS uses Apple's own shake gesture (see `shake_source.dart`).
/// Known limit: running with the phone in a pocket (10+ m/s² at ~3 Hz, reversing
/// every half step) looks exactly like a shake. It can only fire while the app
/// is open and the screen is on, and the sheet closes with one tap.
class ShakeDetector {
  ShakeDetector({
    this.threshold = 7,
    this.swings = 4,
    this.pauseLimit = defaultPauseLimit,
    this.cooldown = const Duration(seconds: 2),
    this.minSwingGap = const Duration(milliseconds: 40),
  });

  /// No swing starting within this long of the previous one: start over.
  static const defaultPauseLimit = Duration(milliseconds: 400);

  /// Minimum acceleration magnitude (m/s², about 0.7 g) for a sample to count.
  final double threshold;

  /// Consecutive swings that make a shake.
  final int swings;
  final Duration pauseLimit;
  final Duration cooldown;

  /// A swing against the last one closer than this is sensor ringing.
  final Duration minSwingGap;

  double _px = 0, _py = 0, _pz = 0;
  int _count = 0;
  Duration? _lastSwingAt;
  Duration? _deafUntil;

  /// Swings counted so far in the current attempt (0 after a pause).
  int get consecutive => _count;

  /// Feeds one sample taken at [at] (any monotonic clock). Returns true exactly
  /// when this sample completes a shake.
  bool add(double x, double y, double z, Duration at) {
    if (_deafUntil case final until? when at < until) return false;
    if (x * x + y * y + z * z < threshold * threshold) return false;

    final last = _lastSwingAt;
    if (last != null && at - last > pauseLimit) {
      // A pause: forget the partial shake, this movement is swing one again.
      _px = _py = _pz = 0;
      _count = 0;
    }

    // Still the swing in progress: same direction as the last sample.
    if (_count > 0 && (x * _px + y * _py + z * _pz) >= 0) {
      _px = x;
      _py = y;
      _pz = z;
      return false;
    }
    // The other way, but too soon after the last swing began: sensor ringing.
    if (_count > 0 && last != null && at - last < minSwingGap) return false;

    _px = x;
    _py = y;
    _pz = z;
    _lastSwingAt = at;
    _count++;
    if (_count < swings) return false;

    reset();
    _deafUntil = at + cooldown;
    return true;
  }

  /// Forgets everything: the app went to the background or the feature was
  /// switched off, so half a shake must not carry over.
  void reset() {
    _px = _py = _pz = 0;
    _count = 0;
    _lastSwingAt = null;
    _deafUntil = null;
  }
}
