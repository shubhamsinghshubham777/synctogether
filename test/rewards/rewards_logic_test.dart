import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/rewards/rewards_logic.dart';
import 'package:synctogether/rewards/rewards_models.dart';

MemberTally tally(
  String id, {
  String? name,
  int messages = 0,
  int reactions = 0,
  int transport = 0,
  int gateHolds = 0,
  bool camera = false,
  bool atStart = false,
  bool atEnd = false,
}) {
  final t = MemberTally(userId: id, displayName: name ?? id);
  t.messages = messages;
  t.reactions = reactions;
  t.transportActions = transport;
  t.gateHolds = gateHolds;
  t.cameraOn = camera;
  t.presentAtStart = atStart;
  t.presentAtEnd = atEnd;
  return t;
}

Achievement achievement(
  String id, {
  required String metric,
  required int threshold,
  bool unlocked = false,
  RewardGrade grade = RewardGrade.bronze,
}) => Achievement(
  id: id,
  title: id,
  description: id,
  icon: 'bolt',
  grade: grade,
  metric: metric,
  threshold: threshold,
  unlocked: unlocked,
);

void main() {
  group('streak multiplier', () {
    test('bands match the server, which is what the board publishes', () {
      expect(streakMultiplier(0), 1.00);
      expect(streakMultiplier(2), 1.00);
      expect(streakMultiplier(3), 1.10);
      expect(streakMultiplier(6), 1.10);
      expect(streakMultiplier(7), 1.25);
      expect(streakMultiplier(29), 1.25);
      expect(streakMultiplier(30), 1.50);
      expect(streakMultiplier(400), 1.50);
    });

    test('the next band is the nudge, and runs out at the top', () {
      expect(nextStreakBand(0), (days: 3, multiplier: 1.10));
      expect(nextStreakBand(5), (days: 2, multiplier: 1.25));
      expect(nextStreakBand(29), (days: 1, multiplier: 1.50));
      expect(nextStreakBand(30), isNull);
    });
  });

  group('the day in progress', () {
    test('fills toward the qualifying minutes and stops at full', () {
      expect(streakDayProgress(const StreakState(secondsToday: 0, minMinutes: 20)), 0);
      expect(streakDayProgress(const StreakState(secondsToday: 600, minMinutes: 20)), 0.5);
      expect(streakDayProgress(const StreakState(secondsToday: 9000, minMinutes: 20)), 1);
    });

    test('a zero requirement never divides by zero', () {
      expect(streakDayProgress(const StreakState(minMinutes: 0)), 1);
    });
  });

  group('streakAtRisk', () {
    final today = DateTime(2026, 5, 20);

    test('is false with no streak at all', () {
      expect(streakAtRisk(const StreakState(), today), isFalse);
      expect(streakAtRisk(StreakState(current: 0, lastDay: DateTime(2026, 5, 19)), today), isFalse);
    });

    test('is false once today already qualifies', () {
      expect(
        streakAtRisk(StreakState(current: 6, lastDay: today, qualifiedToday: true), today),
        isFalse,
      );
    });

    test('is true when the last qualifying day was yesterday and today is not done', () {
      expect(streakAtRisk(StreakState(current: 6, lastDay: DateTime(2026, 5, 19)), today), isTrue);
    });

    test('ignores the time of day on either side', () {
      expect(
        streakAtRisk(
          StreakState(current: 6, lastDay: DateTime(2026, 5, 19, 23, 58)),
          DateTime(2026, 5, 20, 0, 3),
        ),
        isTrue,
      );
    });
  });

  group('achievement progress', () {
    final metrics = {'total_sessions': 7, 'total_seconds': 100};

    test('is the fraction of the threshold, clamped', () {
      expect(
        achievementProgress(achievement('a', metric: 'total_sessions', threshold: 10), metrics),
        closeTo(0.7, 0.0001),
      );
      expect(
        achievementProgress(achievement('b', metric: 'total_sessions', threshold: 2), metrics),
        1,
      );
    });

    test('an unknown metric reads as zero rather than crashing an older client', () {
      expect(
        achievementProgress(achievement('c', metric: 'invented_later', threshold: 5), metrics),
        0,
      );
    });

    test('an unlocked badge is complete whatever the metric says', () {
      expect(
        achievementProgress(
          achievement('d', metric: 'nothing', threshold: 5, unlocked: true),
          metrics,
        ),
        1,
      );
    });
  });

  group('nextAchievement', () {
    final metrics = {'a': 9, 'b': 1, 'c': 50};

    test('picks the closest badge still in reach', () {
      final next = nextAchievement([
        achievement('far', metric: 'b', threshold: 100),
        achievement('near', metric: 'a', threshold: 10),
      ], metrics);
      expect(next?.id, 'near');
    });

    test('never reveals a secret - the absence is the point of one', () {
      final next = nextAchievement([
        achievement('hidden', metric: 'a', threshold: 10, grade: RewardGrade.secret),
        achievement('shown', metric: 'b', threshold: 100),
      ], metrics);
      expect(next?.id, 'shown');
    });

    test('skips what is already earned and what has not been started', () {
      final next = nextAchievement([
        achievement('done', metric: 'a', threshold: 10, unlocked: true),
        achievement('untouched', metric: 'missing', threshold: 10),
      ], metrics);
      expect(next, isNull);
    });
  });

  group('formatting', () {
    test('ordinals survive the teens', () {
      expect(rankOrdinal(1), '1st');
      expect(rankOrdinal(2), '2nd');
      expect(rankOrdinal(3), '3rd');
      expect(rankOrdinal(4), '4th');
      expect(rankOrdinal(11), '11th');
      expect(rankOrdinal(12), '12th');
      expect(rankOrdinal(13), '13th');
      expect(rankOrdinal(21), '21st');
      expect(rankOrdinal(112), '112th');
      expect(rankOrdinal(0), '-');
    });

    test('watch time never renders a zero, which reads as broken', () {
      expect(formatWatchTime(const Duration(seconds: 20)), 'under a minute');
      expect(formatWatchTime(const Duration(minutes: 38)), '38m');
      expect(formatWatchTime(const Duration(hours: 2)), '2h');
      expect(formatWatchTime(const Duration(hours: 4, minutes: 12)), '4h 12m');
    });

    test('hours stay in minutes below an hour', () {
      expect(formatWatchHours(const Duration(minutes: 18)), '18m');
      expect(formatWatchHours(const Duration(minutes: 90)), '1.5h');
      expect(formatWatchHours(const Duration(hours: 42)), '42h');
    });

    test('points shorten without pretending to precision', () {
      expect(formatPoints(940), '940');
      expect(formatPoints(1500), '1.5k');
      expect(formatPoints(42000), '42k');
      expect(formatPoints(2400000), '2.4M');
    });
  });

  group('superlatives', () {
    test('a session of one gets no awards - there is nobody to be best among', () {
      expect(
        superlativesFor(
          tallies: [tally('a', reactions: 50)],
          sessionLength: const Duration(hours: 1),
        ),
        isEmpty,
      );
    });

    test('an award needs a real number behind it', () {
      final out = superlativesFor(
        tallies: [tally('a', reactions: 1), tally('b', messages: 2)],
        sessionLength: const Duration(minutes: 10),
      );
      expect(out.map((s) => s.key), isNot(contains(SuperlativeKey.reactions)));
      expect(out.map((s) => s.key), isNot(contains(SuperlativeKey.chat)));
    });

    test('one award per person, highest priority first', () {
      final out = superlativesFor(
        tallies: [tally('a', reactions: 40, messages: 40, transport: 40), tally('b', reactions: 1)],
        sessionLength: const Duration(minutes: 10),
      );
      expect(out.where((s) => s.userId == 'a').length, 1);
      expect(out.single.key, SuperlativeKey.reactions);
    });

    test('distributes across people rather than piling onto one', () {
      final out = superlativesFor(
        tallies: [tally('a', reactions: 40), tally('b', messages: 30), tally('c', transport: 12)],
        sessionLength: const Duration(minutes: 10),
      );
      expect(out.map((s) => s.userId), ['a', 'b', 'c']);
      expect(out.map((s) => s.key), [
        SuperlativeKey.reactions,
        SuperlativeKey.chat,
        SuperlativeKey.pauser,
      ]);
    });

    test('never returns more than asked for', () {
      final out = superlativesFor(
        tallies: [
          tally('a', reactions: 40),
          tally('b', messages: 30),
          tally('c', transport: 12),
          tally('d', camera: true),
        ],
        sessionLength: const Duration(minutes: 10),
        max: 2,
      );
      expect(out, hasLength(2));
    });

    test('Ride or Die needs a session long enough to have ridden through', () {
      final people = [
        tally('a', atStart: true, atEnd: true),
        tally('b', atStart: true, atEnd: true),
      ];
      expect(
        superlativesFor(
          tallies: people,
          sessionLength: const Duration(minutes: 5),
        ).map((s) => s.key),
        isNot(contains(SuperlativeKey.rideOrDie)),
      );
      expect(
        superlativesFor(tallies: people, sessionLength: kRideOrDieMinimum).map((s) => s.key),
        contains(SuperlativeKey.rideOrDie),
      );
    });

    test('Rock Solid goes to somebody who never held the gate shut', () {
      final out = superlativesFor(
        tallies: [
          tally('blocker', gateHolds: 1, atStart: true, atEnd: true),
          tally('clean', gateHolds: 0, atStart: true, atEnd: true),
        ],
        sessionLength: const Duration(minutes: 10),
      );
      final steady = out.where((s) => s.key == SuperlativeKey.steady).firstOrNull;
      expect(steady?.userId, 'clean');
    });

    test('Night Owl only exists when the session crossed 2am', () {
      final people = [tally('a', reactions: 9), tally('b', messages: 9)];
      expect(
        superlativesFor(
          tallies: people,
          sessionLength: const Duration(minutes: 10),
        ).map((s) => s.key),
        isNot(contains(SuperlativeKey.nightOwl)),
      );
    });

    test('is deterministic, so two clients render the same card', () {
      final forward = superlativesFor(
        tallies: [tally('b', reactions: 10), tally('a', reactions: 10)],
        sessionLength: const Duration(minutes: 10),
      );
      final backward = superlativesFor(
        tallies: [tally('a', reactions: 10), tally('b', reactions: 10)],
        sessionLength: const Duration(minutes: 10),
      );
      expect(forward.map((s) => (s.key, s.userId)), backward.map((s) => (s.key, s.userId)));
    });

    test('the wire form is the allow-list the server checks against', () {
      expect(SuperlativeKey.rideOrDie.wire, 'ride_or_die');
      expect(SuperlativeKey.nightOwl.wire, 'night_owl');
      expect(SuperlativeKey.firstIn.wire, 'first_in');
      expect(Superlative(key: .chat, userId: 'u1', displayName: 'Sam').toWire(), {
        'key': 'chat',
        'user_id': 'u1',
      });
    });
  });

  group('sessionWorthRecapping', () {
    test('a guest is never offered one - they have no durable identity to share', () {
      expect(
        sessionWorthRecapping(length: const Duration(hours: 2), peakMembers: 4, isGuest: true),
        isFalse,
      );
    });

    test('watching alone is not a watch party', () {
      expect(
        sessionWorthRecapping(length: const Duration(hours: 2), peakMembers: 1, isGuest: false),
        isFalse,
      );
    });

    test('four minutes is not a story worth telling', () {
      expect(
        sessionWorthRecapping(length: const Duration(minutes: 4), peakMembers: 3, isGuest: false),
        isFalse,
      );
    });

    test('but a real session is', () {
      expect(
        sessionWorthRecapping(length: kRecapMinimumLength, peakMembers: 2, isGuest: false),
        isTrue,
      );
    });
  });
}
