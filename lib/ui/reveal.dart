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

/// A [PTReveal] for something that is only there on some condition and whose words
/// come from live state: it keeps what it last showed, so it folds shut with its
/// content intact (a link field whose controller was just cleared, a message whose
/// error just went away) instead of blanking first.
///
/// [gap] is the space above it, carried inside the fold: put a PTRevealKeep in a column
/// with no `spacing`, so a hidden one leaves no gap behind. Group the fold with the
/// widget above it in a nested column when the parent has spacing.
class PTRevealKeep extends StatefulWidget {
  const PTRevealKeep({
    super.key,
    required this.visible,
    required this.child,
    this.gap = 0,
    this.axis = Axis.vertical,
    this.alignment = Alignment.topCenter,
    this.slide = 0,
  });

  final bool visible;
  final Widget child;
  final double gap;
  final Axis axis;
  final Alignment alignment;
  final double slide;

  /// The same fold with its gap set (what [PTColumn] does for its children).
  PTRevealKeep withGap(double gap) => PTRevealKeep(
    key: key,
    visible: visible,
    gap: gap,
    axis: axis,
    alignment: alignment,
    slide: slide,
    child: child,
  );

  @override
  State<PTRevealKeep> createState() => _PTRevealKeepState();
}

class _PTRevealKeepState extends State<PTRevealKeep> {
  Widget? _last;

  @override
  Widget build(BuildContext context) {
    if (widget.visible) _last = widget.child;
    return PTReveal(
      visible: widget.visible,
      axis: widget.axis,
      alignment: widget.alignment,
      slide: widget.slide,
      child: Padding(
        padding: widget.axis == Axis.vertical
            ? EdgeInsets.only(top: widget.gap)
            : EdgeInsets.only(left: widget.gap),
        child: _last ?? widget.child,
      ),
    );
  }
}

/// A [Column] with `spacing` that understands folds: a [PTRevealKeep] child carries
/// its gap above it inside the fold, so while it is hidden it leaves no spacing
/// behind, and as it opens the space opens with it. Use it in place of
/// `Column(spacing: n, ...)` wherever a child comes and goes.
class PTColumn extends StatelessWidget {
  const PTColumn({
    super.key,
    required this.spacing,
    required this.children,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
    this.mainAxisSize = MainAxisSize.max,
  });

  final double spacing;
  final List<Widget> children;
  final CrossAxisAlignment crossAxisAlignment;
  final MainAxisSize mainAxisSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: crossAxisAlignment,
      mainAxisSize: mainAxisSize,
      children: [
        for (final (i, child) in children.indexed)
          if (child is PTRevealKeep)
            child.withGap(i == 0 ? 0 : spacing)
          else ...[
            if (i > 0) SizedBox(height: spacing),
            child,
          ],
      ],
    );
  }
}
