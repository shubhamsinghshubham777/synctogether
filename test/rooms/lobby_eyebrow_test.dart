import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/rooms/lobby_screen.dart';

void main() {
  group('lobbyEyebrowText', () {
    test('formats day, time and greeting', () {
      expect(
        lobbyEyebrowText(DateTime(2026, 11, 6, 10, 4), 'maya'),
        'FRI · 10:04 · GOOD MORNING, MAYA',
      );
      expect(lobbyEyebrowText(DateTime(2026, 11, 7, 21, 40), null), 'SAT · 21:40 · GOOD EVENING');
      expect(lobbyEyebrowText(DateTime(2026, 11, 8, 3, 5), 'x'), 'SUN · 03:05 · LATE SHOW, X');
      expect(lobbyEyebrowText(DateTime(2026, 11, 9, 14, 0), null), 'MON · 14:00 · GOOD AFTERNOON');
    });
  });

  group('LobbyEyebrow keeps the time fresh', () {
    late DateTime now;
    setUp(() => now = DateTime(2026, 11, 6, 10, 2, 30));

    Widget host() => MaterialApp(
      home: Scaffold(body: LobbyEyebrow(clock: () => now)),
    );

    testWidgets('moves to the next minute without any other rebuild', (tester) async {
      await tester.pumpWidget(host());
      expect(find.textContaining('10:02'), findsOneWidget);

      // The wall clock moves on; the timer aimed at the minute boundary fires.
      now = DateTime(2026, 11, 6, 10, 3, 0, 200);
      await tester.pump(const Duration(seconds: 31));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('10:03'), findsOneWidget);
      expect(find.textContaining('10:02'), findsNothing);

      // And it keeps going: the timer was re-armed.
      now = DateTime(2026, 11, 6, 10, 4, 0, 200);
      await tester.pump(const Duration(seconds: 61));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('10:04'), findsOneWidget);
    });

    testWidgets('refreshes on resume (timers do not run in the background)', (tester) async {
      await tester.pumpWidget(host());
      expect(find.textContaining('10:02'), findsOneWidget);

      // Backgrounded for minutes: no timer fired, the clock is far ahead.
      now = DateTime(2026, 11, 6, 10, 9, 10);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('10:09'), findsOneWidget);
    });

    testWidgets('leaves no timer behind when it goes away', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 3));
      // A leaked timer would throw 'A Timer is still pending' at teardown.
    });
  });
}
