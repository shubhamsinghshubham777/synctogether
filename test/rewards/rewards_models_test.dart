import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/rewards/rewards_models.dart';

void main() {
  _seasonTests();
  group('RewardState parsing', () {
    test('reads the whole my_rewards payload in one go', () {
      final state = RewardState.fromJson({
        'enabled': true,
        'tier': 'premium',
        'public_profile': true,
        'handle': 'reel_fan',
        'equipped_frame': 'aurora',
        'streak': {
          'current': 9,
          'longest': 14,
          'freezes': 2,
          'seconds_today': 600,
          'min_minutes': 20,
          'qualified_today': false,
        },
        'totals': {'seconds': 7200, 'sessions': 12, 'co_watchers': 4},
        'points': {'today': 40, 'week': 310, 'month': 900, 'all': 4200},
        'rank': {'week': 12, 'circle': 2},
        'global_board': {'open': false, 'participants': 31, 'min_required': 200},
        'metrics': {'total_sessions': 12, 'total_seconds': 7200},
        'frames': ['aurora', 'ember'],
        'achievements': [
          {
            'id': 'first_sync',
            'title': 'First Sync',
            'description': 'x',
            'icon': 'handshake',
            'grade': 'bronze',
            'metric': 'total_sessions',
            'threshold': 1,
            'reward': {'frame': 'ember'},
            'unlocked': true,
            'seen': false,
            'unlocked_at': '2026-05-01T10:00:00Z',
          },
          {
            'id': 'century',
            'title': 'Century',
            'description': 'y',
            'icon': 'military_tech',
            'grade': 'gold',
            'metric': 'total_seconds',
            'threshold': 360000,
            'reward': {},
            'unlocked': false,
          },
        ],
      });

      expect(state.isPremium, isTrue);
      expect(state.publicProfile, isTrue);
      expect(state.handle, 'reel_fan');
      expect(state.equippedFrame, AvatarFrame.aurora);
      expect(state.streak.current, 9);
      expect(state.streak.today, const Duration(minutes: 10));
      expect(state.totals.watched, const Duration(hours: 2));
      expect(state.points.week, 310);
      expect(state.circleRank, 2);
      expect(state.globalBoard.open, isFalse);
      expect(state.globalBoard.participants, 31);
      expect(state.unlocked.map((a) => a.id), ['first_sync']);
      expect(state.locked.map((a) => a.id), ['century']);
      expect(state.unlocked.single.frame, AvatarFrame.ember);
      expect(state.metrics['total_sessions'], 12);
    });

    test('an empty payload lands on the understated fallback, never a crash', () {
      final state = RewardState.fromJson(const {});
      expect(state.tier, 'free');
      expect(state.streak.current, 0);
      expect(state.achievements, isEmpty);
      expect(state.publicProfile, isFalse);
    });

    test('premium wears its frame by right, on top of whatever it earned', () {
      const earned = RewardState(tier: 'premium', frames: {AvatarFrame.ember});
      expect(earned.availableFrames, {AvatarFrame.ember, AvatarFrame.aurum});

      const free = RewardState(tier: 'free', frames: {AvatarFrame.ember});
      expect(free.availableFrames, {AvatarFrame.ember});
    });

    test('a frame the client has never heard of is simply not worn', () {
      expect(AvatarFrame.fromWire('invented_next_year'), isNull);
      expect(AvatarFrame.fromWire(null), isNull);
      expect(AvatarFrame.fromWire('aurum'), AvatarFrame.aurum);
      expect(AvatarFrame.aurum.isPremiumOnly, isTrue);
      expect(AvatarFrame.ember.isPremiumOnly, isFalse);
    });

    test('an unknown grade reads as bronze rather than throwing', () {
      expect(RewardGrade.fromWire('platinum'), RewardGrade.bronze);
      expect(RewardGrade.fromWire('secret'), RewardGrade.secret);
    });
  });

  group('HeartbeatResult', () {
    test('a credited beat carries the new streak and the badges it crossed', () {
      final result = HeartbeatResult.fromJson({
        'enabled': true,
        'credited': true,
        'granted_seconds': 60,
        'seconds_today': 1260,
        'points_today': 36,
        'streak': 4,
        'longest_streak': 9,
        'freezes': 1,
        'streak_frozen': false,
        'day_qualified': true,
        'unlocked': [
          {
            'id': 'week_one',
            'title': 'Regular',
            'description': 'x',
            'icon': 'bolt',
            'grade': 'bronze',
            'reward': {'frame': 'ember'},
          },
        ],
      });
      expect(result.credited, isTrue);
      expect(result.outcome, HeartbeatOutcome.credited);
      expect(result.grantedSeconds, 60);
      expect(result.dayQualified, isTrue);
      expect(result.unlocked.single.id, 'week_one');
      expect(result.unlocked.single.unlocked, isTrue);
      expect(result.unlocked.single.frame, AvatarFrame.ember);
    });

    test('every refusal is a normal answer with a name', () {
      for (final (wire, outcome) in const [
        ('guest', HeartbeatOutcome.guest),
        ('solo', HeartbeatOutcome.solo),
        ('idle', HeartbeatOutcome.idle),
        ('no_media', HeartbeatOutcome.noMedia),
        ('daily_cap', HeartbeatOutcome.dailyCap),
        ('anchored', HeartbeatOutcome.anchored),
        ('no_elapsed', HeartbeatOutcome.noElapsed),
        ('room_ended', HeartbeatOutcome.roomEnded),
        ('not_a_member', HeartbeatOutcome.notAMember),
        ('disabled', HeartbeatOutcome.disabled),
      ]) {
        final result = HeartbeatResult.fromJson({'credited': false, 'reason': wire});
        expect(result.outcome, outcome, reason: wire);
        expect(result.credited, isFalse);
      }
    });

    test('a reason this client has never seen is the only one worth reporting', () {
      final result = HeartbeatResult.fromJson({'credited': false, 'reason': 'added_in_v2'});
      expect(result.outcome, HeartbeatOutcome.unknown);
    });

    test('the guest refusal carries the sign-in offer', () {
      final result = HeartbeatResult.fromJson({
        'credited': false,
        'reason': 'guest',
        'upgrade': true,
      });
      expect(result.outcome, HeartbeatOutcome.guest);
      expect(result.needsUpgrade, isTrue);
    });
  });

  group('LeaderboardRow', () {
    test('carries the cosmetics the row renders', () {
      final row = LeaderboardRow.fromJson({
        'rank': 3,
        'user_id': 'u1',
        'display_name': 'Ana',
        'avatar_url': null,
        'handle': 'ana',
        'frame': 'laurel',
        'is_premium': true,
        'points': 812,
        'streak': 21,
        'seconds': 36000,
        'is_me': false,
      });
      expect(row.rank, 3);
      expect(row.frame, AvatarFrame.laurel);
      expect(row.isPremium, isTrue);
      expect(row.watched, const Duration(hours: 10));
      expect(row.isMe, isFalse);
    });

    test('a sparse row still renders something sensible', () {
      final row = LeaderboardRow.fromJson(const {'user_id': 'u2'});
      expect(row.displayName, 'Watcher');
      expect(row.points, 0);
      expect(row.frame, isNull);
    });
  });

  group('scopes and periods', () {
    test('wire values match the RPC parameters', () {
      expect(LeaderboardScope.circle.wire, 'circle');
      expect(LeaderboardScope.global.wire, 'global');
      expect(LeaderboardPeriod.week.wire, 'week');
      expect(LeaderboardPeriod.month.wire, 'month');
      expect(LeaderboardPeriod.all.wire, 'all');
    });
  });
}

void _seasonTests() {
  group('SeasonAward', () {
    test('renders a month from the wire id', () {
      expect(const SeasonAward(season: '2026-05', rank: 1).monthLabel, 'May 2026');
      expect(const SeasonAward(season: '2026-12', rank: 2).monthLabel, 'December 2026');
    });

    test('a shape this client has not seen falls back rather than throwing', () {
      expect(const SeasonAward(season: '2026-13', rank: 1).monthLabel, '2026-13');
      expect(const SeasonAward(season: 'nonsense', rank: 1).monthLabel, 'nonsense');
      expect(const SeasonAward(season: '', rank: 1).monthLabel, '');
    });

    test('names the placing rather than the number', () {
      expect(const SeasonAward(season: '2026-05', rank: 1).label, 'Season winner');
      expect(const SeasonAward(season: '2026-05', rank: 2).label, 'Season runner-up');
      expect(const SeasonAward(season: '2026-05', rank: 3).label, 'Season third');
    });

    test('parses out of the my_rewards payload', () {
      final state = RewardState.fromJson({
        'seasons': [
          {'season': '2026-05', 'rank': 1, 'points': 8400},
          {'season': '2026-04', 'rank': 3, 'points': 5100},
        ],
      });
      expect(state.seasons.map((s) => s.season), ['2026-05', '2026-04']);
      expect(state.seasons.first.rank, 1);
      expect(state.seasons.first.points, 8400);
    });

    test('a payload with no seasons is an empty list, never null', () {
      expect(RewardState.fromJson(const {}).seasons, isEmpty);
    });
  });
}
