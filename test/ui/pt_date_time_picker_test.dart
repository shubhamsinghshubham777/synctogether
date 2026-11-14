import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/ui/booth_icons.g.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/pt_date_time_picker.dart';
import 'package:synctogether/ui/pt_theme.dart';
import 'package:synctogether/ui/rolling_text.dart';

final _now = DateTime(2026, 11, 8, 20, 15);
final _min = _now;
final _max = DateTime(2027, 11, 8, 20, 15);

/// A rolling line (headline, time, year), found by the whole string it shows.
Finder rolling(String t) => find.byWidgetPredicate((w) => w is PTRollingText && w.text == t);

void main() {
  DateTime? result;
  var closed = false;

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(900, 800),
    DateTime? initial,
    bool dateOnly = false,
    bool? is24Hour,
    PickerPart part = PickerPart.date,
    String? Function(DateTime)? partnerLine,
    String? movingFrom,
    DateTime? max,
  }) async {
    result = null;
    closed = false;
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPTTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showGlassDialog<DateTime>(
                  context: context,
                  width: 640,
                  sheetOnCompact: true,
                  builder: (_) => PTDateTimePicker(
                    initial: initial ?? DateTime(2026, 12, 10, 21, 0),
                    min: _min,
                    max: max ?? _max,
                    dateOnly: dateOnly,
                    part: part,
                    is24Hour: is24Hour ?? false,
                    firstWeekday: DateTime.monday,
                    now: _now,
                    partnerLine: partnerLine,
                    movingFrom: movingFrom,
                  ),
                );
                closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> tapSet(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(PTButton, 'Set'));
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String chars) async {
    for (final c in chars.split('')) {
      final key = switch (c) {
        '0' => LogicalKeyboardKey.digit0,
        '1' => LogicalKeyboardKey.digit1,
        '2' => LogicalKeyboardKey.digit2,
        '3' => LogicalKeyboardKey.digit3,
        '9' => LogicalKeyboardKey.digit9,
        'p' => LogicalKeyboardKey.keyP,
        _ => throw ArgumentError(c),
      };
      await simulateKeyDownEvent(key, character: c);
      await simulateKeyUpEvent(key);
    }
    await tester.pump();
  }

  bool setEnabled(WidgetTester tester) =>
      tester.widget<PTButton>(find.widgetWithText(PTButton, 'Set')).onPressed != null;

  group('wheels (under 480 wide)', () {
    const phone = Size(390, 844);

    testWidgets('a phone gets four wheels and no month grid', (tester) async {
      await open(tester, size: phone);
      expect(find.byType(ListWheelScrollView), findsNWidgets(4));
      expect(find.text('TIME'), findsNothing);
      expect(rolling('Saturday 12 December'), findsNothing);
      expect(rolling('Thursday 10 December'), findsOneWidget);
    });

    testWidgets('Set returns what the wheels show', (tester) async {
      await open(tester, size: phone);
      await tapSet(tester);
      expect(result, DateTime(2026, 12, 10, 21, 0));
    });

    testWidgets('dragging the minute wheel one row sets the next minute', (tester) async {
      await open(tester, size: phone);
      await tester.drag(find.byType(ListWheelScrollView).at(2), const Offset(0, -40));
      await tester.pumpAndSettle();
      await tapSet(tester);
      expect(result, DateTime(2026, 12, 10, 21, 1));
    });

    testWidgets('a short landscape phone also gets wheels', (tester) async {
      await open(tester, size: const Size(844, 390));
      expect(find.byType(ListWheelScrollView), findsNWidgets(4));
    });

    testWidgets('a 24-hour clock has no AM/PM wheel', (tester) async {
      await open(tester, size: phone, is24Hour: true);
      expect(find.byType(ListWheelScrollView), findsNWidgets(3));
      expect(find.text('PM'), findsNothing);
    });

    testWidgets('date only is month, day and year', (tester) async {
      await open(tester, size: phone, dateOnly: true, initial: DateTime(2027, 3, 12));
      expect(find.byType(ListWheelScrollView), findsNWidgets(3));
      await tapSet(tester);
      expect(result, DateTime(2027, 3, 12));
    });

    testWidgets('a phone is a sheet', (tester) async {
      await open(tester, size: phone);
      expect(find.byKey(kGlassSheetKey), findsOneWidget);
    });
  });

  group('grid (480 and up)', () {
    testWidgets('a desktop window gets the month grid and the time field', (tester) async {
      await open(tester);
      expect(find.byType(ListWheelScrollView), findsNothing);
      expect(find.text('December'), findsOneWidget);
      expect(find.text('TIME'), findsOneWidget);
      expect(find.text('Type a time, or use the Up and Down arrow keys.'), findsOneWidget);
    });

    testWidgets('tapping a day and Set returns that day at the same time', (tester) async {
      await open(tester);
      await tester.tap(find.text('17'));
      await tester.pumpAndSettle();
      await tapSet(tester);
      expect(result, DateTime(2026, 12, 17, 21, 0));
    });

    testWidgets('arrow keys move the day, Enter sets it', (tester) async {
      await open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(rolling('Friday 18 December'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(result, DateTime(2026, 12, 18, 21, 0));
    });

    testWidgets('page keys change the month', (tester) async {
      await open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pump();
      expect(find.text('January'), findsOneWidget);
      expect(rolling('Sunday 10 January 2027'), findsOneWidget);
    });

    testWidgets('the hour steps with the arrows and wraps at midnight', (tester) async {
      await open(tester, part: PickerPart.time, initial: DateTime(2026, 12, 10, 23, 10));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      await tapSet(tester);
      expect(result, DateTime(2026, 12, 10, 0, 10));
    });

    testWidgets('typing 930p sets 9:30 PM', (tester) async {
      await open(tester, part: PickerPart.time, initial: DateTime(2026, 12, 10, 8, 0));
      await type(tester, '930p');
      await tapSet(tester);
      expect(result, DateTime(2026, 12, 10, 21, 30));
    });

    testWidgets('the AM/PM buttons flip the half of the day', (tester) async {
      await open(tester);
      await tester.tap(find.text('AM'));
      await tester.pumpAndSettle();
      await tapSet(tester);
      expect(result, DateTime(2026, 12, 10, 9, 0));
    });

    testWidgets('a 24-hour clock has no AM/PM buttons', (tester) async {
      await open(tester, is24Hour: true);
      expect(find.text('AM'), findsNothing);
      expect(find.text('PM'), findsNothing);
    });

    testWidgets('the month buttons stop at the ends of the range', (tester) async {
      await open(tester, initial: DateTime(2026, 11, 20, 21, 0));
      // November 2026 is the first month: nothing before it.
      await tester.tap(find.byIcon(BoothIcons.chevronLeft));
      await tester.pump();
      expect(find.text('November'), findsOneWidget);
      await tester.tap(find.byIcon(BoothIcons.chevronRight));
      await tester.pump();
      expect(find.text('December'), findsOneWidget);
    });

    testWidgets('days before today cannot be picked', (tester) async {
      await open(tester, initial: DateTime(2026, 11, 20, 21, 0));
      await tester.tap(find.text('3'));
      await tester.pumpAndSettle();
      expect(rolling('Friday 20 November'), findsOneWidget);
    });

    testWidgets('date only has the grid and no time field', (tester) async {
      await open(tester, dateOnly: true, initial: DateTime(2027, 3, 12));
      expect(find.text('TIME'), findsNothing);
      await tapSet(tester);
      expect(result, DateTime(2027, 3, 12));
    });
  });

  group('what the picker says', () {
    testWidgets('a time that has already passed turns Set off and says why', (tester) async {
      await open(tester, initial: DateTime(2026, 11, 8, 21, 0));
      expect(setEnabled(tester), isTrue);
      await tester.tap(find.byIcon(BoothIcons.chevronDown).first);
      await tester.tap(find.byIcon(BoothIcons.chevronDown).first);
      await tester.pumpAndSettle();
      expect(find.text("Pick a time that hasn't happened yet."), findsOneWidget);
      expect(setEnabled(tester), isFalse);
    });

    testWidgets('an existing value outside the range opens clamped to the edge', (tester) async {
      await open(tester, initial: DateTime(2020, 1, 1, 8, 0));
      await tapSet(tester);
      expect(result, DateTime(2026, 11, 8, 20, 15));
    });

    testWidgets('the last day says how far ahead can be planned', (tester) async {
      await open(tester, initial: DateTime(2027, 11, 8, 20, 15));
      expect(find.text('A year ahead is as far as we can plan.'), findsOneWidget);
    });

    testWidgets('Today jumps to today and lights up', (tester) async {
      await open(tester);
      expect(rolling('Today, Sun 8 Nov'), findsNothing);
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      expect(rolling('Today, Sun 8 Nov'), findsOneWidget);
      expect(find.text('WHEN'), findsOneWidget);
      expect(find.text(' · TODAY'), findsOneWidget);
      expect(find.byIcon(BoothIcons.check), findsOneWidget);
    });

    testWidgets('the other person\'s time shows when asked, and not when not', (tester) async {
      await open(tester, partnerLine: (m) => "That's 4:00 PM for Sam.");
      expect(find.text("That's 4:00 PM for Sam."), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      await open(tester, partnerLine: (_) => null);
      expect(find.textContaining('for Sam'), findsNothing);
    });

    testWidgets('moving a night says where it is moving from', (tester) async {
      await open(tester, movingFrom: 'Moving from Sat 14 Nov, 8:07 PM');
      expect(find.text('WHEN · MOVING THE NIGHT'), findsOneWidget);
      expect(find.text('Moving from Sat 14 Nov, 8:07 PM'), findsOneWidget);
    });

    testWidgets('Cancel returns nothing', (tester) async {
      await open(tester);
      await tester.tap(find.widgetWithText(PTButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(closed, isTrue);
    });

    testWidgets('Escape returns nothing', (tester) async {
      await open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(closed, isTrue);
    });
  });
  group('motion', () {
    double height(WidgetTester tester) => tester.getSize(find.byType(PTDateTimePicker)).height;

    testWidgets('a caption folds open, it does not shove the buttons in one frame', (tester) async {
      await open(tester, initial: DateTime(2026, 11, 8, 21, 0));
      final before = height(tester);
      await tester.tap(find.byIcon(BoothIcons.chevronDown).first);
      await tester.tap(find.byIcon(BoothIcons.chevronDown).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final during = height(tester);
      await tester.pumpAndSettle();
      final after = height(tester);
      expect(after, greaterThan(before));
      expect(during, greaterThan(before), reason: 'it has started to open');
      expect(during, lessThan(after), reason: 'and is not there yet');
    });

    testWidgets('every month is the same height, a short month leaves its last row empty', (
      tester,
    ) async {
      // November 2026 needs six rows on a Monday-first week, December five.
      await open(tester, initial: DateTime(2026, 11, 20, 21, 0));
      final nov = height(tester);
      await tester.tap(find.byIcon(BoothIcons.chevronRight));
      await tester.pumpAndSettle();
      expect(find.text('December'), findsOneWidget);
      expect(height(tester), nov);
      await tester.tap(find.byIcon(BoothIcons.chevronRight));
      await tester.pumpAndSettle();
      expect(height(tester), nov);
    });

    testWidgets('the month slides in from the side you are heading to', (tester) async {
      await open(tester, initial: DateTime(2026, 12, 10, 21, 0));
      Offset title(String t) => tester.getTopLeft(find.text(t));
      await tester.tap(find.byIcon(BoothIcons.chevronRight));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final nextMid = title('January');
      await tester.pumpAndSettle();
      final nextEnd = title('January');
      expect(nextMid.dx, greaterThan(nextEnd.dx), reason: 'coming from the right');

      await tester.tap(find.byIcon(BoothIcons.chevronLeft));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final prevMid = title('December');
      await tester.pumpAndSettle();
      final prevEnd = title('December');
      expect(prevMid.dx, lessThan(prevEnd.dx), reason: 'coming from the left');
    });

    testWidgets('the year glides to its new place as the month word changes width', (tester) async {
      // "December" is wider than "January": the year after it must move left a bit
      // at a time, not jump when the slide ends.
      await open(tester, initial: DateTime(2026, 12, 10, 21, 0));
      final start = tester.getTopLeft(rolling('2026')).dx;
      await tester.tap(find.byIcon(BoothIcons.chevronRight));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final mid = tester.getTopLeft(rolling('2027')).dx;
      await tester.pump(const Duration(milliseconds: 60));
      final later = tester.getTopLeft(rolling('2027')).dx;
      await tester.pumpAndSettle();
      final end = tester.getTopLeft(rolling('2027')).dx;
      expect(start, greaterThan(end), reason: 'January is narrower');
      expect(mid, lessThan(start), reason: 'already moving');
      expect(mid, greaterThan(end), reason: 'not there yet');
      expect(later, lessThan(mid), reason: 'still moving, smoothly');
      expect(later, greaterThanOrEqualTo(end));
    });

    testWidgets('a digit going up arrives from below, going down from above', (tester) async {
      await open(tester, part: PickerPart.time, initial: DateTime(2026, 12, 10, 16, 20));
      Finder digit(String t) => find.byWidgetPredicate(
        (w) => w is Text && w.data == t && w.style?.fontFamily == PTFonts.mono,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final upMid = tester.getTopLeft(digit('5')).dy;
      await tester.pumpAndSettle();
      final upEnd = tester.getTopLeft(digit('5')).dy;
      expect(upMid, greaterThan(upEnd), reason: 'rising: starts lower than it rests');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final downMid = tester.getTopLeft(digit('3')).dy;
      await tester.pumpAndSettle();
      final downEnd = tester.getTopLeft(digit('3')).dy;
      expect(downMid, lessThan(downEnd), reason: 'falling: starts higher than it rests');
    });

    testWidgets('changing the date animates only the characters that changed', (tester) async {
      await open(tester);
      await tester.tap(find.text('17'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      // Thursday 10 December to Thursday 17 December: one digit changes, so one
      // character leaves and one arrives and nothing else moves.
      final headline = find.descendant(
        of: rolling('Thursday 17 December'),
        matching: find.byType(FadeTransition),
      );
      final moving = tester
          .widgetList<FadeTransition>(headline)
          .where((f) => f.opacity.value < 1)
          .length;
      expect(moving, 2);
      await tester.pumpAndSettle();
    });

    testWidgets('a minute changing rolls its last digit, not the whole time', (tester) async {
      await open(tester, part: PickerPart.time, initial: DateTime(2026, 12, 10, 20, 58));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final time = find.descendant(of: rolling('8:59 PM'), matching: find.byType(FadeTransition));
      final moving = tester
          .widgetList<FadeTransition>(time)
          .where((f) => f.opacity.value < 1)
          .length;
      expect(moving, 2, reason: 'the 8 of 58 leaves and the 9 arrives; 8: PM stay');
      await tester.pumpAndSettle();
    });
  });
}
