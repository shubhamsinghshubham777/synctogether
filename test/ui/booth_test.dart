import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/rooms/widgets/room_control_bar.dart';
import 'package:synctogether/ui/booth.dart';
import 'package:synctogether/ui/pt_theme.dart';

// Booth Light components must animate on the edges they describe and then go
// quiet: every test here ends by asserting no frame is scheduled, because an
// idle ticker beside playing video is the cost this design refuses to pay.

Widget _host(Widget child, {bool reduceMotion = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Scaffold(body: Center(child: child)),
  ),
);

void _expectIdle(WidgetTester tester) {
  expect(tester.binding.hasScheduledFrame, isFalse, reason: 'something is still animating');
}

void main() {
  group('SyncDot', () {
    testWidgets('beats on arriving at locked, then rests', (tester) async {
      await tester.pumpWidget(_host(const SyncDot(state: .catchingUp)));
      await tester.pumpAndSettle();
      _expectIdle(tester);

      await tester.pumpWidget(_host(const SyncDot(state: .locked)));
      await tester.pump(SyncDot.heartbeat ~/ 4);
      final mid = tester.widget<Transform>(
        find.descendant(of: find.byType(SyncDot), matching: find.byType(Transform)),
      );
      expect(mid.transform.getMaxScaleOnAxis(), greaterThan(1.1), reason: 'mid-beat is enlarged');

      await tester.pumpAndSettle();
      _expectIdle(tester);
    });

    testWidgets('staying locked never re-beats', (tester) async {
      await tester.pumpWidget(_host(const SyncDot(state: .locked)));
      await tester.pumpAndSettle();
      await tester.pumpWidget(_host(const SyncDot(state: .locked, size: 9)));
      await tester.pump();
      _expectIdle(tester);
    });

    testWidgets('reduce motion skips the beat', (tester) async {
      await tester.pumpWidget(_host(const SyncDot(state: .idle), reduceMotion: true));
      await tester.pumpWidget(_host(const SyncDot(state: .locked), reduceMotion: true));
      await tester.pumpAndSettle();
      _expectIdle(tester);
    });
  });

  group('ReadyRing', () {
    Widget ring({required bool ready}) => ReadyRing(
      diameter: 32,
      ready: ready,
      child: const ColoredBox(color: PTColors.aisle),
    );

    testWidgets('ripples once on becoming ready and settles', (tester) async {
      await tester.pumpWidget(_host(ring(ready: false)));
      await tester.pumpAndSettle();
      await tester.pumpWidget(_host(ring(ready: true)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pumpAndSettle();
      _expectIdle(tester);
    });
  });

  group('PTStamp', () {
    testWidgets('presses in and lands at its angle', (tester) async {
      await tester.pumpWidget(_host(const PTStamp(angle: -0.2, child: Text('12'))));
      await tester.pump(const Duration(milliseconds: 60));
      final early = tester.widget<Opacity>(
        find.descendant(of: find.byType(PTStamp), matching: find.byType(Opacity)),
      );
      expect(early.opacity, lessThan(1));
      await tester.pumpAndSettle();
      final done = tester.widget<Opacity>(
        find.descendant(of: find.byType(PTStamp), matching: find.byType(Opacity)),
      );
      expect(done.opacity, 1);
      _expectIdle(tester);
    });

    testWidgets('animate: false is already inked', (tester) async {
      await tester.pumpWidget(_host(const PTStamp(animate: false, child: Text('x'))));
      await tester.pump();
      _expectIdle(tester);
    });
  });

  group('PTTicket', () {
    testWidgets('lays out, taps, and hover lift settles', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 420,
            child: PTTicket(
              paper: true,
              onTap: () => taps++,
              body: const Padding(padding: EdgeInsets.all(16), child: Text('Friday Horror Club')),
              stub: const Center(child: Text('K7Q2ZP')),
            ),
          ),
        ),
      );
      final gesture = await tester.createGesture(kind: .mouse);
      await gesture.addPointer(location: tester.getCenter(find.byType(PTTicket)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Friday Horror Club'));
      await tester.pumpAndSettle();
      expect(taps, 1);
      _expectIdle(tester);
      await gesture.removePointer();
    });

    test('TicketBorder bites a notch out of each short edge at mid-height', () {
      const border = TicketBorder(stubInset: 100, notchRadius: 10);
      final path = border.getOuterPath(const Rect.fromLTWH(0, 0, 400, 120));
      expect(path.contains(const Offset(2, 60)), isFalse, reason: 'left notch');
      expect(path.contains(const Offset(398, 60)), isFalse, reason: 'right notch');
      expect(path.contains(const Offset(300, 2)), isTrue, reason: 'the tear line is not notched');
      expect(path.contains(const Offset(200, 60)), isTrue);
    });
  });

  group('extrapolatedPlayhead', () {
    test('advances on the wall clock between reports', () {
      expect(
        extrapolatedPlayhead(
          reported: const Duration(seconds: 10),
          sinceReport: const Duration(milliseconds: 250),
          duration: const Duration(minutes: 2),
        ),
        const Duration(seconds: 10, milliseconds: 250),
      );
    });

    test('a stalled player freezes instead of running away', () {
      expect(
        extrapolatedPlayhead(
          reported: const Duration(seconds: 10),
          sinceReport: const Duration(seconds: 30),
          duration: const Duration(minutes: 2),
        ),
        const Duration(seconds: 10) + kMaxExtrapolation,
      );
    });

    test('never draws past the end', () {
      expect(
        extrapolatedPlayhead(
          reported: const Duration(seconds: 119, milliseconds: 900),
          sinceReport: const Duration(milliseconds: 500),
          duration: const Duration(minutes: 2),
        ),
        const Duration(minutes: 2),
      );
    });
  });
}
