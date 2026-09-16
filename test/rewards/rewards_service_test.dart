import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/analytics_consent.dart';
import 'package:synctogether/rewards/rewards_models.dart';
import 'package:synctogether/rewards/rewards_service.dart';

void main() {
  group('without a backend', () {
    // Every read path degrades silently rather than reporting. An uninitialized
    // Supabase is a widget test or an unconfigured build, not a bug, and
    // reporting it would fail every test that happens to mount a screen.
    late RewardsService service;

    setUp(() => service = RewardsService());

    test('loading returns null instead of throwing', () async {
      expect(await service.load(), isNull);
      expect(service.loaded, isFalse);
      expect(service.state, RewardState.empty);
    });

    test('the leaderboard is empty rather than an error', () async {
      expect(await service.leaderboard(), isEmpty);
    });

    test('a heartbeat is a no-op', () async {
      final result = await service.recordProgress('room-1');
      expect(result.outcome, HeartbeatOutcome.unknown);
      expect(result.grantedSeconds, 0);
    });

    test('the referral count stays where it was', () async {
      expect(await service.loadReferrals(), 0);
    });
  });

  group('the usage-data switch stops everything', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() => AnalyticsConsent.instance.setOptedOut(false));

    test('opting out refuses the heartbeat before it touches the network', () async {
      await AnalyticsConsent.instance.setOptedOut(true);
      final result = await RewardsService().recordProgress('room-1');
      // The distinction matters: `optedOut` is the user's decision, not a
      // failure, and the UI says so rather than showing a frozen streak.
      expect(result.outcome, HeartbeatOutcome.optedOut);
      expect(result.grantedSeconds, 0);
    });

    test('opting back in resumes rather than replaying', () async {
      await AnalyticsConsent.instance.setOptedOut(true);
      await AnalyticsConsent.instance.setOptedOut(false);
      final result = await RewardsService().recordProgress('room-1');
      expect(result.outcome, isNot(HeartbeatOutcome.optedOut));
    });
  });

  group('state handling', () {
    test('clear resets to the understated fallback', () {
      final service = RewardsService()
        ..setStateForTesting(const RewardState(tier: 'premium', publicProfile: true));
      expect(service.loaded, isTrue);
      service.clear();
      expect(service.state, RewardState.empty);
      expect(service.loaded, isFalse);
    });

    test('clearing an already-empty service does not notify', () {
      final service = RewardsService();
      var notifications = 0;
      service.addListener(() => notifications++);
      service.clear();
      expect(notifications, 0);
    });
  });

  group('share URLs', () {
    test('every public artefact is an https link, never the app scheme', () {
      expect(recapUrl('abc123'), startsWith('http'));
      expect(recapUrl('abc123'), endsWith('/r/abc123'));
      expect(profileUrl('reel_fan'), endsWith('/u/reel_fan'));
      expect(rewardsSiteBase, isNot(contains('synctogether://')));
    });
  });

  group('failure codes', () {
    test('each one maps to advice that fits it', () {
      expect(RewardErrorCode.fromError(Exception('handle_taken')), RewardErrorCode.handleTaken);
      expect(
        RewardErrorCode.fromError(Exception('handle_reserved')),
        RewardErrorCode.handleReserved,
      );
      expect(RewardErrorCode.fromError(Exception('invalid_handle')), RewardErrorCode.invalidHandle);
      expect(RewardErrorCode.fromError(Exception('frame_locked')), RewardErrorCode.frameLocked);
      expect(
        RewardErrorCode.fromError(Exception('guest_not_eligible')),
        RewardErrorCode.guestNotEligible,
      );
      expect(
        RewardErrorCode.fromError(Exception('premium_required')),
        RewardErrorCode.premiumRequired,
      );
    });

    test('an unrecognised failure falls back rather than showing a raw code', () {
      final code = RewardErrorCode.fromError(Exception('some_new_server_error'));
      expect(code, RewardErrorCode.unknown);
      expect(code.message, isNot(contains('some_new_server_error')));
    });

    test('the message is friendly copy, never the wire code', () {
      for (final code in RewardErrorCode.values) {
        expect(code.message, isNot(contains('_')), reason: code.name);
        expect(code.message.trim(), isNotEmpty);
      }
    });
  });
}
