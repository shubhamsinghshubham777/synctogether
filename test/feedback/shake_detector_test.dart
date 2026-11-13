import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/feedback/shake_detector.dart';

Duration ms(int v) => Duration(milliseconds: v);

/// One swing sample: `sign` along x at [at].
bool swing(ShakeDetector d, int at, double sign, {double g = 20}) => d.add(sign * g, 0, 0, ms(at));

void main() {
  /// Four alternating swings [gap] ms apart starting at [from]; true if the last fired.
  bool fourSwings(ShakeDetector d, {int from = 0, int gap = 150}) {
    var fired = false;
    for (var i = 0; i < 4; i++) {
      fired = swing(d, from + i * gap, i.isEven ? 1 : -1);
    }
    return fired;
  }

  test('a shake is four swings by default: two full down-and-ups', () {
    final d = ShakeDetector();
    expect(d.swings, 4);
    expect(
      [swing(d, 0, 1), swing(d, 150, -1), swing(d, 300, 1), swing(d, 450, -1)],
      [false, false, false, true],
    );
  });

  test('one swing never fires, however long it lasts', () {
    final d = ShakeDetector();
    for (var t = 0; t < 2000; t += 20) {
      expect(swing(d, t, 1), isFalse);
    }
    expect(d.consecutive, 1);
  });

  test('one down-and-up (two swings) is not enough', () {
    final d = ShakeDetector();
    expect([swing(d, 0, 1), swing(d, 150, -1)], [false, false]);
    expect(d.consecutive, 2);
  });

  test('swings spaced by more than pauseLimit never fire', () {
    final d = ShakeDetector();
    final late = ShakeDetector.defaultPauseLimit.inMilliseconds + 1;
    expect(fourSwings(d, gap: late), isFalse);
    expect(d.consecutive, 1, reason: 'every late swing starts over as swing one');
  });

  test('four swings exactly pauseLimit apart still count', () {
    final d = ShakeDetector();
    expect(fourSwings(d, gap: ShakeDetector.defaultPauseLimit.inMilliseconds), isTrue);
  });

  test('three swings, then a pause, then one swing does not fire', () {
    final d = ShakeDetector();
    swing(d, 0, 1);
    swing(d, 150, -1);
    swing(d, 300, 1);
    expect(d.consecutive, 3);
    expect(swing(d, 1000, -1), isFalse); // the pause dropped all three
    expect(d.consecutive, 1);
  });

  test('a pause, then four fresh swings, fires', () {
    final d = ShakeDetector();
    swing(d, 0, 1);
    swing(d, 150, -1);
    swing(d, 300, 1);
    expect(fourSwings(d, from: 1500), isTrue);
  });

  test('a partial shake is forgotten: nothing carries over the pause', () {
    final d = ShakeDetector();
    swing(d, 0, 1);
    swing(d, 150, -1);
    swing(d, 2000, -1); // same direction as the last, after a long pause: swing one
    expect(d.consecutive, 1);
  });

  test('the swing count is a parameter', () {
    final d = ShakeDetector(swings: 2);
    expect([swing(d, 0, 1), swing(d, 150, -1)], [false, true]);
  });

  test('samples below the threshold are ignored, so a phone on a table never fires', () {
    final d = ShakeDetector();
    for (var i = 0; i < 40; i++) {
      expect(d.add(i.isEven ? 6 : -6, 0, 0, ms(i * 25)), isFalse);
    }
    expect(d.consecutive, 0);
  });

  test('a swing right after another, closer than the minimum gap, is ringing', () {
    final d = ShakeDetector();
    expect(swing(d, 0, 1), isFalse);
    expect(swing(d, 10, -1), isFalse); // 10 ms later: sensor bounce
    expect(d.consecutive, 1);
  });

  test('after a shake it is deaf for the cooldown, then works again', () {
    final d = ShakeDetector();
    expect(fourSwings(d), isTrue);
    // Another full shake straight away is swallowed.
    expect(fourSwings(d, from: 600), isFalse);
    expect(fourSwings(d, from: 1300), isFalse);
    // Past the 2 s cooldown a fresh shake fires.
    expect(fourSwings(d, from: 2600), isTrue);
  });

  test('reset forgets half a shake', () {
    final d = ShakeDetector();
    swing(d, 0, 1);
    swing(d, 150, -1);
    swing(d, 300, 1);
    d.reset();
    expect(swing(d, 450, -1), isFalse);
    expect(d.consecutive, 1);
  });

  test('direction is a vector, not an axis: a shake along y or a diagonal counts', () {
    final d = ShakeDetector();
    var fired = false;
    for (var i = 0; i < 4; i++) {
      fired = d.add(i.isEven ? 10 : -10, i.isEven ? 10 : -10, 0, ms(i * 150));
    }
    expect(fired, isTrue);
  });

  group('realistic 50 Hz traces (one sample per 20 ms, like the iOS stream)', () {
    /// A hand-held oscillation: amplitude [amp] m/s² at [hz], along a diagonal,
    /// for [seconds]. Returns when the detector first fired, or null.
    Duration? run(ShakeDetector d, {required double amp, required double hz, double seconds = 3}) {
      for (var t = 0; t <= seconds * 1000; t += 20) {
        final a = amp * math.sin(2 * math.pi * hz * t / 1000);
        if (d.add(a * 0.8, a * 0.6, 0, ms(t))) return ms(t);
      }
      return null;
    }

    test('a gentle shake (7.5 m/s² at 3 Hz) fires', () {
      expect(run(ShakeDetector(), amp: 7.5, hz: 3), isNotNull);
    });

    test('a normal shake (8 m/s² at 4 Hz) fires inside 0.6 s', () {
      final at = run(ShakeDetector(), amp: 8, hz: 4);
      expect(at, isNotNull);
      expect(at!, lessThan(ms(600)));
    });

    test('a hard shake (30 m/s² at 5 Hz) fires fast', () {
      final at = run(ShakeDetector(), amp: 30, hz: 5);
      expect(at, isNotNull);
      expect(at!, lessThan(ms(400)));
    });

    test('walking with the phone in hand (3.5 m/s² at 2 Hz) never fires', () {
      expect(run(ShakeDetector(), amp: 3.5, hz: 2, seconds: 30), isNull);
    });

    test('a slow wave of the arm (8 m/s² at 1 Hz) is not a shake', () {
      expect(run(ShakeDetector(), amp: 8, hz: 1, seconds: 20), isNull);
    });

    test('putting the phone down hard is one impact and a ring, not a shake', () {
      final d = ShakeDetector();
      var fired = false;
      for (var t = 0; t <= 1500; t += 20) {
        final a = 25 * math.exp(-t / 30) * math.cos(2 * math.pi * 25 * t / 1000);
        fired |= d.add(a, 0, 0, ms(t));
      }
      expect(fired, isFalse);
    });

    test('a single hard tap then silence never fires', () {
      final d = ShakeDetector();
      var fired = d.add(30, 0, 0, ms(0));
      for (var t = 20; t <= 2000; t += 20) {
        fired |= d.add(0.2, 0, 0, ms(t));
      }
      expect(fired, isFalse);
    });

    test(
      'known limit: running with the phone in a pocket (14 m/s² at 2.8 Hz) looks like a shake',
      () {
        // Acceleration alone cannot tell this from a hand shake. It can only
        // happen while the app is open and the screen is on (ShakeToReport
        // listens only in the foreground), and the sheet closes with one tap.
        expect(run(ShakeDetector(), amp: 14, hz: 2.8), isNotNull);
      },
    );

    test('two shakes a few seconds apart both fire, one shake fires once', () {
      final d = ShakeDetector();
      var fires = 0;
      for (var t = 0; t <= 6000; t += 20) {
        final active = t < 1000 || (t >= 3500 && t < 4500);
        final a = active ? 12 * math.sin(2 * math.pi * 4 * t / 1000) : 0.0;
        if (d.add(a, 0, 0, ms(t))) fires++;
      }
      expect(fires, 2);
    });
  });
}
