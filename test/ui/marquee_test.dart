import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/ui/marquee.dart';

const _long = 'Cosmic Voyage Screening With An Unreasonably Long Room Name';
const _style = TextStyle(fontSize: 14, fontFamily: 'Ahem');

Widget _host(String text, {double width = 160, bool reduceMotion = false}) => MediaQuery(
  data: MediaQueryData(disableAnimations: reduceMotion),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: SizedBox(
        width: width,
        child: PTMarquee(text, style: _style),
      ),
    ),
  ),
);

double _x(WidgetTester tester) => tester.getTopLeft(find.text(_long)).dx;

void main() {
  setUp(() => PTMarquee.animate = true);
  tearDown(() => PTMarquee.animate = false);

  testWidgets('a name that fits is plain text and nothing animates', (tester) async {
    await tester.pumpWidget(_host('Movie night', width: 400));
    expect(find.text('Movie night'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pump(const Duration(seconds: 5));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a long name holds, then scrolls its whole length, then loops', (tester) async {
    await tester.pumpWidget(_host(_long));
    await tester.pump(); // the controller starts after layout
    await tester.pump();
    final start = _x(tester);
    // Held at its start for the pause.
    await tester.pump(const Duration(milliseconds: 1000));
    expect(_x(tester), start);
    // Then moving left, a few pixels a frame.
    await tester.pump(const Duration(milliseconds: 1000));
    var prev = _x(tester);
    expect(prev, lessThan(start));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final now = _x(tester);
      expect(prev - now, lessThan(3), reason: 'no jump at frame $i');
      prev = now;
    }
    // It reaches the end of the first copy plus the gap and starts over.
    await tester.pump(const Duration(seconds: 40));
    expect(_x(tester), inInclusiveRange(start - 900, start));
    expect(find.text(_long), findsOneWidget, reason: 'one Text, the second copy is not a Text');
  });

  testWidgets('it is one line tall wherever it sits, even with unbounded height', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SingleChildScrollView(
            child: Column(
              children: [
                SizedBox(width: 160, child: PTMarquee(_long, style: _style)),
                Row(
                  children: [Flexible(child: PTMarquee(_long, style: _style))],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    for (final marquee in find.byType(PTMarquee).evaluate()) {
      final box = marquee.renderObject! as RenderBox;
      expect(
        box.size.height,
        lessThan(40),
        reason: 'a marquee must not take the height it is offered',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduce-motion shows it still, ellipsized', (tester) async {
    await tester.pumpWidget(_host(_long, reduceMotion: true));
    await tester.pump(const Duration(seconds: 3));
    expect(tester.binding.hasScheduledFrame, isFalse);
    final text = tester.widget<Text>(find.text(_long));
    expect(text.overflow, TextOverflow.ellipsis);
  });

  testWidgets('it is one semantics label', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(_long));
    await tester.pump();
    expect(find.bySemanticsLabel(_long), findsOneWidget);
    handle.dispose();
  });
}
