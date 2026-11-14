import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'buttons.dart';
import 'coach_geometry.dart';
import 'coach_scrim.dart';
import 'pt_motion.dart';
import 'pt_theme.dart';

/// How a coach mark ended, so each caller can count only what it cares about.
enum CoachEnd {
  /// The card's primary button.
  done,

  /// The card's secondary text button ("Not now").
  skipped,

  /// A tap on the dim, or Escape.
  dismissed,

  /// A tap on the lit target itself. The target still gets the tap.
  target,
}

/// A coach mark: the window dims except for one lit control, with a ring round
/// it and a card beside it. Shared by the bug-button hint and the first-night
/// onboarding marks.
///
/// Everything is placed from the target's real rectangle (see [CoachGeometry]),
/// so the ring and the card stay inside the window wherever the control sits.
/// The ripple plays once (a looping pulse would repaint forever); reduce-motion
/// draws the ring still and shortens the fade.
///
/// It is a hint, not a modal: a tap on the dim, Escape or either card button
/// ends it, and a tap on the lit control ends it too and still reaches the
/// control. It must sit in a full-window [Stack] (it positions itself).
class CoachMark extends StatefulWidget {
  const CoachMark({
    super.key,
    required this.anchor,
    required this.title,
    required this.body,
    required this.onEnd,
    this.doneLabel = 'Got it',
    this.kicker,
    this.skipLabel,
    this.step,
    this.steps,
  });

  /// The lit control's rectangle in window coordinates, or null before it has
  /// been laid out. Read after every frame, so a move is followed.
  final Rect? Function() anchor;

  final String title;
  final String body;
  final String doneLabel;

  /// A small mono line above the title ("START HERE", "2 OF 3 · ...").
  final String? kicker;

  /// A quiet text button on the card's left ("Not now"). None when null.
  final String? skipLabel;

  /// 1-based position in a sequence, drawn as dots when [steps] is over 1.
  final int? step;
  final int? steps;

  /// Called once the fade-out finishes.
  final ValueChanged<CoachEnd> onEnd;

  @override
  State<CoachMark> createState() => _CoachMarkState();
}

class _CoachMarkState extends State<CoachMark> with SingleTickerProviderStateMixin {
  Rect? _anchor;
  final _cardKey = GlobalKey();
  double _cardHeight = 0;
  late final AnimationController _fade = AnimationController(vsync: this);
  bool _started = false;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    _measure();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Functional motion: shorter under reduce-motion, never removed.
    _fade.animateTo(
      1,
      duration: PTMotion.functional(context, PTMotion.state),
      curve: PTMotion.enter,
    );
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _fade.dispose();
    super.dispose();
  }

  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.escape || _closing) return false;
    _close(CoachEnd.dismissed);
    return true;
  }

  /// Fades the dim and the card away, then tells the caller.
  void _close(CoachEnd end) {
    if (_closing) return;
    _closing = true;
    _fade
        .animateBack(
          0,
          duration: PTMotion.functional(context, PTMotion.hover),
          curve: PTMotion.exit,
        )
        .whenComplete(() {
          if (mounted) widget.onEnd(end);
        });
  }

  @override
  void didUpdateWidget(CoachMark old) {
    super.didUpdateWidget(old);
    _measure();
  }

  /// The target is laid out before this widget builds, but its rectangle is only
  /// readable once the frame is done; read it again then so a move (a resize, a
  /// different header) is followed.
  void _measure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final now = widget.anchor();
      final h = (_cardKey.currentContext?.findRenderObject() as RenderBox?)?.size.height ?? 0;
      if (now != _anchor || (h - _cardHeight).abs() > 0.5) {
        setState(() {
          _anchor = now;
          _cardHeight = h;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final anchor = _anchor ?? widget.anchor();
    if (anchor == null) return const SizedBox.shrink();
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    // A keyboard that is up counts as the bottom edge of the window.
    final keys = MediaQuery.viewInsetsOf(context).bottom;
    final geo = CoachGeometry.compute(
      anchor: anchor,
      window: size,
      safe: pad.copyWith(bottom: keys > pad.bottom ? keys : pad.bottom),
      cardHeight: _cardHeight,
    );
    final still = reducedMotion(context);
    final area = geo.ringArea;
    final lit = geo.anchor.inflate(geo.ringOutset + CoachScrim.holeGap);
    final hole = RRect.fromRectAndRadius(
      lit,
      Radius.circular(PTRadius.control + geo.ringOutset + CoachScrim.holeGap),
    );
    return Stack(
      children: [
        Positioned.fill(
          child: CoachScrim(fade: _fade, hole: hole, onTap: () => _close(CoachEnd.dismissed)),
        ),
        // The lit control is the one place the dim lets taps through. This only
        // listens: the control still gets the tap, and the mark ends with it.
        Positioned.fromRect(
          rect: lit,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => _close(CoachEnd.target),
          ),
        ),
        Positioned.fromRect(
          rect: area,
          child: IgnorePointer(
            child: FadeTransition(
              opacity: _fade,
              child: TweenAnimationBuilder<double>(
                key: const ValueKey('coach-ring'),
                tween: Tween(begin: still ? 1 : 0, end: 1),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, t, _) => CustomPaint(
                  painter: _RingPainter(geo: geo, ripple: t),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: geo.card.left,
          top: geo.card.top,
          width: geo.card.width,
          // Invisible for the one frame it takes to measure the card, so it never
          // flashes in a spot it then leaves.
          child: Opacity(
            opacity: _cardHeight > 0 ? 1 : 0,
            child: FadeTransition(
              opacity: _fade,
              child: PTEntrance(
                offset: -6,
                duration: PTMotion.state,
                child: _CoachCard(
                  key: _cardKey,
                  side: geo.side,
                  arrow: geo.arrow,
                  maxHeight: geo.maxHeight,
                  kicker: widget.kicker,
                  title: widget.title,
                  body: widget.body,
                  doneLabel: widget.doneLabel,
                  skipLabel: widget.skipLabel,
                  step: widget.step,
                  steps: widget.steps,
                  onDone: () => _close(CoachEnd.done),
                  onSkip: () => _close(CoachEnd.skipped),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The still ring, its faint halo (only where there is room) and the single
/// ripple. Paints inside [CoachGeometry.ringArea], which is inside the window.
class _RingPainter extends CustomPainter {
  _RingPainter({required this.geo, required this.ripple});

  final CoachGeometry geo;

  /// 0 at the start of the ripple, 1 when it has faded out.
  final double ripple;

  RRect _ring(double outset) => RRect.fromRectAndRadius(
    geo.anchor.inflate(outset).shift(-geo.ringArea.topLeft),
    Radius.circular(PTRadius.control + outset),
  );

  @override
  void paint(Canvas canvas, Size size) {
    final o = geo.ringOutset;
    if (geo.halo > 0) {
      canvas.drawRRect(
        _ring(o + geo.halo / 2 + 0.75),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = geo.halo
          ..color = PTColors.primary.withValues(alpha: 0.16),
      );
    }
    canvas.drawRRect(
      _ring(o),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = PTColors.primary,
    );
    if (ripple < 1 && geo.rippleOutset > o) {
      canvas.drawRRect(
        _ring(o + (geo.rippleOutset - o) * ripple),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = PTColors.primary.withValues(alpha: 0.6 * (1 - ripple)),
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.ripple != ripple || old.geo != geo;
}

class _CoachCard extends StatelessWidget {
  const _CoachCard({
    super.key,
    required this.side,
    required this.arrow,
    required this.maxHeight,
    required this.title,
    required this.body,
    required this.doneLabel,
    required this.onDone,
    required this.onSkip,
    this.kicker,
    this.skipLabel,
    this.step,
    this.steps,
  });

  final CoachSide side;
  final double arrow;
  final double maxHeight;
  final String? kicker;
  final String title;
  final String body;
  final String doneLabel;
  final String? skipLabel;
  final int? step;
  final int? steps;
  final VoidCallback onDone;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final kicker = this.kicker;
    final skip = skipLabel;
    final step = this.step, steps = this.steps;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: PTColors.glassBase,
              border: Border.all(color: PTColors.rail),
              borderRadius: BorderRadius.circular(PTRadius.panel),
            ),
            child: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .start,
              spacing: 8,
              children: [
                // The words scroll if the window is shorter than the card; the
                // buttons below them never leave the screen.
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: .start,
                      spacing: 8,
                      children: [
                        if (kicker != null)
                          Text(kicker, style: PTText.label.copyWith(fontSize: 10)),
                        Text(title, style: PTText.cardHeading.copyWith(fontSize: 17)),
                        Text(
                          body,
                          style: PTText.body.copyWith(
                            fontSize: 13,
                            color: PTColors.fgDim,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: [
                    // A quiet text link (board 87): the card is 290 px wide and the
                    // primary keeps its full label beside it.
                    if (skip != null)
                      // Takes all the free space itself (left-aligned), so it only
                      // ever shortens when the card truly has no room.
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: onSkip,
                            style: TextButton.styleFrom(
                              foregroundColor: PTColors.fgDim,
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                            ),
                            child: Text(skip, maxLines: 1, overflow: .ellipsis),
                          ),
                        ),
                      )
                    else ...[
                      if (step != null && steps != null && steps > 1)
                        CoachDots(step: step, steps: steps),
                      const Spacer(),
                    ],
                    PTButton(label: doneLabel, height: 34, expand: false, onPressed: onDone),
                  ],
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: side == CoachSide.below ? arrow - 6 : null,
          right: side == CoachSide.left ? -6 : null,
          top: side == CoachSide.below ? -6 : arrow - 6,
          child: Transform.rotate(
            angle: 0.785398,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: PTColors.glassBase,
                // The two edges that face away from the card carry the hairline.
                border: side == CoachSide.below
                    ? const Border(
                        left: BorderSide(color: PTColors.rail),
                        top: BorderSide(color: PTColors.rail),
                      )
                    : const Border(
                        right: BorderSide(color: PTColors.rail),
                        top: BorderSide(color: PTColors.rail),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Progress dots for a short sequence: done and current ones in Beam, the rest
/// on the Rail. Each dot's colour glides when the step changes.
class CoachDots extends StatelessWidget {
  const CoachDots({super.key, required this.step, required this.steps});

  /// 1-based.
  final int step;
  final int steps;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Step $step of $steps',
      child: Row(
        mainAxisSize: .min,
        spacing: 6,
        children: [
          for (var i = 1; i <= steps; i++)
            AnimatedContainer(
              duration: PTMotion.functional(context, PTMotion.state),
              curve: PTMotion.enter,
              width: 18,
              height: 4,
              decoration: BoxDecoration(
                color: i <= step ? PTColors.primary : PTColors.rail,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }
}
