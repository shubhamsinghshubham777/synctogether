import 'package:flutter/material.dart';

import 'pt_motion.dart';

/// Shows and hides [child] with a size + fade (and an optional small slide)
/// instead of popping it in and out of the layout.
///
/// The conditional pieces of a screen - a banner, a strip, an error line - used
/// to be `if (cond) Widget`, which moves everything beneath them by the piece's
/// whole height in one frame. Here the piece folds along [axis] over
/// [duration] (reduce-motion halves it), its neighbours follow the eased size,
/// and while it is hidden it is out of focus, semantics and hit testing.
///
/// Cost: one controller, started only when [visible] flips; the child is built
/// once and reused each frame (only the clip/align/opacity wrappers update),
/// and once fully hidden the child is not mounted at all. It starts in its
/// settled state, so the first frame never animates.
class PTReveal extends StatefulWidget {
  const PTReveal({
    super.key,
    required this.visible,
    required this.child,
    this.axis = Axis.vertical,
    this.alignment = Alignment.topCenter,
    this.duration = PTMotion.state,
    this.slide = 0,
  });

  final bool visible;
  final Widget child;

  /// The axis the size animates along.
  final Axis axis;

  /// Which edge the child stays pinned to while it unfolds.
  final Alignment alignment;
  final Duration duration;

  /// Logical pixels the child travels through on the way in (towards its
  /// resting place from the side opposite [alignment] along [axis]). 0 = none.
  final double slide;

  @override
  State<PTReveal> createState() => _PTRevealState();
}

class _PTRevealState extends State<PTReveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: widget.visible ? 1 : 0,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: PTMotion.emphasized,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = PTMotion.functional(context, widget.duration);
  }

  @override
  void didUpdateWidget(PTReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.duration != oldWidget.duration) {
      _controller.duration = PTMotion.functional(context, widget.duration);
    }
    if (widget.visible != oldWidget.visible) {
      widget.visible ? _controller.forward() : _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vertical = widget.axis == Axis.vertical;
    // The wrapper structure never changes between frames, so a stateful child
    // keeps its state through the whole fold.
    return AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (context, child) {
        final t = _curve.value;
        if (t <= 0 && !widget.visible) return const SizedBox.shrink();
        Widget result = child!;
        if (widget.slide != 0) {
          final dir = vertical ? -widget.alignment.y : -widget.alignment.x;
          final shift = (1 - t) * widget.slide * (dir == 0 ? 1 : dir.sign);
          result = Transform.translate(
            offset: vertical ? Offset(0, shift) : Offset(shift, 0),
            child: result,
          );
        }
        return ExcludeFocus(
          excluding: !widget.visible,
          child: ExcludeSemantics(
            excluding: !widget.visible,
            child: IgnorePointer(
              ignoring: !widget.visible,
              child: ClipRect(
                child: Align(
                  alignment: widget.alignment,
                  heightFactor: vertical ? t : null,
                  widthFactor: vertical ? null : t,
                  child: Opacity(opacity: t.clamp(0.0, 1.0), child: result),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
