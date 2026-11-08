import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/ui/pt_date_time_logic.dart';

/// A zone whose clocks jump from 02:00 to 03:00 on 14 March 2027.
DateTime _springForward(int y, int mo, int d, int h, int mi) {
  if (y == 2027 && mo == 3 && d == 14 && h == 2) return DateTime(y, mo, d, 3, mi);
  return DateTime(y, mo, d, h, mi);
}

void main() {
  group('range', () {
    final min = DateTime(2026, 11, 8, 20, 15);
    final max = DateTime(2027, 11, 8, 20, 15);

    test('checkMoment says past, too far or ok', () {
      expect(checkMoment(DateTime(2026, 11, 8, 20, 14), min: min, max: max), MomentCheck.past);
      expect(checkMoment(min, min: min, max: max), MomentCheck.ok);
      expect(checkMoment(max, min: min, max: max), MomentCheck.ok);
      expect(checkMoment(DateTime(2027, 11, 8, 20, 16), min: min, max: max), MomentCheck.tooFar);
    });

    test('clampMoment pulls an out-of-range value to the nearest edge', () {
      expect(clampMoment(DateTime(2020), min: min, max: max), min);
      expect(clampMoment(DateTime(2030), min: min, max: max), max);
      final inside = DateTime(2027, 1, 1, 9);
      expect(clampMoment(inside, min: min, max: max), inside);
    });
  });

  group('resolveMoment', () {
    test('a normal time is kept as chosen', () {
      final r = resolveMoment(2027, 3, 14, 1, 30, build: _springForward);
      expect(r.moment, DateTime(2027, 3, 14, 1, 30));
      expect(r.movedForGap, isFalse);
    });

    test('a time inside the jump becomes the first valid time after it', () {
      final r = resolveMoment(2027, 3, 14, 2, 30, build: _springForward);
      expect(r.movedForGap, isTrue);
      expect(r.moment, DateTime(2027, 3, 14, 3, 0));
    });

    test('the same clock time on another day is untouched', () {
      final r = resolveMoment(2027, 3, 15, 2, 30, build: _springForward);
      expect(r.movedForGap, isFalse);
      expect(r.moment, DateTime(2027, 3, 15, 2, 30));
    });
  });

  group('month grid', () {
    test('month lengths, including leap years', () {
      expect(daysInMonth(2027, 2), 28);
      expect(daysInMonth(2028, 2), 29);
      expect(daysInMonth(2026, 11), 30);
      expect(daysInMonth(2026, 12), 31);
    });

    test('Monday-first grid pads before the 1st and after the last day', () {
      // 1 November 2026 is a Sunday: six empty cells first when weeks start on Monday.
      final cells = monthCells(2026, 11);
      expect(cells.length % 7, 0);
      expect(cells.take(6), everyElement(isNull));
      expect(cells[6], DateTime(2026, 11, 1));
      expect(cells.whereType<DateTime>().length, 30);
    });

    test('Sunday-first grid starts that month in the first column', () {
      final cells = monthCells(2026, 11, firstWeekday: DateTime.sunday);
      expect(cells.first, DateTime(2026, 11, 1));
    });

    test('a month can need six rows', () {
      expect(monthCells(2026, 3).length, 42); // 1 Mar 2026 is a Sunday: six weeks Monday-first
    });

    test('weekday order follows the first weekday', () {
      expect(weekdayOrder(DateTime.monday), [1, 2, 3, 4, 5, 6, 7]);
      expect(weekdayOrder(DateTime.sunday), [7, 1, 2, 3, 4, 5, 6]);
    });

    test('month buttons stop at the range ends', () {
      final min = DateTime(2026, 11, 8);
      final max = DateTime(2027, 11, 8);
      expect(hasMonthBefore(2026, 11, min), isFalse);
      expect(hasMonthBefore(2026, 12, min), isTrue);
      expect(hasMonthAfter(2027, 11, max), isFalse);
      expect(hasMonthAfter(2027, 10, max), isTrue);
    });
  });

  group('arrow keys', () {
    final min = DateTime(2026, 11, 8);
    final max = DateTime(2027, 11, 8);
    DateTime move(DateTime d, DayKey k, {int first = DateTime.monday}) =>
        moveSelectedDay(d, k, min: min, max: max, firstWeekday: first);

    test('left and right move a day, up and down a week', () {
      final d = DateTime(2026, 12, 10);
      expect(move(d, .left), DateTime(2026, 12, 9));
      expect(move(d, .right), DateTime(2026, 12, 11));
      expect(move(d, .up), DateTime(2026, 12, 3));
      expect(move(d, .down), DateTime(2026, 12, 17));
    });

    test('page keys change the month and keep the day where they can', () {
      expect(move(DateTime(2027, 1, 31), .pageDown), DateTime(2027, 2, 28));
      expect(move(DateTime(2027, 3, 15), .pageUp), DateTime(2027, 2, 15));
    });

    test('home and end jump to the ends of the week', () {
      final thursday = DateTime(2026, 12, 10);
      expect(move(thursday, .home), DateTime(2026, 12, 7));
      expect(move(thursday, .end), DateTime(2026, 12, 13));
      expect(move(thursday, .home, first: DateTime.sunday), DateTime(2026, 12, 6));
    });

    test('a move past the range ends stops at the edge', () {
      expect(move(DateTime(2026, 11, 8), .left), DateTime(2026, 11, 8));
      expect(move(DateTime(2027, 11, 8), .down), DateTime(2027, 11, 8));
      expect(move(DateTime(2026, 11, 10), .pageUp), DateTime(2026, 11, 8));
    });
  });

  group('stepping', () {
    test('hours and minutes wrap at their limits', () {
      expect(wrapStep(23, 1, 24), 0);
      expect(wrapStep(0, -1, 24), 23);
      expect(wrapStep(59, 1, 60), 0);
      expect(wrapStep(0, -1, 60), 59);
      expect(wrapStep(10, 5, 60), 15);
    });
  });

  group('typed time', () {
    TypedTime? p(String s, {bool is24 = false}) => parseTypedTime(s, is24Hour: is24);

    test('"930p" is 9:30 PM', () {
      expect(p('930p'), (hour: 21, minute: 30, needsMeridiem: false));
    });

    test('colon, space and am/pm spellings', () {
      expect(p('9:30 pm'), (hour: 21, minute: 30, needsMeridiem: false));
      expect(p('9.30PM'), (hour: 21, minute: 30, needsMeridiem: false));
      expect(p('12:05 a'), (hour: 0, minute: 5, needsMeridiem: false));
      expect(p('12 pm'), (hour: 12, minute: 0, needsMeridiem: false));
    });

    test('twenty-four hour input is read as it is', () {
      expect(p('21:00'), (hour: 21, minute: 0, needsMeridiem: false));
      expect(p('0930', is24: true), (hour: 9, minute: 30, needsMeridiem: false));
      expect(p('9', is24: true), (hour: 9, minute: 0, needsMeridiem: false));
    });

    test('a 12-hour field with no a or p asks the caller to keep the current meridiem', () {
      expect(p('9'), (hour: 9, minute: 0, needsMeridiem: true));
      expect(p('12:15'), (hour: 0, minute: 15, needsMeridiem: true));
    });

    test('out-of-range numbers clamp, nothing throws', () {
      expect(p('9:75'), (hour: 9, minute: 59, needsMeridiem: true));
      expect(p('99', is24: true), (hour: 23, minute: 0, needsMeridiem: false));
      expect(p('99'), (hour: 23, minute: 0, needsMeridiem: false));
    });

    test('no digits or too many is not a time', () {
      expect(p(''), isNull);
      expect(p('abc'), isNull);
      expect(p('12345'), isNull);
      expect(p('1:2:3'), isNull);
    });
  });
  group('words', () {
    test('daysBetween counts calendar days, not 24-hour spans', () {
      expect(daysBetween(DateTime(2027, 3, 13, 23), DateTime(2027, 3, 15, 1)), 2);
      expect(daysBetween(DateTime(2027, 3, 15), DateTime(2027, 3, 15, 23)), 0);
    });

    test('headline says Today, spares this year, and adds another year', () {
      final today = DateTime(2026, 11, 8);
      expect(pickerHeadline(DateTime(2026, 11, 8), today), 'Today, Sun 8 Nov');
      expect(pickerHeadline(DateTime(2026, 11, 14), today), 'Saturday 14 November');
      expect(pickerHeadline(DateTime(2027, 3, 12), today), 'Friday 12 March 2027');
    });

    test('clock text in both clocks', () {
      expect(clockText(21, 0, is24Hour: false), '9:00 PM');
      expect(clockText(0, 5, is24Hour: false), '12:05 AM');
      expect(clockText(12, 30, is24Hour: false), '12:30 PM');
      expect(clockText(9, 5, is24Hour: true), '09:05');
    });
  });
}
