import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Where the coach mark's ring and card sit, worked out from the bug button's
/// real rectangle and the window, so nothing is ever drawn off-screen.
///
/// The ring hugs the button (outset [ringOutset]) and its one ripple grows to
/// [rippleOutset]; both are clamped by how much room the button really has,
/// because the button can sit 8 px under the top of a title bar. The card hangs
/// below the ring, never wider than the window less a margin, with its arrow
/// under the button's centre but kept clear of the card's rounded corners. When
/// the window is too short for the card to fit below (a phone on its side at a
/// large text size) it moves to the button's left instead, arrow on its right edge.
enum CoachSide { below, left }

class CoachGeometry {
  const CoachGeometry({
    required this.anchor,
    required this.ringOutset,
    required this.rippleOutset,
    required this.halo,
    required this.card,
    required this.side,
    required this.arrow,
    required this.maxHeight,
  });

  /// The button, in window coordinates.
  final Rect anchor;

  /// How far the still ring stands off the button.
  final double ringOutset;

  /// How far the ripple grows (at least [ringOutset]).
  final double rippleOutset;

  /// Width of the faint outer halo beside the ring, or 0 when there is no room.
  final double halo;

  /// The card, in window coordinates. Its height is [cardHeight] (0 until known).
  final Rect card;

  /// Which side of the button the card hangs on.
  final CoachSide side;

  /// The tallest the card may be from its top to the window's bottom margin. A
  /// card taller than this scrolls its text and keeps "Got it" in view.
  final double maxHeight;

  /// The arrow's centre along the card's top edge (from its left) when [side] is
  /// [CoachSide.below], or along its right edge (from its top) when [CoachSide.left].
  final double arrow;

  /// The whole area the ring can ever paint into. Always inside the window.
  Rect get ringArea => anchor.inflate(rippleOutset);

  /// Keep every painted pixel at least this far from a window edge.
  static const edgeMargin = 4.0;
  static const _ringOutset = 3.0;
  static const _maxRipple = 10.0;
  static const _haloWidth = 4.0;

  /// Space between the ring and the arrow's tip.
  static const ringGap = 8.0;

  /// A 12 px square turned 45 degrees reaches 8.5 px from its centre.
  static const arrowReach = 8.5;
  static const cardMargin = 12.0;
  static const cardWidth = 290.0;
  static const cornerClear = 20.0;

  /// The card's padding, its button and the gap between them.
  static const minCardHeight = 96.0;

  static CoachGeometry compute({
    required Rect anchor,
    required Size window,
    EdgeInsets safe = EdgeInsets.zero,
    double cardHeight = 0,
  }) {
    final room = [
      anchor.left - safe.left,
      anchor.top - safe.top,
      window.width - safe.right - anchor.right,
      window.height - safe.bottom - anchor.bottom,
    ].reduce(math.min);
    final fit = (room - edgeMargin).clamp(0.0, _maxRipple);
    final ring = math.min(_ringOutset, fit);
    final halo = fit - ring >= _haloWidth ? _haloWidth : 0.0;

    final minLeft = cardMargin + safe.left;
    final maxRight = window.width - cardMargin - safe.right;
    final minTop = cardMargin + safe.top;
    final maxBottom = window.height - cardMargin - safe.bottom;

    var width = math.min(cardWidth, math.max(0.0, maxRight - minLeft));
    var left = (anchor.right + 4 - width).clamp(minLeft, math.max(minLeft, maxRight - width));
    var top = anchor.bottom + ring + ringGap + arrowReach;
    var side = CoachSide.below;

    if (cardHeight > 0 && top + cardHeight > maxBottom) {
      // No room underneath: hang the card to the button's left instead.
      final right = anchor.left - ring - ringGap - arrowReach;
      final w = math.min(cardWidth, right - minLeft);
      if (w >= 200) {
        side = CoachSide.left;
        width = w;
        left = right - w;
        top = anchor.top.clamp(minTop, math.max(minTop, maxBottom - cardHeight)).toDouble();
      } else {
        // Nowhere better: keep it below but pull it up as far as the window allows.
        top = math.max(minTop, maxBottom - cardHeight);
      }
    }

    final double arrow;
    if (side == CoachSide.below) {
      arrow = (anchor.center.dx - left)
          .clamp(math.min(cornerClear, width / 2), math.max(width - cornerClear, width / 2))
          .toDouble();
    } else {
      arrow = (anchor.center.dy - top)
          .clamp(
            math.min(cornerClear, cardHeight / 2),
            math.max(cardHeight - cornerClear, cardHeight / 2),
          )
          .toDouble();
    }
    return CoachGeometry(
      anchor: anchor,
      ringOutset: ring,
      rippleOutset: fit,
      halo: halo,
      card: Rect.fromLTWH(left.toDouble(), top, width, cardHeight),
      side: side,
      arrow: arrow,
      // Unknown height: let the card lay out freely so it can be measured. Known:
      // never below what its button and padding need, or it could not lay out at all.
      maxHeight: cardHeight > 0 ? math.max(minCardHeight, maxBottom - top) : double.infinity,
    );
  }
}
