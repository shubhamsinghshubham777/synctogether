import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/feedback/discovery/coach_geometry.dart';

void main() {
  const m = CoachGeometry.edgeMargin;

  void expectInside(CoachGeometry g, Size window, {EdgeInsets safe = EdgeInsets.zero}) {
    final bounds = Rect.fromLTRB(
      safe.left + m,
      safe.top + m,
      window.width - safe.right - m,
      window.height - safe.bottom - m,
    );
    final ring = g.ringArea;
    expect(ring.left, greaterThanOrEqualTo(bounds.left - 1e-9), reason: 'ring left');
    expect(ring.top, greaterThanOrEqualTo(bounds.top - 1e-9), reason: 'ring top');
    expect(ring.right, lessThanOrEqualTo(bounds.right + 1e-9), reason: 'ring right');
    expect(ring.bottom, lessThanOrEqualTo(bounds.bottom + 1e-9), reason: 'ring bottom');
    final card = g.card;
    expect(card.left, greaterThanOrEqualTo(safe.left + CoachGeometry.cardMargin - 1e-9));
    expect(
      card.right,
      lessThanOrEqualTo(window.width - safe.right - CoachGeometry.cardMargin + 1e-9),
    );
    expect(g.arrow, inInclusiveRange(0, g.side == CoachSide.below ? card.width : card.height));
    if (card.height > 0) {
      expect(card.top, greaterThanOrEqualTo(safe.top + CoachGeometry.cardMargin - 1e-9));
      expect(
        card.bottom,
        lessThanOrEqualTo(window.height - safe.bottom - CoachGeometry.cardMargin + 1e-9),
        reason: 'card bottom',
      );
    }
  }

  group('ring and card stay inside the window', () {
    test('macOS title bar: 36 px button, 8 px under the top, 14 px from the right', () {
      const window = Size(1280, 800);
      final g = CoachGeometry.compute(anchor: const Rect.fromLTWH(1230, 8, 36, 36), window: window);
      expectInside(g, window);
      expect(g.ringOutset, 3);
      // The old ring was 54 px square on a 36 px button: 9 px out, 1 px past the top.
      expect(g.rippleOutset, lessThan(9));
    });

    test('Windows title bar: button before the 138 px caption buttons', () {
      const window = Size(1280, 800);
      final g = CoachGeometry.compute(anchor: const Rect.fromLTWH(1090, 8, 36, 36), window: window);
      expectInside(g, window);
    });

    test('phone: 40 px button under a 47 px status bar', () {
      const window = Size(390, 844);
      const safe = EdgeInsets.only(top: 47, bottom: 34);
      final g = CoachGeometry.compute(
        anchor: const Rect.fromLTWH(290, 55, 40, 40),
        window: window,
        safe: safe,
      );
      expectInside(g, window, safe: safe);
      expect(g.ringOutset, 3);
    });

    test('cover display and a side inset (fold / cutout)', () {
      const window = Size(360, 374);
      const safe = EdgeInsets.fromLTRB(24, 0, 24, 0);
      final g = CoachGeometry.compute(
        anchor: const Rect.fromLTWH(290, 10, 36, 36),
        window: window,
        safe: safe,
      );
      expectInside(g, window, safe: safe);
    });

    test('a button flush against the top draws no ring outside the window', () {
      const window = Size(800, 600);
      final g = CoachGeometry.compute(anchor: const Rect.fromLTWH(700, 0, 36, 36), window: window);
      expect(g.ringOutset, 0);
      expect(g.rippleOutset, 0);
      expect(g.halo, 0);
      expect(g.ringArea.top, greaterThanOrEqualTo(0));
    });

    test('a button near the right edge keeps its ring inside', () {
      const window = Size(800, 600);
      final g = CoachGeometry.compute(anchor: const Rect.fromLTWH(750, 40, 40, 40), window: window);
      expectInside(g, window);
    });

    test('the halo needs room and is dropped without it', () {
      const window = Size(800, 600);
      final roomy = CoachGeometry.compute(
        anchor: const Rect.fromLTWH(400, 100, 40, 40),
        window: window,
      );
      expect(roomy.halo, 4);
      final tight = CoachGeometry.compute(
        anchor: const Rect.fromLTWH(700, 8, 36, 36),
        window: window,
      );
      expect(tight.halo, 0);
    });
  });

  group('the card', () {
    test('hangs 8 px of air below the ring, to the arrow tip', () {
      final g = CoachGeometry.compute(
        anchor: const Rect.fromLTWH(1230, 8, 36, 36),
        window: const Size(1280, 800),
      );
      final ringBottom = g.anchor.bottom + g.ringOutset;
      expect(g.card.top - CoachGeometry.arrowReach - ringBottom, CoachGeometry.ringGap);
    });

    test('is right-aligned to the button and 290 px wide when there is room', () {
      final g = CoachGeometry.compute(
        anchor: const Rect.fromLTWH(1230, 8, 36, 36),
        window: const Size(1280, 800),
      );
      expect(g.card.width, 290);
      // 4 px past the button, but never closer than 12 px to the window edge.
      expect(g.card.right, 1280 - CoachGeometry.cardMargin);
      // The arrow sits under the button's centre.
      expect(g.card.left + g.arrow, closeTo(1248, 1e-9));
    });

    test('shrinks to the window less a 12 px margin on a narrow screen', () {
      const window = Size(200, 500);
      final g = CoachGeometry.compute(anchor: const Rect.fromLTWH(150, 20, 36, 36), window: window);
      expect(g.card.width, 176);
      expect(g.card.left, 12);
      expectInside(g, window);
    });

    test('the arrow never reaches the rounded corners', () {
      // Button at the far left: the arrow clamps to 20 px from the card's edge.
      final left = CoachGeometry.compute(
        anchor: const Rect.fromLTWH(14, 8, 36, 36),
        window: const Size(1280, 800),
      );
      expect(left.arrow, greaterThanOrEqualTo(CoachGeometry.cornerClear));
      // Button at the far right of a window wider than the card's reach.
      final right = CoachGeometry.compute(
        anchor: const Rect.fromLTWH(1244, 8, 36, 36),
        window: const Size(1280, 800),
      );
      expect(right.arrow, lessThanOrEqualTo(right.card.width - CoachGeometry.cornerClear));
    });
  });

  group('a window too short for the card underneath', () {
    test('hangs it to the button\'s left, arrow on its right edge', () {
      const window = Size(750, 369);
      const safe = EdgeInsets.only(left: 47, right: 47);
      final g = CoachGeometry.compute(
        anchor: const Rect.fromLTWH(630, 8, 40, 40),
        window: window,
        safe: safe,
        cardHeight: 300,
      );
      expect(g.side, CoachSide.left);
      expectInside(g, window, safe: safe);
      expect(g.card.right, lessThan(g.anchor.left - g.ringOutset));
      // The arrow still points at the button (it is only kept off the corners).
      expect(g.card.top + g.arrow, inInclusiveRange(g.anchor.top, g.anchor.bottom));
    });

    test('stays underneath when it fits', () {
      final g = CoachGeometry.compute(
        anchor: const Rect.fromLTWH(1230, 8, 36, 36),
        window: const Size(1280, 800),
        cardHeight: 160,
      );
      expect(g.side, CoachSide.below);
    });

    test('a window shorter than the card pulls it up inside the margins, never off-screen', () {
      const window = Size(320, 260);
      final g = CoachGeometry.compute(
        anchor: const Rect.fromLTWH(270, 8, 36, 36),
        window: window,
        cardHeight: 200,
      );
      expect(g.card.top, greaterThanOrEqualTo(CoachGeometry.cardMargin));
      expect(g.card.bottom, lessThanOrEqualTo(window.height - CoachGeometry.cardMargin));
    });
  });
}
