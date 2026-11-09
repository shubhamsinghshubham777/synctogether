/// The decisions behind `PTDateTimePicker`, as free functions over plain values so
/// they can be tested without a widget or a time zone.
library;

/// Builds a local moment the way `DateTime.new` does. Tests pass a fake zone.
typedef LocalBuilder = DateTime Function(int year, int month, int day, int hour, int minute);

DateTime _local(int y, int mo, int d, int h, int mi) => DateTime(y, mo, d, h, mi);

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime minuteFloor(DateTime d) => DateTime(d.year, d.month, d.day, d.hour, d.minute);

int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// A moment is allowed between [min] and [max] inclusive.
enum MomentCheck { ok, past, tooFar }

MomentCheck checkMoment(DateTime moment, {required DateTime min, required DateTime max}) {
  if (moment.isBefore(min)) return .past;
  if (moment.isAfter(max)) return .tooFar;
  return .ok;
}

/// An existing value outside the range is pulled to the nearest edge before the
/// picker opens.
DateTime clampMoment(DateTime moment, {required DateTime min, required DateTime max}) {
  if (moment.isBefore(min)) return min;
  if (moment.isAfter(max)) return max;
  return moment;
}

class ResolvedMoment {
  const ResolvedMoment(this.moment, {required this.movedForGap});

  final DateTime moment;

  /// The requested clock time does not exist that day (the clocks jump forward),
  /// so [moment] is the first valid time after it.
  final bool movedForGap;
}

/// Turns a chosen date and clock time into a real local moment. A time that falls
/// inside a spring-forward gap becomes the first valid time after it. A repeated
/// hour (clocks fall back) is left to the platform, which takes the first one.
ResolvedMoment resolveMoment(
  int year,
  int month,
  int day,
  int hour,
  int minute, {
  LocalBuilder build = _local,
}) {
  bool same(DateTime t, int d, int h, int mi) => t.day == d && t.hour == h && t.minute == mi;
  final direct = build(year, month, day, hour, minute);
  if (same(direct, day, hour, minute)) return ResolvedMoment(direct, movedForGap: false);
  for (var step = 1; step <= 180; step++) {
    final total = hour * 60 + minute + step;
    final h = total ~/ 60;
    if (h > 23) break;
    final m = total % 60;
    final t = build(year, month, day, h, m);
    if (same(t, day, h, m)) return ResolvedMoment(t, movedForGap: true);
  }
  return ResolvedMoment(direct, movedForGap: true);
}

/// The cells of one month, row by row, with null padding before the 1st and after
/// the last day so the length is a whole number of weeks. [firstWeekday] is a
/// `DateTime.monday`..`DateTime.sunday` value.
List<DateTime?> monthCells(int year, int month, {int firstWeekday = DateTime.monday}) {
  final lead = (DateTime(year, month).weekday - firstWeekday + 7) % 7;
  final count = daysInMonth(year, month);
  final total = ((lead + count + 6) ~/ 7) * 7;
  return [
    for (var i = 0; i < total; i++)
      i < lead || i >= lead + count ? null : DateTime(year, month, i - lead + 1),
  ];
}

/// Weekday numbers in column order for a week that starts on [firstWeekday].
List<int> weekdayOrder(int firstWeekday) => [
  for (var i = 0; i < 7; i++) (firstWeekday - 1 + i) % 7 + 1,
];

/// Whether the month grid has a month before / after this one inside the range.
bool hasMonthBefore(int year, int month, DateTime min) =>
    DateTime(year, month).isAfter(DateTime(min.year, min.month));

bool hasMonthAfter(int year, int month, DateTime max) =>
    DateTime(year, month).isBefore(DateTime(max.year, max.month));

enum DayKey { left, right, up, down, pageUp, pageDown, home, end }

/// Where an arrow key moves the selected day. Days outside the range are greyed,
/// so a move that would land on one stays within the range instead.
DateTime moveSelectedDay(
  DateTime day,
  DayKey key, {
  required DateTime min,
  required DateTime max,
  int firstWeekday = DateTime.monday,
}) {
  final d = dateOnly(day);
  final DateTime moved = switch (key) {
    .left => DateTime(d.year, d.month, d.day - 1),
    .right => DateTime(d.year, d.month, d.day + 1),
    .up => DateTime(d.year, d.month, d.day - 7),
    .down => DateTime(d.year, d.month, d.day + 7),
    .pageUp => _shiftMonth(d, -1),
    .pageDown => _shiftMonth(d, 1),
    .home => DateTime(d.year, d.month, d.day - (d.weekday - firstWeekday + 7) % 7),
    .end => DateTime(d.year, d.month, d.day + 6 - (d.weekday - firstWeekday + 7) % 7),
  };
  final lo = dateOnly(min);
  final hi = dateOnly(max);
  if (moved.isBefore(lo)) return lo;
  if (moved.isAfter(hi)) return hi;
  return moved;
}

DateTime _shiftMonth(DateTime d, int delta) {
  final target = DateTime(d.year, d.month + delta);
  final last = daysInMonth(target.year, target.month);
  return DateTime(target.year, target.month, d.day > last ? last : d.day);
}

/// Steps [value] by [delta] and wraps inside 0..[size]-1 (hours 24, minutes 60).
int wrapStep(int value, int delta, int size) => ((value + delta) % size + size) % size;

/// What a typed time means. [hour] is 0-23 when [needsMeridiem] is false. When it
/// is true (12-hour field, no "a" or "p" typed) [hour] is 0-11 and the caller adds
/// 12 if the field is currently on PM.
typedef TypedTime = ({int hour, int minute, bool needsMeridiem});

/// A forgiving reading of what someone typed into the time field: "930p", "9:30 pm",
/// "21:00", "9", "0930". Out-of-range numbers clamp to their limit. Returns null
/// when there are no digits to read.
TypedTime? parseTypedTime(String input, {required bool is24Hour}) {
  final s = input.trim().toLowerCase();
  final suffix = RegExp(r'([ap])\.?m?\.?$').firstMatch(s);
  final pm = suffix?.group(1) == 'p';
  final hasSuffix = suffix != null;
  final body = (hasSuffix ? s.substring(0, suffix.start) : s).replaceAll(RegExp(r'[^0-9:. ]'), '');
  final parts = body.split(RegExp(r'[:. ]+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty || parts.length > 2) return null;
  int h;
  int m;
  if (parts.length == 2) {
    h = int.parse(parts[0]);
    m = int.parse(parts[1]);
  } else {
    final p = parts[0];
    if (p.length <= 2) {
      h = int.parse(p);
      m = 0;
    } else if (p.length == 3) {
      h = int.parse(p.substring(0, 1));
      m = int.parse(p.substring(1));
    } else if (p.length == 4) {
      h = int.parse(p.substring(0, 2));
      m = int.parse(p.substring(2));
    } else {
      return null;
    }
  }
  m = m.clamp(0, 59);
  if (hasSuffix && !is24Hour) {
    final h12 = h.clamp(1, 12) % 12;
    return (hour: h12 + (pm ? 12 : 0), minute: m, needsMeridiem: false);
  }
  if (is24Hour || h > 12) return (hour: h.clamp(0, 23), minute: m, needsMeridiem: false);
  return (hour: h % 12, minute: m, needsMeridiem: true);
}

/// Whole calendar days from [a] to [b], ignoring the time of day and any daylight
/// saving shift in between.
int daysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

const _weekdaysLong = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const _monthsLong = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String weekdayLong(int weekday) => _weekdaysLong[weekday - 1];

String weekdayShort(int weekday) => _weekdaysLong[weekday - 1].substring(0, 3);

String monthLong(int month) => _monthsLong[month - 1];

String monthShort(int month) => _monthsLong[month - 1].substring(0, 3);

/// "Sat 14 Nov": a wheel row.
String dayRowLabel(DateTime d) => '${weekdayShort(d.weekday)} ${d.day} ${monthShort(d.month)}';

/// The picker's headline: "Today, Sun 8 Nov", "Saturday 14 November", and the year
/// when it is not this one.
String pickerHeadline(DateTime day, DateTime today) {
  if (dateOnly(day) == dateOnly(today)) return 'Today, ${dayRowLabel(day)}';
  final long = '${_weekdaysLong[day.weekday - 1]} ${day.day} ${monthLong(day.month)}';
  return day.year == today.year ? long : '$long ${day.year}';
}

/// "9:30 PM", or "21:30" on a 24-hour clock.
String clockText(int hour, int minute, {required bool is24Hour}) {
  final m = minute.toString().padLeft(2, '0');
  if (is24Hour) return '${hour.toString().padLeft(2, '0')}:$m';
  final h = hour % 12 == 0 ? 12 : hour % 12;
  return '$h:$m ${hour < 12 ? 'AM' : 'PM'}';
}
