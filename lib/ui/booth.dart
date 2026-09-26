import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'pt_motion.dart';
import 'pt_theme.dart';

// Booth Light signature components: the ticket, the sync dot, the ready ring
// and the stamp. Every animation here is one-shot or runs only while the
// thing it describes is changing - nothing in this file keeps a ticker alive
// on an idle screen, because most of these sit beside playing video.

/// A ticket stub outline: a rectangle with a half-circle notch bitten out of
/// each short edge at mid-height (the Components board's ticket). The
/// perforation runs the full height at [stubInset] from the trailing edge.
///
/// A real [ShapeBorder] rather than a mask, so it clips, hit-tests and paints
/// its border through the normal decoration path - no saveLayer.
class TicketBorder extends OutlinedBorder {
  const TicketBorder({
    super.side,
    this.radius = PTRadius.panel,
    this.notchRadius = 10,
    required this.stubInset,
  });

  final double radius;
  final double notchRadius;

  /// Distance of the perforation from the trailing (right) edge.
  final double stubInset;

  Path _path(Rect rect) {
    final r = Radius.circular(radius);
    final body = Path()..addRRect(RRect.fromRectAndRadius(rect, r));
    final y = rect.center.dy;
    final notches = Path()
      ..addOval(Rect.fromCircle(center: Offset(rect.left, y), radius: notchRadius))
      ..addOval(Rect.fromCircle(center: Offset(rect.right, y), radius: notchRadius));
    return Path.combine(PathOperation.difference, body, notches);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _path(rect.deflate(side.strokeInset));

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    canvas.drawPath(_path(rect.deflate(side.strokeInset / 2)), side.toPaint());
  }

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.strokeInset);

  @override
  ShapeBorder scale(double t) => TicketBorder(
    side: side.scale(t),
    radius: radius * t,
    notchRadius: notchRadius * t,
    stubInset: stubInset * t,
  );

  @override
  TicketBorder copyWith({BorderSide? side, double? stubInset}) => TicketBorder(
    side: side ?? this.side,
    radius: radius,
    notchRadius: notchRadius,
    stubInset: stubInset ?? this.stubInset,
  );

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    if (a is TicketBorder) {
      return TicketBorder(
        side: BorderSide.lerp(a.side, side, t),
        radius: lerpDouble(a.radius, radius, t),
        notchRadius: lerpDouble(a.notchRadius, notchRadius, t),
        stubInset: lerpDouble(a.stubInset, stubInset, t),
      );
    }
    return super.lerpFrom(a, t);
  }

  static double lerpDouble(double a, double b, double t) => a + (b - a) * t;

  @override
  bool operator ==(Object other) =>
      other is TicketBorder &&
      other.side == side &&
      other.radius == radius &&
      other.notchRadius == notchRadius &&
      other.stubInset == stubInset;

  @override
  int get hashCode => Object.hash(side, radius, notchRadius, stubInset);
}

/// The dashed perforation between a ticket's body and its stub, painted over
/// the whole ticket at [inset] from the trailing edge. A foreground painter
/// rather than a child, so the ticket needs no intrinsic-height pass (which
/// would throw on any LayoutBuilder in the body).
class _Perforation extends CustomPainter {
  const _Perforation(this.color, this.inset, this.notch);

  final Color color;
  final double inset;
  final double notch;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    const dash = 4.0, gap = 4.0;
    final x = size.width - inset;
    // Edge to edge, a dash's width in from each end - the notches are on
    // the short sides now, not where the tear runs.
    final end = size.height - 4;
    for (var y = 4.0; y < end; y += dash + gap) {
      canvas.drawLine(Offset(x, y), Offset(x, math.min(y + dash, end)), paint);
    }
  }

  @override
  bool shouldRepaint(_Perforation old) =>
      old.color != color || old.inset != inset || old.notch != notch;
}

/// The signature object: a ticket with a body and a tear-off stub.
///
/// [paper] tickets are the one light surface in the app, reserved for what is
/// *live* (a room that's showing now) and for things people share. Everything
/// else is a dark ticket on the booth.
///
/// Motion: on hover the ticket lifts 2px and its edge catches the Beam; on
/// press it settles back. Both are implicit animations - nothing runs while
/// the pointer is elsewhere.
class PTTicket extends StatefulWidget {
  const PTTicket({
    super.key,
    required this.body,
    required this.stub,
    this.stubWidth = 104,
    this.paper = false,
    this.onTap,
    this.semanticLabel,
  });

  final Widget body;
  final Widget stub;
  final double stubWidth;
  final bool paper;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  State<PTTicket> createState() => _PTTicketState();
}

class _PTTicketState extends State<PTTicket> {
  static const _notch = 9.0;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onTap != null;
    final lit = _hovered && interactive;
    final fill = widget.paper ? PTColors.fg : PTColors.glassBase;
    final edge = widget.paper
        ? Colors.transparent
        : lit
        ? PTColors.primary.withValues(alpha: 0.7)
        : PTColors.rail;
    final ink = widget.paper ? PTColors.canvas : PTColors.fg;
    final duration = PTMotion.functional(context, PTMotion.hover);

    final ticket = AnimatedContainer(
      duration: duration,
      curve: PTMotion.enter,
      transform: Matrix4.translationValues(0, lit ? -2 : 0, 0),
      decoration: ShapeDecoration(
        color: fill,
        shape: TicketBorder(
          side: BorderSide(color: edge),
          notchRadius: _notch,
          stubInset: widget.stubWidth,
        ),
        shadows: lit ? PTColors.beamSpill : const [],
      ),
      child: CustomPaint(
        foregroundPainter: _Perforation(
          widget.paper ? PTColors.canvas.withValues(alpha: 0.25) : PTColors.rail,
          widget.stubWidth,
          _notch,
        ),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: ink),
          child: Row(
            children: [
              Expanded(child: widget.body),
              SizedBox(width: widget.stubWidth, child: widget.stub),
            ],
          ),
        ),
      ),
    );

    if (!interactive) return Semantics(label: widget.semanticLabel, child: ticket);
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: PTPressable(onTap: widget.onTap, child: ticket),
      ),
    );
  }
}

/// What the sync dot is saying.
enum SyncDotState {
  /// Everyone within tolerance. Beam, glowing.
  locked,

  /// We are correcting drift or recovering from a stall. Hollow Beam ring.
  catchingUp,

  /// The channel dropped. Signal, no glow.
  reconnecting,

  /// Nothing to sync (no media, or alone). Dim.
  idle,
}

/// The product's promise, made visible: one dot that reports the room's sync.
///
/// On every transition *into* [SyncDotState.locked] it beats twice - a
/// heartbeat that says "caught" - and then rests on a steady glow. It does
/// not pulse forever: a looping pulse would repaint every frame for the whole
/// film, which is exactly the idle cost this app refuses to pay beside video.
/// Colour changes between states are tweened.
class SyncDot extends StatefulWidget {
  const SyncDot({super.key, required this.state, this.size = 8});

  final SyncDotState state;
  final double size;

  /// Length of the arrival heartbeat (two beats).
  static const heartbeat = Duration(milliseconds: 900);

  @override
  State<SyncDot> createState() => _SyncDotState();
}

class _SyncDotState extends State<SyncDot> with SingleTickerProviderStateMixin {
  late final AnimationController _beat = AnimationController(
    vsync: this,
    duration: SyncDot.heartbeat,
  );

  @override
  void didUpdateWidget(SyncDot old) {
    super.didUpdateWidget(old);
    if (widget.state == .locked && old.state != .locked && !reducedMotion(context)) {
      _beat.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  Color get _color => switch (widget.state) {
    .locked || .catchingUp => PTColors.primary,
    .reconnecting => PTColors.dangerBorder,
    .idle => PTColors.away,
  };

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final hollow = widget.state == .catchingUp;
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: size * 2.5,
        child: Center(
          child: TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: _color),
            duration: PTMotion.functional(context, PTMotion.state),
            builder: (context, color, _) => AnimatedBuilder(
              animation: _beat,
              builder: (context, _) {
                // Two beats: sin^2 over two half-periods, gone by the end.
                final t = _beat.value;
                final beat = _beat.isAnimating ? math.pow(math.sin(t * 2 * math.pi), 2) : 0.0;
                final glow = widget.state == .locked ? 0.55 + 0.45 * beat : 0.0;
                return Transform.scale(
                  scale: 1 + 0.35 * beat,
                  child: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: .circle,
                      color: hollow ? Colors.transparent : color,
                      border: hollow ? Border.all(color: color!, width: size / 4) : null,
                      boxShadow: glow > 0
                          ? [
                              BoxShadow(
                                color: color!.withValues(alpha: glow * 0.8),
                                blurRadius: size * 1.5,
                              ),
                            ]
                          : null,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// A ring around an avatar that reports readiness (Cue), premium (Brass) or
/// nothing (Rail). The colour tweens between states, and becoming [ready]
/// sends one ripple outward - the room seeing you arrive.
class ReadyRing extends StatefulWidget {
  const ReadyRing({
    super.key,
    required this.child,
    required this.diameter,
    this.ready = false,
    this.premium = false,
    this.gap = 2,
    this.width = 2,
    this.clip = true,
  });

  final Widget child;
  final double diameter;

  /// False for a child that draws its own round shape and decorations (a
  /// [PTAvatar] with a crown or frame), which clipping would cut off.
  final bool clip;
  final bool ready;
  final bool premium;
  final double gap;
  final double width;

  @override
  State<ReadyRing> createState() => _ReadyRingState();
}

class _ReadyRingState extends State<ReadyRing> with SingleTickerProviderStateMixin {
  late final AnimationController _ripple = AnimationController(
    vsync: this,
    duration: PTMotion.entrance,
  );

  @override
  void didUpdateWidget(ReadyRing old) {
    super.didUpdateWidget(old);
    if (widget.ready && !old.ready && !reducedMotion(context)) _ripple.forward(from: 0);
  }

  @override
  void dispose() {
    _ripple.dispose();
    super.dispose();
  }

  Color get _ring => widget.ready
      ? PTColors.online
      : widget.premium
      ? PTColors.premium
      : PTColors.rail;

  @override
  Widget build(BuildContext context) {
    final outer = widget.diameter + 2 * (widget.gap + widget.width);
    return SizedBox.square(
      dimension: outer,
      child: Stack(
        alignment: .center,
        clipBehavior: Clip.none,
        children: [
          AnimatedBuilder(
            animation: _ripple,
            builder: (context, _) {
              if (!_ripple.isAnimating) return const SizedBox.shrink();
              final t = PTMotion.enter.transform(_ripple.value);
              return IgnorePointer(
                child: Container(
                  width: outer + 12 * t,
                  height: outer + 12 * t,
                  decoration: BoxDecoration(
                    shape: .circle,
                    border: Border.all(color: PTColors.online.withValues(alpha: 1 - t), width: 2),
                  ),
                ),
              );
            },
          ),
          TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: _ring),
            duration: PTMotion.functional(context, PTMotion.state),
            builder: (context, color, child) => Container(
              width: outer,
              height: outer,
              padding: EdgeInsets.all(widget.gap + widget.width),
              decoration: BoxDecoration(
                shape: .circle,
                border: Border.all(color: color!, width: widget.width),
              ),
              child: child,
            ),
            child: widget.clip ? ClipOval(child: widget.child) : widget.child,
          ),
        ],
      ),
    );
  }
}

/// An ink stamp - how achievements, streaks and the recap's superlatives are
/// marked. One colour, slightly rotated, a little imperfect.
///
/// It lands once: pressed down from 1.6x with the arrival overshoot, settling
/// into its [angle]. [animate] false (or reduce-motion) renders it already
/// inked, which is what a shelf of old badges wants.
class PTStamp extends StatefulWidget {
  const PTStamp({
    super.key,
    required this.child,
    this.color = PTColors.ember,
    this.angle = -0.14,
    this.size = 88,
    this.circle = true,
    this.animate = true,
    this.delay = Duration.zero,
  });

  final Widget child;
  final Color color;

  /// Resting rotation in radians.
  final double angle;
  final double size;
  final bool circle;
  final bool animate;
  final Duration delay;

  static const duration = Duration(milliseconds: 420);

  @override
  State<PTStamp> createState() => _PTStampState();
}

class _PTStampState extends State<PTStamp> {
  @override
  Widget build(BuildContext context) {
    return StampIn(
      angle: widget.angle,
      animate: widget.animate,
      delay: widget.delay,
      child: Container(
        width: widget.size,
        height: widget.size,
        alignment: .center,
        decoration: BoxDecoration(
          shape: widget.circle ? .circle : .rectangle,
          borderRadius: widget.circle ? null : BorderRadius.circular(PTRadius.panel),
          border: Border.all(color: widget.color, width: widget.size / 32),
        ),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: widget.color),
          textAlign: .center,
          child: IconTheme.merge(
            data: IconThemeData(color: widget.color),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// The stamp's motion on its own, for art that brings its own look (badge
/// renders): pressed down from 1.6x with the arrival overshoot, settling into
/// [angle].
///
/// [delay] is folded into the controller as a leading [Interval] rather than
/// a timer, so there is nothing to cancel and nothing for a test to leak.
class StampIn extends StatefulWidget {
  const StampIn({
    super.key,
    required this.child,
    this.angle = 0,
    this.animate = true,
    this.delay = Duration.zero,
  });

  final Widget child;
  final double angle;
  final bool animate;
  final Duration delay;

  @override
  State<StampIn> createState() => _StampInState();
}

class _StampInState extends State<StampIn> with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: widget.delay + PTStamp.duration,
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _press,
    curve: Interval(
      widget.delay.inMicroseconds / (widget.delay + PTStamp.duration).inMicroseconds,
      1,
    ),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!widget.animate || reducedMotion(context)) {
      _press.value = 1;
    } else {
      _press.forward();
    }
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _t,
        child: widget.child,
        builder: (context, child) {
          final t = _t.value;
          final scale = 1.6 - 0.6 * PTMotion.arrive.transform(t);
          return Opacity(
            opacity: Curves.easeOut.transform((t * 2).clamp(0.0, 1.0)),
            child: Transform.rotate(
              angle: widget.angle * PTMotion.enter.transform(t),
              child: Transform.scale(scale: scale, child: child),
            ),
          );
        },
      ),
    );
  }
}

/// A one-shot burst of flat paper confetti - Beam, Signal, Cue and Brass
/// rectangles thrown up from [origin] and falling under gravity, the way a
/// ticket stub gets torn and tossed.
///
/// Cheap by construction: one [AnimationController] drives one
/// [CustomPainter] over a precomputed list (no per-piece widgets, no
/// allocation per frame), inside its own [RepaintBoundary]. When the burst
/// ends the controller has stopped and the painter draws nothing, so an idle
/// page pays zero. Under reduce motion nothing is thrown at all.
class PTConfetti extends StatefulWidget {
  const PTConfetti({
    super.key,
    this.pieces = 60,
    this.duration = const Duration(milliseconds: 1700),
    this.origin = const Alignment(0, -0.1),
    this.seed = 7,
  });

  final int pieces;
  final Duration duration;

  /// Where the burst starts, in the widget's own box.
  final Alignment origin;

  /// Fixed so the burst is identical every run (and in screenshots).
  final int seed;

  @override
  State<PTConfetti> createState() => _PTConfettiState();
}

class _PTConfettiState extends State<PTConfetti> with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(vsync: this, duration: widget.duration);
  late final List<_Piece> _pieces = _throw();
  bool _started = false;

  List<_Piece> _throw() {
    final rng = math.Random(widget.seed);
    const inks = [PTColors.primary, PTColors.ember, PTColors.online, PTColors.premium];
    return [
      for (var i = 0; i < widget.pieces; i++)
        _Piece(
          // Mostly upward, fanned about 70 degrees either side.
          angle: -math.pi / 2 + (rng.nextDouble() - 0.5) * 2.4,
          speed: 0.55 + rng.nextDouble() * 0.75,
          spin: (rng.nextDouble() - 0.5) * 14,
          flutter: rng.nextDouble() * math.pi * 2,
          w: 6 + rng.nextDouble() * 6,
          h: 3 + rng.nextDouble() * 4,
          color: inks[i % inks.length],
        ),
    ];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!reducedMotion(context)) _t.forward();
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _ConfettiPainter(_t, _pieces, widget.origin),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _Piece {
  const _Piece({
    required this.angle,
    required this.speed,
    required this.spin,
    required this.flutter,
    required this.w,
    required this.h,
    required this.color,
  });

  final double angle;
  final double speed;
  final double spin;
  final double flutter;
  final double w;
  final double h;
  final Color color;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.t, this.pieces, this.origin) : super(repaint: t);

  final Animation<double> t;
  final List<_Piece> pieces;
  final Alignment origin;
  final Paint _paint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    final p = t.value;
    if (p == 0 || p == 1) return;
    final start = origin.alongSize(size);
    // Distances scale with the box, so the burst fills a phone and a desktop
    // alike; gravity is quadratic in time, the launch linear.
    final reach = size.shortestSide * 0.9;
    final fade = p < 0.75 ? 1.0 : (1 - p) / 0.25;
    for (final c in pieces) {
      final dx = math.cos(c.angle) * c.speed * reach * p;
      final dy = math.sin(c.angle) * c.speed * reach * p + reach * 1.4 * p * p;
      canvas.save();
      canvas.translate(start.dx + dx + math.sin(c.flutter + p * 9) * 8, start.dy + dy);
      canvas.rotate(c.spin * p);
      _paint.color = c.color.withValues(alpha: fade);
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: c.w, height: c.h), _paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.pieces != pieces || old.origin != origin;
}
