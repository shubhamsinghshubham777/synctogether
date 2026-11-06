import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/ui/responsive.dart';

void main() {
  test('kDesktopMinWindowSize sits inside the desktop class', () {
    expect(kDesktopMinWindowSize, const Size(900, 600));
    expect(classifyLayout(kDesktopMinWindowSize, .pointer), PTLayout.desktop);
  });

  group('classifyLayout', () {
    const cases = <(String, Size, PTInput, PTLayout)>[
      ('macOS desktop', Size(1440, 900), .pointer, .desktop),
      ('narrow pointer window', Size(700, 900), .pointer, .portrait),
      ('iPhone portrait', Size(390, 844), .touch, .portrait),
      ('iPhone landscape', Size(844, 390), .touch, .landscape),
      ('iPhone SE landscape', Size(667, 375), .touch, .landscape),
      ('iPad mini portrait', Size(744, 1133), .touch, .tablet),
      ('iPad Air portrait', Size(820, 1180), .touch, .tablet),
      ('iPad landscape', Size(1180, 820), .touch, .tablet),
      ('iPad 1/3 split view', Size(320, 1024), .touch, .portrait),
      ('Fold unfolded', Size(882, 1104), .touch, .tablet),
      ('Fold cover screen', Size(344, 882), .touch, .portrait),
    ];
    for (final (name, size, input, expected) in cases) {
      test(name, () => expect(classifyLayout(size, input), expected));
    }
  });

  group('panes', () {
    PTFold fold(Rect bounds, {DisplayFeatureType type = .hinge, DisplayFeatureState? state}) =>
        foldFromFeatures([
          DisplayFeature(bounds: bounds, type: type, state: state ?? .postureFlat),
        ]);

    test('no split is one whole-window pane', () {
      const size = Size(882, 1104);
      expect(panesOf(size, PTFold.none), [Offset.zero & size]);
      expect(primaryPaneOf(size, PTFold.none), Offset.zero & size);
      // A flat fold with no hinge area is a continuous display.
      final flat = fold(const Rect.fromLTWH(0, 552, 882, 0), type: .fold, state: .postureFlat);
      expect(flat.isSplit, isFalse);
    });

    test('a vertical hinge leaves its own rect out of both panes', () {
      const size = Size(1110, 720);
      final f = fold(const Rect.fromLTWH(540, 0, 30, 720));
      expect(f.axis, PTFoldAxis.vertical);
      final panes = panesOf(size, f);
      expect(panes, [const Rect.fromLTRB(0, 0, 540, 720), const Rect.fromLTRB(570, 0, 1110, 720)]);
      for (final p in panes) {
        expect(p.overlaps(f.bounds), isFalse);
      }
    });

    test('a half-opened horizontal fold splits top and bottom', () {
      const size = Size(882, 1104);
      final f = fold(const Rect.fromLTWH(0, 552, 882, 0), type: .fold, state: .postureHalfOpened);
      expect(f.axis, PTFoldAxis.horizontal);
      expect(panesOf(size, f), [
        const Rect.fromLTRB(0, 0, 882, 552),
        const Rect.fromLTRB(0, 552, 882, 1104),
      ]);
    });

    test('a one-column screen takes the larger pane, the first on a tie', () {
      const size = Size(1080, 960);
      final even = fold(const Rect.fromLTWH(538, 0, 4, 960));
      expect(primaryPaneOf(size, even).left, 0);
      // Hinge off to the left: the right pane is bigger.
      final lopsided = fold(const Rect.fromLTWH(300, 0, 20, 960));
      expect(primaryPaneOf(size, lopsided).left, 320);
    });

    test('a tabletop screen takes the lower pane unless that is too short', () {
      const size = Size(882, 1104);
      final mid = fold(const Rect.fromLTWH(0, 552, 882, 0), type: .fold, state: .postureHalfOpened);
      expect(primaryPaneOf(size, mid).top, 552);
      final low = fold(
        const Rect.fromLTWH(0, 1000, 882, 0),
        type: .fold,
        state: .postureHalfOpened,
      );
      expect(primaryPaneOf(size, low).top, 0);
    });

    test('an anchor picks the pane that holds it', () {
      const size = Size(1110, 720);
      final f = fold(const Rect.fromLTWH(540, 0, 30, 720));
      expect(primaryPaneOf(size, f, anchor: const Offset(900, 100)).left, 570);
      expect(primaryPaneOf(size, f, anchor: const Offset(100, 100)).left, 0);
    });
  });
}
