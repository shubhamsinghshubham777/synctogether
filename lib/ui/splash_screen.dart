import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:synctogether/diagnostics.dart';
import 'package:synctogether/ui/pt_motion.dart';
import 'package:synctogether/ui/pt_theme.dart';

/// Total run: film leader, the Beam strikes, the wordmark rolls up, hand-off.
const _kTotal = Duration(milliseconds: 2400);

/// Under reduce-motion the landed frame rests this long before the fade.
const _kReducedHold = Duration(milliseconds: 300);

// The choreography, in milliseconds from t=0 (canvas board 91 mirrors it).

/// The sweep hand makes one calm turn across the countdown - a third of the
/// first cut's speed, which read as frantic rather than a calm "nearly there".
const _kSweepEnd = 1050;
const _kSweepTurns = 1.0;

/// The leader ring snaps shut into the Beam; the strike lands at its end.
const _kCloseStart = 950;
const _kStrike = 1200;

/// 3 · 2 · 1, one numeral per window.
const _kCountdown = [(100, 400, '3'), (400, 700, '2'), (700, 1000, '1')];

/// Letters roll up from the baseline one after another, from the left.
const _kLettersStart = 1220;
const _kLetterStep = 25;
const _kLetterRoll = 420;
const _kEyebrowStart = 1600;

/// The app is built here, still hidden, so its first frame - the lobby's
/// whole tree - is paid for under the strike's flash frame, where a dropped
/// frame cannot be seen, instead of on the first frame of the fade, where it
/// stalls the raster thread and turns the cross-fade into a cut.
const _kPrewarm = 1210;
const _kExitStart = 1950;

const _kWord = 'sync·together';
const _kDotIndex = 4;

double _seg(double ms, num a, num b, [Curve curve = Curves.linear]) =>
    curve.transform(((ms - a) / (b - a)).clamp(0.0, 1.0));

/// Cold-start splash: a film leader counts down while startup work runs
/// behind it (see `StartupWarmup` in main.dart), the ring closes into the
/// Beam, and the wordmark rolls up before the app cross-fades in.
///
/// It is an overlay in `MaterialApp.builder`, not a route - the router,
/// redirects and the deep-link handler in main.dart all keep running
/// underneath, so an invite link that arrives during the splash still lands.
class PTSplash extends StatefulWidget {
  const PTSplash({super.key, required this.child});

  final Widget child;

  @override
  State<PTSplash> createState() => _PTSplashState();
}

class _PTSplashState extends State<PTSplash> with SingleTickerProviderStateMixin, RestorationMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: _kTotal)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _shown.value = true;
        setState(() => _finished = true);
      }
    });

  bool _finished = false;

  /// Set once the splash has played. It is restorable, so when the OS kills
  /// the app in the background and restores it, the user lands straight back
  /// where they were instead of sitting through the countdown again.
  final _shown = RestorableBool(false);

  @override
  String get restorationId => 'splash';

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_shown, 'shown');
    if (_shown.value) trace('splash skipped on restore', category: 'ui');
  }

  Timer? _reducedMotionTimer;

  @override
  void initState() {
    super.initState();
    // First frame is laid out before the clock starts, so the controller's
    // first tick is not charged with initial build cost.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startAnimation();
    });
  }

  void _startAnimation() {
    if (_shown.value) return;
    if (reducedMotion(context)) {
      // Decorative motion renders its end state; the hold gives the wordmark
      // somewhere to rest before the hand-off.
      _controller.value = _kExitStart / _kTotal.inMilliseconds;
      _reducedMotionTimer = Timer(_kReducedHold, () {
        if (mounted) _controller.forward();
      });
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _reducedMotionTimer?.cancel();
    _controller.dispose();
    _shown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_finished || _shown.value) return widget.child;
    double ms() => _controller.value * _kTotal.inMilliseconds;
    return Stack(
      fit: .expand,
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => ms() >= _kPrewarm ? widget.child : const SizedBox.shrink(),
        ),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = ms();
            final leaving = _seg(t, _kExitStart, _kTotal.inMilliseconds, PTMotion.emphasized);
            if (leaving >= 1) return const SizedBox.shrink();
            return Opacity(
              opacity: 1 - leaving,
              child: RepaintBoundary(
                child: _Stage(ms: t, exit: leaving),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _Stage extends StatelessWidget {
  const _Stage({required this.ms, required this.exit});

  final double ms;
  final double exit;

  @override
  Widget build(BuildContext context) {
    // `MaterialApp.builder` sits above every Scaffold, so there is no ancestor
    // text style here - without this the wordmark paints with the framework's
    // yellow "unstyled text" underline.
    return DefaultTextStyle(
      style: PTText.body,
      child: ColoredBox(
        // Flat Booth, the lobby's own ground, so the hand-off has no seam.
        color: PTColors.canvas,
        child: LayoutBuilder(
          builder: (context, box) {
            // 46 on a 390 phone, capped for desktop windows.
            final size = (box.maxWidth * 0.118).clamp(34.0, 72.0);
            final flash = ms < _kStrike - 10
                ? 0.0
                : ms < _kStrike + 10
                ? 0.1 * _seg(ms, _kStrike - 10, _kStrike + 10)
                : 0.1 * (1 - _seg(ms, _kStrike + 10, _kStrike + 200));
            return Stack(
              fit: .expand,
              children: [
                if (flash > 0) ColoredBox(color: PTColors.primary.withValues(alpha: flash)),
                if (ms < _kStrike)
                  Center(
                    child: _Leader(ms: ms, diameter: size * 5),
                  ),
                if (ms >= _kStrike)
                  CustomPaint(
                    painter: _ShockPainter(ms: ms, unit: size * 2.2),
                  ),
                Center(
                  child: Transform.scale(
                    // Drifts forward as it leaves, so the hand-off reads as
                    // passing through the wordmark into the app.
                    scale: 1 + 0.06 * exit,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      // Large text sizes and narrow windows shrink the lockup
                      // rather than overflow it.
                      child: FittedBox(
                        fit: .scaleDown,
                        child: Column(
                          mainAxisSize: .min,
                          children: [
                            _RollingWordmark(ms: ms, size: size),
                            SizedBox(height: size * 0.48),
                            _Eyebrow(ms: ms, size: size),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 84,
                  child: Center(
                    child: _Rail(
                      progress: _seg(ms, 0, _kExitStart),
                      width: math.min(200, box.maxWidth * 0.5),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The countdown leader: ring, crosshair, sweep hand and the numeral, which
/// snaps shut into the Beam at [_kStrike].
class _Leader extends StatelessWidget {
  const _Leader({required this.ms, required this.diameter});

  final double ms;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    final appear = _seg(ms, 0, 150, PTMotion.enter);
    final close = _seg(ms, _kCloseStart, _kStrike, const Cubic(0.6, 0, 0.9, 0.4));
    final sweep = _seg(ms, 0, _kSweepEnd, const Cubic(0.3, 0.1, 0.3, 1));
    return Opacity(
      opacity: appear,
      child: Transform.scale(
        scale: (1.15 - 0.15 * appear) * (1 - 0.94 * close),
        child: SizedBox.square(
          dimension: diameter,
          child: Stack(
            alignment: .center,
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _LeaderPainter(angle: sweep * _kSweepTurns * 2 * math.pi),
                ),
              ),
              for (final (a, b, numeral) in _kCountdown)
                if (ms >= a && ms <= b)
                  _Numeral(ms: ms, from: a, to: b, text: numeral, size: diameter * 0.28),
            ],
          ),
        ),
      ),
    );
  }
}

class _Numeral extends StatelessWidget {
  const _Numeral({
    required this.ms,
    required this.from,
    required this.to,
    required this.text,
    required this.size,
  });

  final double ms;
  final int from;
  final int to;
  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    final inT = _seg(ms, from, from + 60, PTMotion.enter);
    final outT = _seg(ms, to - 30, to);
    return Opacity(
      opacity: inT * (1 - outT),
      child: Transform.scale(
        scale: (1.5 - 0.5 * inT) * (1 - 0.3 * outT),
        child: Text(
          text,
          style: TextStyle(
            fontFamily: PTFonts.display,
            fontWeight: .w800,
            fontSize: size,
            height: 1,
            color: PTColors.accentSoft,
          ),
        ),
      ),
    );
  }
}

class _LeaderPainter extends CustomPainter {
  const _LeaderPainter({required this.angle});

  final double angle;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final reach = r + 24;
    final cross = Paint()
      ..color = PTColors.aisle
      ..strokeWidth = 1;
    canvas
      ..drawLine(c.translate(0, -reach), c.translate(0, reach), cross)
      ..drawLine(c.translate(-reach, 0), c.translate(reach, 0), cross)
      ..drawCircle(
        c,
        r,
        Paint()
          ..color = PTColors.rail
          ..style = .stroke
          ..strokeWidth = 1.5,
      )
      ..drawLine(
        c,
        c + Offset(math.sin(angle), -math.cos(angle)) * r,
        Paint()
          ..color = PTColors.primary
          ..strokeWidth = 2,
      );
  }

  @override
  bool shouldRepaint(_LeaderPainter old) => old.angle != angle;
}

/// Two shockwaves leave the strike point and fade as they grow.
class _ShockPainter extends CustomPainter {
  const _ShockPainter({required this.ms, required this.unit});

  final double ms;
  final double unit;

  static const _curve = Cubic(0.1, 0.7, 0.3, 1);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    for (final (start, grow, alpha) in [(_kStrike, 6.0, 0.6), (_kStrike + 120, 3.5, 0.35)]) {
      final p = _seg(ms, start, start + 1000, _curve);
      if (p <= 0 || p >= 1) continue;
      canvas.drawCircle(
        c,
        unit * (0.1 + (grow - 0.1) * p),
        Paint()
          ..color = PTColors.primary.withValues(alpha: alpha * (1 - p))
          ..style = .stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_ShockPainter old) => old.ms != ms || old.unit != unit;
}

/// `sync·together`, each glyph rolling up from behind its own baseline. The
/// dot is the Beam and pops instead of rolling.
class _RollingWordmark extends StatelessWidget {
  const _RollingWordmark({required this.ms, required this.size});

  final double ms;
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: PTFonts.display,
      fontSize: size,
      fontWeight: .w800,
      letterSpacing: -size * 0.035,
      height: 1,
      color: PTColors.fg,
    );
    return Semantics(
      label: 'SyncTogether',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: .min,
        children: [
          for (var i = 0; i < _kWord.length; i++)
            i == _kDotIndex
                ? _BeamDot(ms: ms, start: _kLettersStart + i * _kLetterStep, style: style)
                : _RollingGlyph(
                    ms: ms,
                    start: _kLettersStart + i * _kLetterStep,
                    glyph: _kWord[i],
                    style: style,
                  ),
        ],
      ),
    );
  }
}

class _RollingGlyph extends StatelessWidget {
  const _RollingGlyph({
    required this.ms,
    required this.start,
    required this.glyph,
    required this.style,
  });

  final double ms;
  final int start;
  final String glyph;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final p = _seg(ms, start, start + _kLetterRoll, PTMotion.arrive);
    final fade = _seg(ms, start, start + 200);
    return ClipRect(
      clipper: const _BaselineClip(),
      child: Opacity(
        opacity: fade,
        child: Transform.translate(
          offset: Offset(0, (1 - p) * style.fontSize! * 1.05),
          child: Text(glyph, style: style),
        ),
      ),
    );
  }
}

/// Clips only below the glyph box, so a letter rises from behind the line
/// while its overshoot above it is never cut off.
class _BaselineClip extends CustomClipper<Rect> {
  const _BaselineClip();

  @override
  Rect getClip(Size size) => Rect.fromLTRB(-size.width, -size.height, size.width * 2, size.height);

  @override
  bool shouldReclip(_BaselineClip old) => false;
}

class _BeamDot extends StatelessWidget {
  const _BeamDot({required this.ms, required this.start, required this.style});

  final double ms;
  final int start;
  final TextStyle style;

  // Strike, recoil, a smaller bounce, rest.
  static const _beats = [(0, 2.2), (160, 0.9), (300, 1.15), (450, 1.0)];

  double get _scale {
    final local = ms - start;
    if (local < 0) return 0;
    for (var i = 1; i < _beats.length; i++) {
      final (t0, s0) = _beats[i - 1];
      final (t1, s1) = _beats[i];
      if (local <= t1) return s0 + (s1 - s0) * Curves.easeInOut.transform((local - t0) / (t1 - t0));
    }
    return 1;
  }

  @override
  Widget build(BuildContext context) => Transform.scale(
    scale: _scale,
    child: Text('·', style: style.copyWith(color: PTColors.primary)),
  );
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow({required this.ms, required this.size});

  final double ms;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = _seg(ms, _kEyebrowStart, _kEyebrowStart + 350, PTMotion.enter);
    return Opacity(
      opacity: p,
      child: Transform.translate(
        offset: Offset(0, 8 * (1 - p)),
        child: Text(
          'NOW SHOWING · TOGETHER',
          style: TextStyle(
            fontFamily: PTFonts.mono,
            fontSize: size * 0.22,
            letterSpacing: size * 0.22 * 0.28,
            color: PTColors.fgMute,
          ),
        ),
      ),
    );
  }
}

/// A 1 px leader rail that fills while startup work runs behind the splash.
class _Rail extends StatelessWidget {
  const _Rail({required this.progress, required this.width});

  final double progress;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: 1,
    child: ColoredBox(
      color: PTColors.aisle,
      child: Align(
        alignment: .centerLeft,
        child: FractionallySizedBox(
          widthFactor: progress,
          heightFactor: 1,
          child: const ColoredBox(color: PTColors.primary),
        ),
      ),
    ),
  );
}
