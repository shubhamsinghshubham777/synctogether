import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/ui/glass.dart';

import '../support/screen_matrix.dart';

const _cases = [
  ScreenCase('phone-small', Size(320, 568), .iOS),
  ScreenCase('phone-land-keyboard', Size(844, 390), .android, keyboard: 200),
  ScreenCase('desktop', Size(1440, 900), .macOS),
];

/// Far taller than any of the screens above.
Widget _tallBody(BuildContext context) => Column(
  mainAxisSize: .min,
  crossAxisAlignment: .stretch,
  children: [
    for (var i = 0; i < 40; i++)
      SizedBox(height: 40, child: Text('Row $i', key: ValueKey('row$i'))),
  ],
);

Future<void> _open(WidgetTester tester, ScreenCase c, {bool sheetOnCompact = false}) async {
  await pumpAtSize(
    tester,
    Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => showGlassDialog<void>(
              context: context,
              width: 430,
              sheetOnCompact: sheetOnCompact,
              builder: _tallBody,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
    c,
  );
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Rect _panelRect(WidgetTester tester) => tester.getRect(find.byType(GlassPanel).last);

void main() {
  for (final c in _cases) {
    testWidgets('tall glass dialog fits @ ${c.name}', (tester) async {
      await _open(tester, c);
      expectNoOverflow(tester);

      final panel = _panelRect(tester);
      final w = c.size.width;
      final visibleBottom = c.size.height - c.keyboard;
      // 16px gutter on both sides, and the 430 cap where there is room for it.
      expect(panel.left, greaterThanOrEqualTo(16));
      expect(panel.right, lessThanOrEqualTo(w - 16));
      expect(panel.width, lessThanOrEqualTo(430));
      if (w >= 430 + 32) expect(panel.width, 430);
      // Clear of the keyboard and the top edge.
      expect(panel.top, greaterThanOrEqualTo(16));
      expect(panel.bottom, lessThanOrEqualTo(visibleBottom - 16));

      // The body scrolls: the last row starts off-screen and can be reached.
      final last = find.byKey(const ValueKey('row39'));
      expect(tester.getRect(last).top, greaterThan(panel.bottom));
      await tester.dragUntilVisible(
        last,
        find.byType(SingleChildScrollView),
        const Offset(0, -200),
      );
      expect(tester.getRect(last).bottom, lessThanOrEqualTo(panel.bottom));
      expectNoOverflow(tester);
      // pumpAtSize resets this in a tearDown, which runs after the binding's
      // invariant check.
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('sheetOnCompact docks to the bottom on a narrow phone', (tester) async {
    await _open(tester, _cases.first, sheetOnCompact: true);
    expectNoOverflow(tester);
    // Full width and docked flush to the bottom edge (the phone sheet board).
    final panel = tester.getRect(find.byKey(kGlassSheetKey));
    expect(panel.width, 320);
    expect(panel.bottom, 568);
    debugDefaultTargetPlatformOverride = null;
  });

  test('horizontal padding tightens below 400 wide', () {
    expect(glassDialogPadding(null, 390).left, 20);
    expect(glassDialogPadding(null, 400).left, 32);
    expect(glassDialogPadding(const EdgeInsets.all(12), 320).left, 12);
    expect(glassDialogPadding(null, 320).top, 30);
  });
}
