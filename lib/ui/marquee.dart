import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'pt_motion.dart';

/// One line of text that fits its box or scrolls to show all of itself.
///
/// A name that fits is plain centred-or-start-aligned text. One that does not
/// holds at its start for [pause], scrolls left at [velocity] pixels a second
/// until its second copy has taken its place, and starts over - a seamless loop,
/// so the whole of a long room name is always on its way past. Under
/// reduce-motion it never moves and is ellipsized instead.
///
/// Cheap by construction: one controller, only while the text overflows; the
/// two copies are laid out once and the loop only moves a transform. The scroll
/// stops with the tree (`TickerMode`), so it costs nothing offstage. One
/// semantics label, the text itself. The second copy is a `RichText`, so a
/// finder for the text sees one widget.
class PTMarquee extends StatefulWidget {
  const PTMarquee(
    this.text, {
    super.key,
    required this.style,
    this.textAlign = TextAlign.start,
    this.pause = const Duration(milliseconds: 1600),
    this.velocity = 38,
    this.gap = 48,
  });

  /// Whether long text scrolls. Off under `flutter test`, where an animation
  /// that never ends would keep `pumpAndSettle` from ever settling and the
  /// layout matrix measures the static (ellipsized) form; the marquee's own
  /// tests turn it on.
  static bool animate = !kIsWeb && Platform.environment['FLUTTER_TEST'] != 'true';

  final String text;
  final TextStyle style;

  /// Where text that fits sits in its box.
  final TextAlign textAlign;

  /// How long the start of the text is held before each scroll.
  final Duration pause;

  /// Logical pixels per second.
  final double velocity;

  /// Space between the end of one copy and the start of the next.
  final double gap;

  @override
  State<PTMarquee> createState() => _PTMarqueeState();
}

class _PTMarqueeState extends State<PTMarquee> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double _travel = 0;
  double _holdShare = 0;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Starts, retimes or stops the loop for a text of [width] in a box of
  /// [available]. Called from layout, so it only touches the controller.
  void _sync(double width, double available, bool still) {
    final overflows = width > available + 0.5 && !still;
    if (!overflows) {
      if (_running) {
        _running = false;
        _controller.stop();
      }
      return;
    }
    final travel = width + widget.gap;
    final scroll = Duration(milliseconds: (travel / widget.velocity * 1000).round());
    final total = scroll + widget.pause;
    final share = widget.pause.inMilliseconds / total.inMilliseconds;
    if (_running && travel == _travel && total == _controller.duration) return;
    _travel = travel;
    _holdShare = share;
    _running = true;
    _controller
      ..duration = total
      ..repeat();
  }

  @override
  Widget build(BuildContext context) {
    final still = reducedMotion(context) || !PTMarquee.animate;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          textDirection: direction,
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        final width = painter.width;
        final height = painter.height;
        painter.dispose();
        final available = box.maxWidth;
        // Defer the controller change out of layout.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _sync(width, available, still);
        });
        if (width <= available + 0.5 || still || !available.isFinite) {
          return Text(
            widget.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: widget.textAlign,
            style: widget.style,
          );
        }
        final copy = Text(widget.text, maxLines: 1, softWrap: false, style: widget.style);
        final second = RichText(
          maxLines: 1,
          softWrap: false,
          textScaler: scaler,
          text: TextSpan(text: widget.text, style: widget.style),
        );
        final strip = RepaintBoundary(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              copy,
              SizedBox(width: widget.gap),
              ExcludeSemantics(child: second),
            ],
          ),
        );
        return Semantics(
          label: widget.text,
          excludeSemantics: true,
          // Exactly one line tall: an OverflowBox fills whatever height it is
          // offered, and in a column with unbounded height that is infinity.
          child: SizedBox(
            height: height,
            child: ClipRect(
              child: OverflowBox(
                alignment: AlignmentDirectional.centerStart,
                maxWidth: double.infinity,
                child: AnimatedBuilder(
                  animation: _controller,
                  child: strip,
                  builder: (context, child) {
                    final t = _controller.value;
                    final moved = t <= _holdShare ? 0.0 : (t - _holdShare) / (1 - _holdShare);
                    final dx = -math.min(1.0, moved) * _travel;
                    return Transform.translate(
                      offset: Offset(direction == TextDirection.rtl ? -dx : dx, 0),
                      child: child,
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
