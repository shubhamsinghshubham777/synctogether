import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/analytics_catalog.dart';

/// Reads the `Analytics.track('...')` literals straight out of `lib/`.
///
/// The catalogue is shown to users as an exhaustive list of what we collect, so
/// a drift between it and the code is not a tidiness problem - it is the app
/// telling somebody an untruth about their own data. This is the guard.
Set<String> _trackedEventsInSource() {
  final pattern = RegExp(r"""track\(\s*'([A-Za-z0-9_]+)'""");
  final found = <String>{};
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    // The catalogue itself names every event in prose; it is documentation,
    // not a call site.
    if (entity.path.endsWith('analytics_catalog.dart')) continue;
    for (final match in pattern.allMatches(entity.readAsStringSync())) {
      found.add(match.group(1)!);
    }
  }
  return found;
}

void main() {
  group('the analytics catalogue is exhaustive', () {
    final tracked = _trackedEventsInSource();
    final documented = {for (final doc in kAnalyticsEvents) doc.event};

    test('the source actually contains track() calls, so the scan is meaningful', () {
      expect(
        tracked,
        isNotEmpty,
        reason: 'found no track() calls at all - the pattern has probably drifted',
      );
    });

    test('every event the app can send is listed for the user', () {
      expect(
        tracked.difference(documented),
        isEmpty,
        reason:
            'These events are sent but not documented, so the "what we collect" '
            'dialog understates what leaves the device. Add them to '
            'lib/analytics_catalog.dart.',
      );
    });

    test('nothing is listed that the app no longer sends', () {
      expect(
        documented.difference(tracked),
        isEmpty,
        reason:
            'These are documented but never sent. A list that overstates is as '
            'untrustworthy as one that understates - remove them.',
      );
    });
  });

  group('every entry is usable copy', () {
    test('nothing is blank', () {
      for (final doc in kAnalyticsEvents) {
        expect(doc.event.trim(), isNotEmpty);
        expect(doc.what.trim(), isNotEmpty, reason: doc.event);
        expect(doc.why.trim(), isNotEmpty, reason: doc.event);
      }
    });

    test('the reason is a sentence, not a shrug', () {
      for (final doc in kAnalyticsEvents) {
        expect(doc.why.length, greaterThan(20), reason: doc.event);
      }
    });

    test('no event is listed twice', () {
      final seen = <String>{};
      for (final doc in kAnalyticsEvents) {
        expect(seen.add(doc.event), isTrue, reason: 'duplicate: ${doc.event}');
      }
    });

    test('grouping loses nothing', () {
      final grouped = analyticsEventsByGroup();
      expect(grouped.values.expand((docs) => docs).length, kAnalyticsEvents.length);
    });

    test('the never-collected list is stated positively and is not empty', () {
      expect(kAnalyticsNeverCollected, isNotEmpty);
      for (final line in kAnalyticsNeverCollected) {
        expect(line.trim(), isNotEmpty);
      }
    });
  });
}
