import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/ui/display_regions.dart';
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

    test('a keyboard that covers most of the lower pane moves a dialog up', () {
      const size = Size(669, 951);
      final f = fold(
        const Rect.fromLTWH(0, 455.5, 669, 40),
        type: .fold,
        state: .postureHalfOpened,
      );
      expect(primaryPaneOf(size, f).top, 495.5);
      expect(primaryPaneOf(size, f, keyboard: 336).top, 0);
      expect(primaryPaneOf(size, f, keyboard: 100).top, 495.5);
    });

    test('an anchor picks the pane that holds it', () {
      const size = Size(1110, 720);
      final f = fold(const Rect.fromLTWH(540, 0, 30, 720));
      expect(primaryPaneOf(size, f, anchor: const Offset(900, 100)).left, 570);
      expect(primaryPaneOf(size, f, anchor: const Offset(100, 100)).left, 0);
    });
  });

  // The payloads below are what the iPhone Duo simulator (Xcode 27.1, iOS 27.1)
  // actually sent for each posture, in the order it sent them.
  group('iPhone Duo reserved regions', () {
    const camera = {
      'kind': 'occlusion',
      'active': true,
      'left': 29.3,
      'top': 29.3,
      'width': 37.0,
      'height': 37.0,
    };

    PTFold fold(List<Map<Object?, Object?>> regions) =>
        foldFromFeatures(featuresFromRegions(regions));

    test('closed outer display: camera and system bar are cutouts, not a hinge', () {
      final features = featuresFromRegions([
        camera,
        {
          'kind': 'occlusion',
          'active': true,
          'left': 0.0,
          'top': 0.0,
          'width': 82.0,
          'height': 84.0,
        },
      ]);
      expect(features, hasLength(2));
      expect(features.every((f) => f.type == DisplayFeatureType.cutout), isTrue);
      expect(foldFromFeatures(features).isSplit, isFalse);
    });

    test('open flat: an inactive 40 pt division divides nothing', () {
      final f = fold([
        {
          'kind': 'occlusion',
          'active': false,
          'left': 677.3,
          'top': 21.0,
          'width': 58.0,
          'height': 37.0,
        },
        {
          'kind': 'occlusion',
          'active': true,
          'left': 867.0,
          'top': 0.0,
          'width': 84.0,
          'height': 124.0,
        },
        {
          'kind': 'division',
          'active': false,
          'left': 455.5,
          'top': 0.0,
          'width': 40.0,
          'height': 669.0,
        },
      ]);
      expect(f.isSplit, isFalse);
    });

    test('book-folded: the active division is a vertical fold with a 40 pt gap', () {
      final f = fold([
        {
          'kind': 'occlusion',
          'active': true,
          'left': 867.0,
          'top': 0.0,
          'width': 84.0,
          'height': 124.0,
        },
        {
          'kind': 'division',
          'active': true,
          'left': 455.5,
          'top': 0.0,
          'width': 40.0,
          'height': 669.0,
        },
      ]);
      expect(f.axis, PTFoldAxis.vertical);
      final panes = panesOf(const Size(951, 669), f);
      expect(panes, [
        const Rect.fromLTRB(0, 0, 455.5, 669),
        const Rect.fromLTRB(495.5, 0, 951, 669),
      ]);
    });

    test('tabletop: the active division is a horizontal fold', () {
      final f = fold([
        {
          'kind': 'occlusion',
          'active': true,
          'left': 525.0,
          'top': 0.0,
          'width': 144.0,
          'height': 82.0,
        },
        {
          'kind': 'division',
          'active': true,
          'left': 0.0,
          'top': 455.5,
          'width': 669.0,
          'height': 40.0,
        },
      ]);
      expect(f.axis, PTFoldAxis.horizontal);
      expect(primaryPaneOf(const Size(669, 951), f).top, 495.5);
    });

    test('a malformed or empty payload is no fold, never an error', () {
      expect(featuresFromRegions(const []), isEmpty);
      expect(
        featuresFromRegions([
          {'kind': 'division'},
        ]),
        isEmpty,
      );
      expect(
        featuresFromRegions([
          {'kind': 'something-new', 'active': true, 'width': 1.0, 'height': 1.0},
        ]),
        isEmpty,
      );
    });
  });
}
