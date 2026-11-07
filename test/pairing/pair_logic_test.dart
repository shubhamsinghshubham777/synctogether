import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/pairing/pair_logic.dart';
import 'package:synctogether/pairing/pair_models.dart';
import 'package:timezone/timezone.dart' as tz;

DateNight night({
  String proposedBy = 'sam',
  DateNightStatus status = .proposed,
  DateTime? at,
  String id = 'n1',
}) => DateNight(
  id: id,
  title: 'Spirited Away',
  startsAt: at ?? DateTime.utc(2026, 11, 14, 21),
  proposedBy: proposedBy,
  status: status,
);

void main() {
  group('time zones', () {
    // 2026-11-14: London is on GMT (+0), New York on EST (-5), Kolkata +5:30.
    final at = DateTime.utc(2026, 11, 14, 21);

    test('an unknown zone is simply unknown, not a crash', () {
      expect(locationOf('Mars/Olympus'), isNull);
      expect(locationOf(null), isNull);
      expect(offsetFromMe('Mars/Olympus', at), isNull);
      expect(shouldShowPartnerTime(null, at), isFalse);
    });

    test('the offset is partner minus the device clock', () {
      final device = at.toLocal().timeZoneOffset;
      expect(offsetFromMe('America/New_York', at), const Duration(hours: -5) - device);
      expect(offsetFromMe('Asia/Kolkata', at), const Duration(hours: 5, minutes: 30) - device);
    });

    test('a partner on the same clock gets no time row, a different one does', () {
      ensureTimeZones();
      final device = at.toLocal().timeZoneOffset;
      final same = tz.timeZoneDatabase.locations.values.firstWhere(
        (l) => tz.TZDateTime.from(at, l).timeZoneOffset == device,
      );
      expect(shouldShowPartnerTime(same.name, at), isFalse);
      final other = tz.timeZoneDatabase.locations.values.firstWhere(
        (l) => tz.TZDateTime.from(at, l).timeZoneOffset != device,
      );
      expect(shouldShowPartnerTime(other.name, at), isTrue);
    });

    test('daylight saving is read at the moment in question, not today', () {
      final summer = DateTime.utc(2026, 7, 14, 21);
      expect(wallClockIn('America/New_York', summer)!.timeZoneOffset, const Duration(hours: -4));
      expect(wallClockIn('America/New_York', at)!.timeZoneOffset, const Duration(hours: -5));
    });

    test('offset labels read naturally', () {
      expect(offsetLabel(const Duration(hours: -5)), '5 h behind');
      expect(offsetLabel(const Duration(hours: 9, minutes: 30)), '9 h 30 min ahead');
      expect(offsetLabel(const Duration(minutes: 45)), '45 min ahead');
      expect(offsetLabel(Duration.zero), '');
    });

    test('clock and day formats', () {
      expect(formatClock(DateTime(2026, 11, 14, 0, 5)), '12:05 AM');
      expect(formatClock(DateTime(2026, 11, 14, 12, 0)), '12:00 PM');
      expect(formatClock(DateTime(2026, 11, 14, 21, 30)), '9:30 PM');
      expect(formatDay(DateTime(2026, 11, 14)), 'Sat 14 Nov');
      expect(formatMoment(DateTime(2026, 11, 14, 21)), 'Sat 14 Nov · 9:00 PM');
      expect(cityOfZone('America/Argentina/Buenos_Aires'), 'Buenos Aires');
      expect(cityOfZone(null), '');
    });
  });

  group('placing a night', () {
    test('9 PM in London is 4 PM in New York, and they are awake', () {
      final p = placeNight(DateTime.utc(2026, 11, 14, 21), partnerZone: 'America/New_York');
      expect(p.theirs!.hour, 16);
      expect(p.theyAwake, isTrue);
      expect(p.lateForThem, isFalse);
      expect(p.theirCity, 'New York');
    });

    test('a time that lands in their night is flagged, never blocked', () {
      final p = placeNight(DateTime.utc(2026, 11, 14, 9), partnerZone: 'America/New_York');
      expect(p.theirs!.hour, 4);
      expect(p.lateForThem, isTrue);
    });

    test('with no partner zone nothing is flagged and one strip is enough', () {
      final p = placeNight(DateTime.utc(2026, 11, 14, 3), partnerZone: null);
      expect(p.theirs, isNull);
      expect(p.lateForThem, isFalse);
      expect(p.zonesDiffer, isFalse);
    });

    test('awake means 7 AM to 10 PM', () {
      expect([6, 7, 21, 22].map(isAwakeHour), [false, true, true, false]);
    });
  });

  group('who answers a date night', () {
    final now = DateTime.utc(2026, 11, 14, 12);

    test('the proposer waits, the other person answers', () {
      expect(nightStanding(now, night(proposedBy: 'me'), 'me'), NightStanding.awaitingThem);
      expect(nightStanding(now, night(proposedBy: 'sam'), 'me'), NightStanding.awaitingMe);
    });

    test('moving a night hands the answer to the other person', () {
      // Sam proposed, I moved it: it is now mine proposing, so Sam answers.
      expect(nightStanding(now, night(proposedBy: 'me'), 'sam'), NightStanding.awaitingMe);
    });

    test('accepted becomes done once it is past', () {
      final past = night(status: .accepted, at: now.subtract(const Duration(hours: 3)));
      expect(nightStanding(now, past, 'me'), NightStanding.done);
      expect(nightStanding(now, night(status: .accepted), 'me'), NightStanding.accepted);
      expect(nightStanding(now, night(status: .cancelled), 'me'), NightStanding.cancelled);
      expect(nightStanding(now, night(status: .declined), 'me'), NightStanding.declined);
    });

    test('upcoming skips cancelled, declined and long-gone nights, soonest first', () {
      final list = upcomingNights(now, [
        night(id: 'late', status: .accepted, at: now.add(const Duration(days: 3))),
        night(id: 'soon', status: .accepted, at: now.add(const Duration(hours: 5))),
        night(id: 'gone', status: .accepted, at: now.subtract(const Duration(hours: 3))),
        night(id: 'cx', status: .cancelled, at: now.add(const Duration(hours: 1))),
        night(id: 'no', status: .declined, at: now.add(const Duration(hours: 1))),
        night(id: 'asked', at: now.add(const Duration(days: 1))),
      ]);
      expect(list.map((n) => n.id), ['soon', 'asked', 'late']);
    });

    test('the lobby features only an accepted night within a day, Beam only inside 15 minutes', () {
      final soon = night(status: .accepted, at: now.add(const Duration(hours: 6)));
      expect(featuredNight(now, [soon]), same(soon));
      expect(
        featuredNight(now, [night(status: .accepted, at: now.add(const Duration(days: 2)))]),
        isNull,
      );
      expect(featuredNight(now, [night(at: now.add(const Duration(hours: 1)))]), isNull);
      expect(isNightImminent(now, night(at: now.add(const Duration(minutes: 14)))), isTrue);
      expect(isNightImminent(now, night(at: now.add(const Duration(minutes: 16)))), isFalse);
      expect(isNightImminent(now, night(at: now.subtract(const Duration(minutes: 20)))), isTrue);
      expect(isNightImminent(now, night(at: now.subtract(const Duration(minutes: 40)))), isFalse);
    });
  });

  group('countdowns', () {
    test('parts and labels', () {
      final now = DateTime.utc(2026, 11, 12, 18);
      final c = countdownTo(DateTime.utc(2026, 11, 14, 21, 12), now);
      expect([c.days, c.hours, c.minutes], [2, 3, 12]);
      expect(c.label, '2d 3h 12m');
      expect(countdownTo(now.add(const Duration(hours: 3, minutes: 5)), now).label, '3h 5m');
      expect(countdownTo(now.add(const Duration(minutes: 9)), now).label, '9m');
      expect(countdownTo(now.subtract(const Duration(hours: 1)), now).label, '0m');
    });

    test('a reunion counts calendar days, whatever the hour', () {
      final reunion = DateTime(2026, 12, 26);
      expect(reunionView(reunion, DateTime(2026, 11, 9, 0, 1)).daysLeft, 47);
      expect(reunionView(reunion, DateTime(2026, 11, 9, 23, 59)).daysLeft, 47);
    });

    test('phases: distant, near, tomorrow, today, then it retires', () {
      final reunion = DateTime(2026, 12, 26);
      ReunionPhase at(int dayOfDec) => reunionView(reunion, DateTime(2026, 12, dayOfDec, 10)).phase;
      expect(reunionView(reunion, DateTime(2026, 11, 9)).phase, ReunionPhase.distant);
      expect(
        reunionView(reunion, DateTime(2026, 12, 18)).phase,
        ReunionPhase.distant,
        reason: '8 days',
      );
      expect(at(19), ReunionPhase.near);
      expect(at(25), ReunionPhase.tomorrow);
      expect(at(26), ReunionPhase.today);
      expect(at(27), ReunionPhase.today, reason: 'still today for the day after, the card lingers');
      expect(at(28), ReunionPhase.past);
    });
  });

  group('TogetherClock', () {
    final t0 = DateTime.utc(2026, 11, 14, 21);

    test('counts only the time both were present', () {
      final c = TogetherClock();
      c.update(t0, together: false);
      c.update(t0.add(const Duration(minutes: 5)), together: true);
      c.update(t0.add(const Duration(minutes: 35)), together: false);
      c.update(t0.add(const Duration(minutes: 50)), together: true);
      expect(c.total(t0.add(const Duration(minutes: 60))), const Duration(minutes: 40));
      expect(c.startedAt, t0.add(const Duration(minutes: 5)));
    });

    test('repeated "together" updates do not restart the run', () {
      final c = TogetherClock();
      c.update(t0, together: true);
      c.update(t0.add(const Duration(minutes: 10)), together: true);
      expect(c.total(t0.add(const Duration(minutes: 20))), const Duration(minutes: 20));
    });

    test('never together means nothing to log; under a minute does not count', () {
      final c = TogetherClock();
      c.update(t0, together: false);
      expect(c.startedAt, isNull);
      expect(isLoggableSitting(c.total(t0.add(const Duration(hours: 1)))), isFalse);
      expect(isLoggableSitting(const Duration(seconds: 59)), isFalse);
      expect(isLoggableSitting(const Duration(minutes: 1)), isTrue);
    });

    test('reset starts a fresh sitting', () {
      final c = TogetherClock()..update(t0, together: true);
      c.reset();
      expect(c.total(t0.add(const Duration(hours: 1))), Duration.zero);
      expect(c.startedAt, isNull);
    });
  });

  group('calendar file', () {
    test('is RFC 5545 shaped: UTC start, alarm, CRLF, escaped text', () {
      final ics = buildDateNightIcs(
        id: 'abc',
        title: 'Aftersun, the one; with sand',
        startsAt: DateTime.utc(2026, 11, 14, 21),
        withName: 'Sam',
        now: DateTime.utc(2026, 11, 7, 9, 30, 5),
      );
      expect(ics, startsWith('BEGIN:VCALENDAR\r\n'));
      expect(ics, endsWith('END:VCALENDAR\r\n'));
      expect(ics, contains('DTSTART:20261114T210000Z\r\n'));
      expect(ics, contains('DTEND:20261114T230000Z\r\n'));
      expect(ics, contains('DTSTAMP:20261107T093005Z\r\n'));
      expect(ics, contains('TRIGGER:-PT15M\r\n'));
      expect(ics, contains(r'Aftersun\, the one\; with sand'));
      expect(RegExp(r'(?<!\r)\n').hasMatch(ics), isFalse, reason: 'every line break is CRLF');
    });

    test('long lines fold at 75 octets with a leading space', () {
      final ics = buildDateNightIcs(
        id: 'x',
        title: 'A very long film title ' * 4,
        startsAt: DateTime.utc(2026, 11, 14, 21),
        withName: 'Sam',
      );
      for (final line in ics.split('\r\n')) {
        expect(line.length, lessThanOrEqualTo(75));
      }
      expect(ics, contains('\r\n '));
    });
  });

  group('recap year', () {
    test('January with nothing yet recaps last year', () {
      expect(recapYear(DateTime(2027, 1, 3), thisYearHasNights: false), 2026);
      expect(recapYear(DateTime(2027, 1, 3), thisYearHasNights: true), 2027);
      expect(recapYear(DateTime(2026, 11, 7), thisYearHasNights: false), 2026);
    });
  });

  group('labels', () {
    test('hours and durations', () {
      expect(hoursLabel(112), '112');
      expect(hoursLabel(112.4), '112.4');
      expect(durationLabel(7500), '2h 05m');
      expect(durationLabel(2400), '40m');
    });
  });

  group('error copy', () {
    test('every server code maps to friendly copy, unknown falls back', () {
      expect(
        PairErrorCode.fromError(Exception('PostgrestException: invite_expired')),
        PairErrorCode.inviteExpired,
      );
      expect(PairErrorCode.fromError('patron_required'), PairErrorCode.patronRequired);
      expect(PairErrorCode.fromError('boom'), PairErrorCode.unknown);
      for (final c in PairErrorCode.values) {
        expect(c.message, isNot(contains('_')), reason: 'no raw codes in copy: ${c.code}');
      }
    });
  });

  group('models', () {
    test('my_pair parses, including a calendar-day reunion', () {
      final p = PairInfo.fromJson({
        'pair_id': 'p',
        'since': '2026-03-02T10:00:00Z',
        'reunion_on': '2026-12-26',
        'reunion_label': 'Heathrow',
        'patron': true,
        'room_id': 'r',
        'room_code': 'ABCDEF',
        'partner': {'id': 's', 'display_name': 'Sam', 'timezone': 'America/New_York'},
      });
      expect(p.partner.displayName, 'Sam');
      expect(p.reunionOn, DateTime(2026, 12, 26));
      expect(p.patron, isTrue);
    });

    test('an invite is live only while pending and unexpired', () {
      final inv = PairInvite.fromJson({
        'code': 'M4YA7K',
        'status': 'pending',
        'expires_at': '2026-11-09T10:00:00Z',
        'inviter': {'id': 'm', 'display_name': 'Maya'},
      });
      expect(inv.isLiveAt(DateTime.utc(2026, 11, 8)), isTrue);
      expect(inv.isLiveAt(DateTime.utc(2026, 11, 10)), isFalse);
      expect(PairInviteStatus.fromWire('weird'), PairInviteStatus.pending);
    });

    test('push prefs: server defaults, and one key changes only itself', () {
      final p = PushPrefs.fromJson(const {});
      expect(
        [p.calls, p.dateNights, p.watchlist, p.reunion, p.quietHours],
        [true, true, false, true, true],
      );
      final q = p.withKey('watchlist', true);
      expect(q.watchlist, isTrue);
      expect([q.calls, q.dateNights, q.reunion, q.quietHours], [true, true, true, true]);
      expect(p.withKey('nonsense', true), same(p));
    });

    test('history carries the lock count', () {
      final h = PairHistory.fromJson({
        'patron': false,
        'locked_count': 45,
        'items': [
          {'title': 'Spirited Away', 'started_at': '2026-11-14T21:00:00Z', 'seconds': 7500},
        ],
      });
      expect(h.items.single.seconds, 7500);
      expect(h.lockedCount, 45);
    });
  });
  historyExportTests();
  sittingTitleTests();
}

void historyExportTests() {
  group('history export', () {
    final t = DateTime.utc(2026, 11, 14, 21);

    test('a header and one row per sitting, rounded to minutes', () {
      final csv = historyToCsv([
        PairSession(title: 'Spirited Away', startedAt: t, seconds: 7500),
        PairSession(title: null, startedAt: t, seconds: 90),
      ]);
      expect(
        csv,
        'title,started_at_utc,minutes\r\n'
        'Spirited Away,2026-11-14T21:00:00.000Z,125\r\n'
        ',2026-11-14T21:00:00.000Z,2\r\n',
      );
    });

    test('commas, quotes and breaks are quoted', () {
      final csv = historyToCsv([
        PairSession(title: 'Aftersun, "the one"\nagain', startedAt: t, seconds: 60),
      ]);
      expect(csv, contains('"Aftersun, ""the one""\nagain"'));
    });

    test('a title a spreadsheet would run as a formula is defused', () {
      for (final bad in ['=HYPERLINK("x")', '+1', '-2', '@SUM(A1)']) {
        final csv = historyToCsv([PairSession(title: bad, startedAt: t, seconds: 60)]);
        final cell = csv.split('\r\n')[1].split(',2026').first;
        expect(cell.replaceAll('"', ''), startsWith("'"), reason: bad);
      }
    });

    test('an empty history is just the header', () {
      expect(historyToCsv(const []), 'title,started_at_utc,minutes\r\n');
    });

    test('month headings', () {
      expect(monthHeading(DateTime(2026, 11, 14)), 'November 2026');
      expect(monthHeading(DateTime(2027, 1, 1)), 'January 2027');
    });
  });
}

void sittingTitleTests() {
  group('sitting titles', () {
    test('the extension and the separators go, the name stays', () {
      expect(sittingTitle('Spirited.Away.2001.mkv'), 'Spirited Away 2001');
      expect(sittingTitle('past_lives.mp4'), 'past lives');
      expect(sittingTitle('Aftersun.mov'), 'Aftersun');
    });

    test('a path is reduced to its basename', () {
      expect(sittingTitle('/Users/maya/Movies/Perfect Days.mkv'), 'Perfect Days');
      expect(sittingTitle(r'C:\Videos\Perfect Days.mkv'), 'Perfect Days');
    });

    test('a title that merely contains a dot is not mangled', () {
      expect(sittingTitle('Mr. Robot S01E01'), 'Mr Robot S01E01');
    });

    test('nothing worth keeping is null', () {
      expect(sittingTitle(null), isNull);
      expect(sittingTitle('   '), isNull);
    });
  });
}
