import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/ui/reveal.dart';

Widget _app({required bool open}) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(
    alignment: Alignment.topLeft,
    child: PTColumn(
      spacing: 12,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(key: ValueKey('a'), width: 50, height: 20),
        PTRevealKeep(visible: open, child: const SizedBox(width: 50, height: 30)),
        const SizedBox(key: ValueKey('b'), width: 50, height: 20),
      ],
    ),
  ),
);

void main() {
  testWidgets('a hidden fold leaves one gap between its neighbours, not two', (tester) async {
    await tester.pumpWidget(_app(open: false));
    final a = tester.getRect(find.byKey(const ValueKey('a')));
    final b = tester.getRect(find.byKey(const ValueKey('b')));
    expect(b.top - a.bottom, 12);
  });

  testWidgets('an open fold has a gap above and below it', (tester) async {
    await tester.pumpWidget(_app(open: true));
    final a = tester.getRect(find.byKey(const ValueKey('a')));
    final b = tester.getRect(find.byKey(const ValueKey('b')));
    expect(b.top - a.bottom, 12 + 30 + 12);
  });

  testWidgets('opening it grows the column over several frames, the gap with it', (tester) async {
    await tester.pumpWidget(_app(open: false));
    final start = tester.getSize(find.byType(PTColumn)).height;
    await tester.pumpWidget(_app(open: true));
    await tester.pump(const Duration(milliseconds: 60));
    final mid = tester.getSize(find.byType(PTColumn)).height;
    await tester.pumpAndSettle();
    final end = tester.getSize(find.byType(PTColumn)).height;
    expect(mid, greaterThan(start));
    expect(mid, lessThan(end));
  });
}
