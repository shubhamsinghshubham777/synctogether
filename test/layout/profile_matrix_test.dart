import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/ui/booth_icons.g.dart';
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

/// The sections arrive on a one-shot stagger (delay timers, then a tween), so
/// let it land before the overflow/inset checks and the screenshot - otherwise
/// they only ever see the first frame of an empty page.
Future<void> _settleStagger(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 600));
}

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
    await _settleStagger(tester);
    // Whatever the width, the seat name never wraps by character.
    // (Only the phone layout has the membership card.)
    if (find.text('Free seat').evaluate().isNotEmpty) expectShownWhole(tester, 'Free seat');
    // On a phone the header sits at the left edge (not centred) and the scroll area starts
    // clear of it, so scrolled content never meets the back button.
    final back = find.byIcon(BoothIcons.arrowBack);
    if (c.size.width < 700 && back.evaluate().isNotEmpty) {
      expect(tester.getTopLeft(back.first).dx, lessThan(80), reason: 'header must be left-aligned');
      final scroll = find.byType(SingleChildScrollView);
      if (scroll.evaluate().isNotEmpty && c.size.height > c.size.width) {
        expect(
          tester.getTopLeft(scroll.first).dy - tester.getBottomLeft(back.first).dy,
          greaterThanOrEqualTo(8),
          reason: 'scroll area must clear the header',
        );
      }
    }
    await finishCase(tester);
  });

  screenMatrix('profile/guest', (tester, c, s) async {
    ProfileService.instance.setProfileForTesting(
      const Profile(id: 'guest-1', displayName: 'Guest-1234', isGuest: true),
    );
    EntitlementService.instance.setLimitsForTesting(_guestLimits);
    await pumpAtSize(tester, const ProfileScreen(), c, textScale: s);
    await _settleStagger(tester);
    await finishCase(tester);
  });
}
