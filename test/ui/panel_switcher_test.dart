import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/ui/panel_switcher.dart';

void main() {
  Widget host(String which) => Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 300,
        child: PTPanelSwitcher(
          child: SizedBox(key: ValueKey(which), height: which == 'tall' ? 400 : 100),
        ),
      ),
    ),
  );

  testWidgets('height starts animating on the first frame and never overshoots', (tester) async {
    await tester.pumpWidget(host('tall'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(PTPanelSwitcher)).height, 400);

    await tester.pumpWidget(host('short'));
    final heights = <double>[];
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      heights.add(tester.getSize(find.byType(PTPanelSwitcher)).height);
    }
    // Moving from the very first frames (the old panel does not hold the height until it fades).
    expect(heights.first, lessThan(400), reason: 'height must start shrinking immediately');
    for (var i = 1; i < heights.length; i++) {
      expect(heights[i], lessThanOrEqualTo(heights[i - 1] + 0.001), reason: 'monotonic shrink');
      expect(heights[i], greaterThanOrEqualTo(100));
    }
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(PTPanelSwitcher)).height, 100);
  });

  testWidgets('growing is monotonic too, and the old panel never takes taps', (tester) async {
    await tester.pumpWidget(host('short'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(host('tall'));
    var last = 100.0;
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (i == 0) {
        // Mid-swap the outgoing panel is inert: it cannot take a tap meant for the new one.
        expect(find.byType(IgnorePointer), findsWidgets);
      }
      final h = tester.getSize(find.byType(PTPanelSwitcher)).height;
      expect(h, greaterThanOrEqualTo(last - 0.001));
      expect(h, lessThanOrEqualTo(400));
      last = h;
    }
    await tester.pumpAndSettle();
    expect(last, greaterThan(100));
  });

  testWidgets('the outgoing panel is gone before the incoming one is fully in', (tester) async {
    await tester.pumpWidget(host('tall'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(host('short'));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byKey(const ValueKey('tall')), findsOneWidget);
    await tester.pump(PTPanelSwitcher.outgoing + const Duration(milliseconds: 40));
    expect(find.byKey(const ValueKey('tall')), findsNothing);
    expect(find.byKey(const ValueKey('short')), findsOneWidget);
  });
}
