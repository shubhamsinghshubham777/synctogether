import 'package:flutter/material.dart';

import '../platform.dart';

/// The one height every item in a header bar shares: chips, the account chip,
/// icon buttons and the bug button. Without a shared token each item took its
/// height from whatever it held (a 30 px avatar here, 13 px type there), so the
/// row read as a ragged skyline.
abstract final class PTBar {
  /// Pointer layouts: sits inside the 52 px marquee bar with 8 px above and below.
  static const double itemHeight = 36;

  /// Touch layouts. The drawn item is this tall; the hit area is still 44 px.
  static const double itemHeightTouch = 40;

  /// Largest an item may grow with the text on a desktop bar (52 px bar, 4 px
  /// margins). Touch headers are free to grow.
  static const double itemHeightDesktopMax = 44;

  /// Items grow with the text, capped, so the type never crowds its chip. All
  /// items scale by the same rule, which is what keeps them equal.
  static const double maxTextScale = 1.6;

  /// The height of one bar item. [touch] defaults to "this is not a desktop".
  static double height(BuildContext context, {bool? touch}) {
    final isTouch = touch ?? !isDesktop;
    final scaled = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: maxTextScale).scale(isTouch ? itemHeightTouch : itemHeight);
    return isTouch ? scaled : scaled.clamp(itemHeight, itemHeightDesktopMax);
  }
}

/// Gives [child] exactly the bar's item height (a tight constraint, so a chip's
/// surface fills it and its content centres inside). [square] also fixes the
/// width, for icon buttons and avatars. Every header item is wrapped in one, so
/// "all items are equally tall" is a single thing to assert.
class PTBarItem extends StatelessWidget {
  const PTBarItem({super.key, required this.child, this.square = false, this.touch});

  final Widget child;
  final bool square;
  final bool? touch;

  @override
  Widget build(BuildContext context) {
    final h = PTBar.height(context, touch: touch);
    return SizedBox(height: h, width: square ? h : null, child: child);
  }
}
