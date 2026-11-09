import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'pair_models.dart';

// Everything a pair screen has to *decide* lives here as free functions over
// plain values - time zones, countdowns, who answers which date night, how long
// two people were together - so the decisions are tested without a widget or a
// backend. The widgets only draw what these return.

bool _zonesReady = false;

/// The IANA database the offset maths needs. Cheap and idempotent.
void ensureTimeZones() {
  if (_zonesReady) return;
  tzdata.initializeTimeZones();
  _zonesReady = true;
}

tz.Location? locationOf(String? name) {
  if (name == null || name.isEmpty) return null;
  ensureTimeZones();
  try {
    return tz.getLocation(name);
  } catch (_) {
    return null;
  }
}

/// [at] as the wall clock in [zone], or null for an unknown zone. The result is
/// a `TZDateTime`: read `.hour`, `.minute`, `.day` from it, never `.toLocal()`.
tz.TZDateTime? wallClockIn(String? zone, DateTime at) {
  final loc = locationOf(zone);
  return loc == null ? null : tz.TZDateTime.from(at.toUtc(), loc);
}

/// Partner minus me at [at], in whole minutes' precision. Null when the
/// partner's zone is unknown. "Me" is the device's own offset rather than a
/// stored zone name, because what the person sees on their own clock is the
/// thing being compared.
Duration? offsetFromMe(String? partnerZone, DateTime at) {
  final theirs = wallClockIn(partnerZone, at);
  if (theirs == null) return null;
  return theirs.timeZoneOffset - at.toLocal().timeZoneOffset;
}

/// The partner's clock is only worth showing when it is a different clock.
/// Two people in the same zone get no time row at all.
bool shouldShowPartnerTime(String? partnerZone, DateTime at) {
  final diff = offsetFromMe(partnerZone, at);
  return diff != null && diff != Duration.zero;
}

/// "5 h behind", "9 h 30 min ahead". Empty for no difference.
String offsetLabel(Duration diff) {
  if (diff == Duration.zero) return '';
  final minutes = diff.inMinutes.abs();
  final h = minutes ~/ 60;
  final m = minutes % 60;
  final amount = [if (h > 0) '$h h', if (m > 0) '$m min'].join(' ');
  return '$amount ${diff.isNegative ? 'behind' : 'ahead'}';
}

/// "4:12 PM"
String formatClock(DateTime wall) {
  final h = wall.hour % 12 == 0 ? 12 : wall.hour % 12;
  final m = wall.minute.toString().padLeft(2, '0');
  return '$h:$m ${wall.hour < 12 ? 'AM' : 'PM'}';
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "Sat 14 Nov"
String formatDay(DateTime wall) =>
    '${_weekdays[wall.weekday - 1]} ${wall.day} ${_months[wall.month - 1]}';

/// "SUN" - the history tile's weekday.
String weekdayShort(DateTime wall) => _weekdays[wall.weekday - 1].toUpperCase();

/// "Sat 14 Nov · 9:00 PM"
String formatMoment(DateTime wall) => '${formatDay(wall)} · ${formatClock(wall)}';

/// `Europe/London` -> `London`, `America/Argentina/Buenos_Aires` -> `Buenos Aires`.
String cityOfZone(String? zone) {
  if (zone == null || zone.isEmpty) return '';
  return zone.split('/').last.replaceAll('_', ' ');
}

/// Whether someone is plausibly awake: 7 AM up to 10 PM on their own clock.
bool isAwakeHour(int hour) => hour >= 7 && hour < 22;

/// How a proposed time lands on each person's clock - what the date-night
/// planner draws as two 24-hour strips.
class NightPlacement {
  const NightPlacement({
    required this.mine,
    required this.theirs,
    required this.myCity,
    required this.theirCity,
    required this.zonesDiffer,
  });

  /// Wall clocks. [theirs] is null when the partner's zone is unknown, in which
  /// case only one strip is drawn.
  final DateTime mine;
  final DateTime? theirs;
  final String myCity;
  final String theirCity;
  final bool zonesDiffer;

  bool get meAwake => isAwakeHour(mine.hour);
  bool get theyAwake => theirs == null || isAwakeHour(theirs!.hour);

  /// The warning the planner shows before sending: never a block.
  bool get lateForThem => theirs != null && !theyAwake;
}

NightPlacement placeNight(DateTime startsAt, {required String? partnerZone, String? myZone}) {
  final mine = startsAt.toLocal();
  final theirs = wallClockIn(partnerZone, startsAt);
  return NightPlacement(
    mine: mine,
    theirs: theirs,
    myCity: cityOfZone(myZone),
    theirCity: cityOfZone(partnerZone),
    zonesDiffer: shouldShowPartnerTime(partnerZone, startsAt),
  );
}

/// Where in the answer chain a date night sits, for the viewer.
enum NightStanding {
  /// I proposed it and the other person has not answered.
  awaitingThem,

  /// They proposed it (or moved it) and I have not answered.
  awaitingMe,
  accepted,
  declined,
  cancelled,

  /// Accepted, and already past.
  done,
}

NightStanding nightStanding(DateTime now, DateNight night, String myId) {
  switch (night.status) {
    case .cancelled:
      return .cancelled;
    case .declined:
      return .declined;
    case .accepted:
      // The same half hour of grace the list gives a night that has just started, so
      // "starting now" is still an accepted night, not one already in the history.
      return night.startsAt.isBefore(now.subtract(const Duration(minutes: 30))) ? .done : .accepted;
    case .proposed:
      return night.proposedBy == myId ? .awaitingThem : .awaitingMe;
  }
}

/// Nights to list under "Coming up": still ahead (or in the last half hour),
/// not cancelled or declined, soonest first.
List<DateNight> upcomingNights(DateTime now, Iterable<DateNight> nights) {
  final cutoff = now.subtract(const Duration(minutes: 30));
  return [
    for (final n in nights)
      if (n.startsAt.isAfter(cutoff) &&
          n.status != DateNightStatus.cancelled &&
          n.status != DateNightStatus.declined)
        n,
  ]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
}

/// Cancelled and declined nights stay on the list for two days after the change, newest
/// first, so the other person sees what happened (and can plan another) before it goes.
List<DateNight> recentlyEndedNights(DateTime now, Iterable<DateNight> nights) {
  final cutoff = now.subtract(const Duration(hours: 48));
  return [
    for (final n in nights)
      if ((n.status == DateNightStatus.cancelled || n.status == DateNightStatus.declined) &&
          n.updatedAt != null &&
          n.updatedAt!.isAfter(cutoff))
        n,
  ]..sort((a, b) => b.updatedAt!.compareTo(a.updatedAt!));
}

/// The date night the lobby card should feature: the next accepted one that is
/// today or sooner than a day away, and the minutes until it.
DateNight? featuredNight(DateTime now, Iterable<DateNight> nights) {
  for (final n in upcomingNights(now, nights)) {
    if (n.status == DateNightStatus.accepted &&
        n.startsAt.difference(now) < const Duration(hours: 24)) {
      return n;
    }
  }
  return null;
}

/// Inside the last quarter hour (and the half hour after): the only window in
/// which the card takes Beam, because amber is for live things.
bool isNightImminent(DateTime now, DateNight night) {
  final until = night.startsAt.difference(now);
  return until <= const Duration(minutes: 15) && until >= const Duration(minutes: -30);
}

class CountdownParts {
  const CountdownParts(this.days, this.hours, this.minutes);
  final int days;
  final int hours;
  final int minutes;

  /// `2d 3h 12m`, dropping leading zeros: `3h 12m`, `12m`.
  String get label {
    if (days > 0) return '${days}d ${hours}h ${minutes}m';
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }
}

CountdownParts countdownTo(DateTime target, DateTime now) {
  var d = target.difference(now);
  if (d.isNegative) d = Duration.zero;
  return CountdownParts(d.inDays, d.inHours % 24, d.inMinutes % 60);
}

enum ReunionPhase {
  /// Eight or more days out: calm numerals.
  distant,

  /// Under eight days: days and hours.
  near,
  tomorrow,
  today,

  /// More than a day gone: the card retires.
  past,
}

class ReunionView {
  const ReunionView(this.phase, this.daysLeft, {this.wholeDays = 0, this.hoursPart = 0});
  final ReunionPhase phase;

  /// Exact time to the start of the reunion day, as whole days and the hours after them.
  /// Only the near phase shows it ("3 days 11 h"); the distant one stays on calendar days.
  final int wholeDays;
  final int hoursPart;

  /// Whole calendar days, by the device's own date. Negative once it has passed.
  final int daysLeft;
}

/// Calendar days to a reunion date, ignoring the time of day: "47 days" must
/// not flip to 46 at some arbitrary hour.
ReunionView reunionView(DateTime reunionOn, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(reunionOn.year, reunionOn.month, reunionOn.day);
  final left = day.difference(today).inDays;
  final phase = left < -1
      ? ReunionPhase.past
      : left <= 0
      ? ReunionPhase.today
      : left == 1
      ? ReunionPhase.tomorrow
      : left < 8
      ? ReunionPhase.near
      : ReunionPhase.distant;
  final span = day.difference(now);
  return ReunionView(
    phase,
    left,
    wholeDays: span.isNegative ? 0 : span.inDays,
    hoursPart: span.isNegative ? 0 : span.inHours % 24,
  );
}

/// Time two people spend in Our Room *together*: the clock runs only while both
/// are present. The room feeds it every presence change; it hands back the
/// sitting to log when someone leaves.
class TogetherClock {
  DateTime? _runningSince;
  Duration _accrued = Duration.zero;
  DateTime? _firstTogether;

  /// When both were first present this sitting, or null if they never were.
  DateTime? get startedAt => _firstTogether;

  void update(DateTime now, {required bool together}) {
    if (together) {
      _runningSince ??= now;
      _firstTogether ??= now;
    } else if (_runningSince != null) {
      _accrued += now.difference(_runningSince!);
      _runningSince = null;
    }
  }

  Duration total(DateTime now) =>
      _accrued + (_runningSince == null ? Duration.zero : now.difference(_runningSince!));

  void reset() {
    _runningSince = null;
    _firstTogether = null;
    _accrued = Duration.zero;
  }
}

/// A sitting worth logging is at least a minute, matching `log_pair_session`.
bool isLoggableSitting(Duration together) => together >= const Duration(minutes: 1);

String hoursLabel(double hours) =>
    hours == hours.roundToDouble() ? '${hours.round()}' : hours.toStringAsFixed(1);

/// "1 NIGHT", "2 NIGHTS" - the year card's stat labels.
String countLabel(int n, String singular, [String? plural]) =>
    '$n ${(n == 1 ? singular : (plural ?? '${singular}S')).toUpperCase()}';

/// Which months (1-12) of [year] had a night together, for the year card's film strip.
/// Counted in UTC, the same clock the server's own year stats use.
Set<int> watchedMonths(Iterable<PairSession> sessions, int year) => {
  for (final s in sessions)
    if (s.seconds >= 1200 && s.startedAt.toUtc().year == year) s.startedAt.toUtc().month,
};

String durationLabel(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  return h > 0 ? '${h}h ${m.toString().padLeft(2, '0')}m' : '${m}m';
}

/// RFC 5545 text escaping: backslash, semicolon, comma and newline.
String _icsText(String s) => s
    .replaceAll(r'\', r'\\')
    .replaceAll(';', r'\;')
    .replaceAll(',', r'\,')
    .replaceAll('\r\n', r'\n')
    .replaceAll('\n', r'\n');

String _icsStamp(DateTime t) {
  final u = t.toUtc();
  String p(int v, [int w = 2]) => v.toString().padLeft(w, '0');
  return '${p(u.year, 4)}${p(u.month)}${p(u.day)}T${p(u.hour)}${p(u.minute)}${p(u.second)}Z';
}

/// Content lines are folded at 75 octets, continuation lines starting with one
/// space. Folding is by character here, which is safe because the longest
/// multi-byte run we emit is a title already bounded to 120 characters.
List<String> _fold(String line) {
  if (line.length <= 73) return [line];
  final out = <String>[];
  var rest = line;
  var first = true;
  while (rest.isNotEmpty) {
    final take = first ? 73 : 72;
    out.add((first ? '' : ' ') + rest.substring(0, rest.length < take ? rest.length : take));
    rest = rest.length < take ? '' : rest.substring(take);
    first = false;
  }
  return out;
}

/// A calendar file for one date night. The start is written in UTC, so it lands
/// at the right moment in whichever calendar and zone opens it - which is the
/// whole point for two people in different zones. It carries a 15 minute alarm.
String buildDateNightIcs({
  required String id,
  required String title,
  required DateTime startsAt,
  required String withName,
  Duration length = const Duration(hours: 2),
  DateTime? now,
}) {
  final lines = <String>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//SyncTogether//Date night//EN',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'BEGIN:VEVENT',
    'UID:$id@synctogether',
    'DTSTAMP:${_icsStamp(now ?? DateTime.now())}',
    'DTSTART:${_icsStamp(startsAt)}',
    'DTEND:${_icsStamp(startsAt.add(length))}',
    'SUMMARY:${_icsText('Date night with $withName: $title')}',
    'DESCRIPTION:${_icsText('Watching $title together in Our Room.')}',
    'BEGIN:VALARM',
    'ACTION:DISPLAY',
    'DESCRIPTION:${_icsText('Date night in 15 minutes')}',
    'TRIGGER:-PT15M',
    'END:VALARM',
    'END:VEVENT',
    'END:VCALENDAR',
  ];
  return '${lines.expand(_fold).join('\r\n')}\r\n';
}

/// The year the recap covers: the current one, or the previous one in January
/// while the new year has nothing in it yet.
int recapYear(DateTime now, {required bool thisYearHasNights}) =>
    now.month == 1 && !thisYearHasNights ? now.year - 1 : now.year;

/// One CSV cell: quoted when it has a comma, quote or line break, quotes
/// doubled. A cell that would be read as a formula by a spreadsheet (`=`, `+`,
/// `-`, `@` first) is prefixed with an apostrophe, since a film title is typed
/// by a person and this file is opened in Excel.
String _csvCell(String v) {
  var s = v;
  if (s.isNotEmpty && '=+-@'.contains(s[0])) s = "'$s";
  if (s.contains(RegExp(r'[",\r\n]'))) s = '"${s.replaceAll('"', '""')}"';
  return s;
}

/// The export of everything you watched together, for anyone, on any plan.
String historyToCsv(Iterable<PairSession> sessions) {
  final rows = <String>['title,started_at_utc,minutes'];
  for (final s in sessions) {
    rows.add(
      [
        _csvCell(s.title ?? ''),
        s.startedAt.toUtc().toIso8601String(),
        (s.seconds / 60).round().toString(),
      ].join(','),
    );
  }
  return '${rows.join('\r\n')}\r\n';
}

/// "November 2026"
String monthHeading(DateTime t) {
  const names = [
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
  return '${names[t.month - 1]} ${t.year}';
}

/// What to call a sitting in the history: the file's name without its extension
/// (`Spirited.Away.2001.mkv` -> `Spirited Away 2001`), or null when there is no
/// name worth keeping. Only ever the basename - never a path.
String? sittingTitle(String? mediaName) {
  if (mediaName == null) return null;
  var name = mediaName.split(RegExp(r'[\\/]')).last.trim();
  final dot = name.lastIndexOf('.');
  // A real extension is short and has no spaces; "Mr. Robot" does not lose its end.
  if (dot > 0 && name.length - dot <= 5 && !name.substring(dot).contains(' ')) {
    name = name.substring(0, dot);
  }
  name = name.replaceAll(RegExp(r'[._]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return name.isEmpty ? null : name;
}

/// Whether [name] is no name at all: empty, or just the part of the email
/// before the `@` (which is what an account gets when its provider shared no
/// name - Sign in with Apple's hidden address yields a random handle).
bool isGenericName(String? name, String? email) {
  final n = (name ?? '').trim();
  if (n.isEmpty) return true;
  final local = (email ?? '').split('@').first.trim().toLowerCase();
  return local.isNotEmpty && n.toLowerCase() == local;
}

/// A starting point for the name field, from an ordinary address:
/// `sam.rivera92@x.com` gives "Sam Rivera". Empty when the local part is not
/// readable as a name - a random handle, one long run-together word, or an
/// Apple relay address - so the field starts blank rather than wrong.
String suggestedName(String? email) {
  final address = (email ?? '').trim().toLowerCase();
  if (address.isEmpty || address.endsWith('@privaterelay.appleid.com')) return '';
  final tokens = address
      .split('@')
      .first
      .replaceAll(RegExp(r'\d+'), ' ')
      .split(RegExp(r'[._+\-\s]+'))
      .where((t) => t.isNotEmpty)
      .toList();
  if (tokens.isEmpty || tokens.any((t) => t.length < 2)) return '';
  if (tokens.length == 1 && tokens.first.length > 12) return '';
  return tokens.map((t) => '${t[0].toUpperCase()}${t.substring(1)}').join(' ');
}

/// Where a date night's file stands, for the badge and the line under the ticket.
enum FileStage { none, uploading, unfinished, ready, stopped }

class FileView {
  const FileView({required this.stage, required this.percent, required this.fraction});

  final FileStage stage;

  /// Whole percent, never 100 until the upload is truly done.
  final int percent;
  final double fraction;
}

/// The night's file as it should be shown now. [liveFraction] and [liveStopped]
/// are what the planner's own device knows first-hand, ahead of what it last
/// reported to the night; the partner passes neither and reads the night.
///
/// "Unfinished" is an upload still going once the night's window has opened
/// (15 minutes before): the room opens on time regardless, so the words change
/// from "uploading" to "still uploading", and nothing blocks.
FileView fileViewOf(DateNight night, DateTime now, {double? liveFraction, bool? liveStopped}) {
  if (!night.hasFile) return const FileView(stage: FileStage.none, percent: 0, fraction: 0);
  if (night.fileReady) return const FileView(stage: FileStage.ready, percent: 100, fraction: 1);
  final fraction = (liveFraction ?? night.uploadFraction).clamp(0.0, 1.0);
  final percent = (fraction * 100).floor().clamp(0, 99);
  final stopped = liveStopped ?? night.fileStopped;
  if (stopped) return FileView(stage: FileStage.stopped, percent: percent, fraction: fraction);
  final windowOpen = !now.isBefore(night.startsAt.subtract(const Duration(minutes: 15)));
  return FileView(
    stage: windowOpen ? FileStage.unfinished : FileStage.uploading,
    percent: percent,
    fraction: fraction,
  );
}
