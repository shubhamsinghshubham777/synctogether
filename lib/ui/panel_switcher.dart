import 'package:flutter/widgets.dart';

import 'pt_motion.dart';

/// Swaps one keyed panel for another as a single, coordinated motion.
///
/// The plain `AnimatedSize` + `AnimatedSwitcher` pairing is jerky: the outgoing
/// panel stays in the stack at its full height until its fade ends, so the
/// height cannot start animating until then - fade first, then a lurch. It also
/// cross-fades the two panels on top of each other, so their text overlaps.
///
/// Here the outgoing panel is taken out of layout the moment the swap starts
/// (pinned to the top, clipped by the size animation, not hit-testable) and
/// fades out quickly, while the height tweens to the new panel's size over the
/// same [PTMotion.panel] beat and the incoming panel fades in just behind it -
/// out, then in, never both at once. Give each panel a distinct `ValueKey`.
class PTPanelSwitcher extends StatelessWidget {
  const PTPanelSwitcher({super.key, required this.child});

  /// The current panel; its key decides when a swap happens.
  final Widget child;

  /// How long the outgoing panel takes to clear. Short, so the two never share the screen.
  static const outgoing = PTMotion.tap;

  /// Where in the beat the incoming panel starts to appear.
  static const incomingStart = 0.3;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: PTMotion.functional(context, PTMotion.panel),
      curve: PTMotion.emphasized,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: PTMotion.functional(context, PTMotion.panel),
        reverseDuration: PTMotion.functional(context, outgoing),
        switchInCurve: const Interval(incomingStart, 1, curve: PTMotion.enter),
        switchOutCurve: PTMotion.exit,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topCenter,
          children: [
            // Out of layout: only the incoming panel sizes the stack, so the
            // height animation begins on the first frame.
            for (final old in previous)
              Positioned(top: 0, left: 0, right: 0, child: IgnorePointer(child: old)),
            ?current,
          ],
        ),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, -0.03), end: Offset.zero).animate(animation),
            child: child,
          ),
        ),
        child: child,
      ),
    );
  }
}
