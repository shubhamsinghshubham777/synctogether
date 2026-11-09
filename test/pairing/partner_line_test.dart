import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/pairing/date_night_plan.dart';

import '../support/fake_pair_service.dart';

void main() {
  final moment = DateTime(2026, 12, 10, 21, 0);
  // A zone that is certainly not this machine's, whatever machine runs the test.
  final localOffset = moment.timeZoneOffset;
  final other = localOffset == const Duration(hours: 9) ? 'America/New_York' : 'Asia/Tokyo';

  test('says what time it is for them, by first name', () {
    final line = partnerLineFor(samePairInfo(partnerZone: other), is24Hour: false)(moment);
    expect(line, matches(RegExp(r"^That's \d{1,2}:\d{2} (AM|PM)( on [A-Z][a-z]+day)? for Sam\.$")));
  });

  test('a 24-hour clock shows 24-hour time', () {
    final line = partnerLineFor(samePairInfo(partnerZone: other), is24Hour: true)(moment);
    expect(line, matches(RegExp(r"^That's \d{2}:\d{2}( on [A-Z][a-z]+day)? for Sam\.$")));
  });

  test('names the day when it is a different day for them', () {
    // Tokyo or New York is at least 9 hours from some zone; pick the moment that
    // forces a date change in one of them by testing both ends of the day.
    final late = DateTime(2026, 12, 10, 23, 30);
    final early = DateTime(2026, 12, 10, 0, 30);
    final lines = [
      late,
      early,
    ].map((m) => partnerLineFor(samePairInfo(partnerZone: other), is24Hour: false)(m));
    expect(lines.any((l) => l!.contains(' on ')), isTrue);
  });

  test('says nothing when their zone is unknown', () {
    expect(partnerLineFor(samePairInfo(partnerZone: null), is24Hour: false)(moment), isNull);
  });
}
