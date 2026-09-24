import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/profile/entitlement_service.dart';
import 'package:synctogether/profile/profile_models.dart';
import 'package:synctogether/profile/profile_service.dart';
import 'package:synctogether/profile/subscription_screen.dart';

import '../support/screen_matrix.dart';
import 'layout_support.dart';

void main() {
  setUp(() {
    ProfileService.instance.setProfileForTesting(
      const Profile(id: 'user-1', displayName: 'Alex Smith', isGuest: false, email: 'a@b.co'),
    );
    EntitlementService.instance.setLimitsForTesting(TierLimits.fallback);
  });
  tearDown(() {
    ProfileService.instance.setProfileForTesting(null);
    EntitlementService.instance.setLimitsForTesting(null);
  });

  // Desktop vs mobile shape follows the case's platform; only the build
  // flavour is forced.
  screenMatrix('subscription/web', (tester, c, s) async {
    await pumpAtSize(tester, const SubscriptionScreen(storeBuildOverride: false), c, textScale: s);
    await finishCase(tester);
  });

  screenMatrix('subscription/store', (tester, c, s) async {
    await pumpAtSize(
      tester,
      const SubscriptionScreen(storeBuildOverride: true, appleStoreBuildOverride: false),
      c,
      textScale: s,
    );
    await finishCase(tester);
  });

  screenMatrix('subscription/apple-store', (tester, c, s) async {
    await pumpAtSize(
      tester,
      const SubscriptionScreen(storeBuildOverride: true, appleStoreBuildOverride: true),
      c,
      textScale: s,
    );
    await finishCase(tester);
  });
}
