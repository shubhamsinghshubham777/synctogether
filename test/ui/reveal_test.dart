import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/ui/reveal.dart';

Widget _host(bool visible, {bool reduce = false, Axis axis = Axis.vertical, Widget? child}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: PTReveal(
              visible: visible,
              axis: axis,
              child:
                  child ??
                  SizedBox(
                    key: const Key('box'),
                    width: 100,
                    height: 80,
                    child: TextButton(onPressed: () {}, child: const Text('tap')),
                  ),
            ),
          ),
        ),
      ),
    );

double _h(WidgetTester t) => t.getSize(find.byType(PTReveal)).height;

void main() {
  testWidgets('starts settled: visible shows whole, hidden is zero tall', (t) async {
    await t.pumpWidget(_host(true));
    expect(_h(t), 80);
    await t.pumpWidget(_host(false));
    await t.pumpAndSettle();
    expect(_h(t), 0);
    expect(find.byKey(const Key('box')), findsNothing);
  });

  testWidgets('height is monotonic and never jumps more than 30 px per frame', (t) async {
    await t.pumpWidget(_host(false));
    await t.pumpWidget(_host(true));
    var prev = _h(t);
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 16));
      final h = _h(t);
      expect(h, greaterThanOrEqualTo(prev));
      expect(h - prev, lessThan(30));
      prev = h;
    }
    expect(prev, 80);
    await t.pumpWidget(_host(false));
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 16));
      final h = _h(t);
      expect(h, lessThanOrEqualTo(prev));
      expect(prev - h, lessThan(30));
      prev = h;
    }
    expect(prev, 0);
  });

  testWidgets('hidden child is not hittable, focusable or semantic', (t) async {
    final handle = t.ensureSemantics();
    await t.pumpWidget(_host(true));
    expect(find.text('tap').hitTestable(), findsOneWidget);
    expect(find.semantics.byLabel('tap'), findsOneWidget);
    await t.pumpWidget(_host(false));
    await t.pump(const Duration(milliseconds: 40));
    // Mid-fold: still painted, but already out of reach.
    expect(find.text('tap').hitTestable(), findsNothing);
    await t.pump();
    // The widget finder still sees the subtree; the semantics tree must not.
    expect(find.semantics.byLabel('tap'), findsNothing);
    handle.dispose();
  });

  testWidgets('reduce-motion halves the duration', (t) async {
    await t.pumpWidget(_host(false, reduce: true));
    await t.pumpWidget(_host(true, reduce: true));
    await t.pump();
    await t.pump(const Duration(milliseconds: 115));
    expect(_h(t), 80);
  });

  testWidgets('horizontal axis animates width', (t) async {
    await t.pumpWidget(_host(false, axis: Axis.horizontal));
    await t.pumpWidget(_host(true, axis: Axis.horizontal));
    await t.pump(const Duration(milliseconds: 16));
    final w = t.getSize(find.byType(PTReveal)).width;
    expect(w, inInclusiveRange(0, 100));
    await t.pumpAndSettle();
    expect(t.getSize(find.byType(PTReveal)).width, 100);
  });

  testWidgets('works under IntrinsicHeight', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IntrinsicHeight(
            child: Row(
              children: [
                const Expanded(child: SizedBox(height: 10)),
                PTReveal(visible: true, child: const SizedBox(width: 20, height: 50)),
              ],
            ),
          ),
        ),
      ),
    );
    expect(t.takeException(), isNull);
  });
}
