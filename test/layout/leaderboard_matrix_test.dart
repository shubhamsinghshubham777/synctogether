import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/profile/entitlement_service.dart';
import 'package:synctogether/profile/profile_models.dart';
import 'package:synctogether/profile/profile_service.dart';
import 'package:synctogether/rewards/leaderboard_screen.dart';
import 'package:synctogether/rewards/rewards_models.dart';
import 'package:synctogether/rewards/rewards_service.dart';

import '../support/screen_matrix.dart';
import 'layout_support.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ProfileService.instance.setProfileForTesting(
      const Profile(id: 'user-alex', displayName: 'Alex Rivers', isGuest: false),
    );
    EntitlementService.instance.setLimitsForTesting(TierLimits.fallback);
  });
  tearDown(() {
    ProfileService.instance.setProfileForTesting(null);
    EntitlementService.instance.setLimitsForTesting(null);
  });

  screenMatrix('leaderboard/circle', (tester, c, s) async {
    RewardsService.instance = FakeRewardsService();
    await pumpAtSize(tester, const LeaderboardScreen(), c, textScale: s);
    await finishCase(tester);
  });

  screenMatrix('leaderboard/guest', (tester, c, s) async {
    RewardsService.instance = FakeRewardsService(
      fakeState: const RewardState(tier: 'guest'),
      rows: const [],
    );
    await pumpAtSize(tester, const LeaderboardScreen(), c, textScale: s);
    await finishCase(tester);
  });
}
