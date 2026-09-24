import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/profile/entitlement_service.dart';
import 'package:synctogether/profile/profile_models.dart';
import 'package:synctogether/profile/profile_screen.dart';
import 'package:synctogether/profile/profile_service.dart';
import 'package:synctogether/rewards/rewards_service.dart';

import '../support/screen_matrix.dart';
import 'layout_support.dart';

const _guestLimits = TierLimits(
  tier: kGuestTier,
  maxLiveRooms: 1,
  maxMembers: 4,
  maxSessionMinutes: 60,
  maxTotalSessionMinutes: 60,
  avLevel: .none,
  persistentRoomCap: 0,
  dormantHours: 0,
  freeExtensionMinutes: 0,
  mediaSharing: 'none',
  mediaSharingWeeklyBytes: 0,
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RewardsService.instance = FakeRewardsService();
  });
  tearDown(() {
    ProfileService.instance.setProfileForTesting(null);
    EntitlementService.instance.setLimitsForTesting(null);
  });

  screenMatrix('profile/signed-in', (tester, c, s) async {
    ProfileService.instance.setProfileForTesting(
      const Profile(
        id: 'user-1',
        displayName: 'Alexandria Montgomery-Smythe',
        isGuest: false,
        email: 'alexandria.montgomery-smythe@example.com',
      ),
    );
    EntitlementService.instance.setLimitsForTesting(TierLimits.fallback);
    await pumpAtSize(tester, const ProfileScreen(), c, textScale: s);
    await finishCase(tester);
  });

  screenMatrix('profile/guest', (tester, c, s) async {
    ProfileService.instance.setProfileForTesting(
      const Profile(id: 'guest-1', displayName: 'Guest-1234', isGuest: true),
    );
    EntitlementService.instance.setLimitsForTesting(_guestLimits);
    await pumpAtSize(tester, const ProfileScreen(), c, textScale: s);
    await finishCase(tester);
  });
}
