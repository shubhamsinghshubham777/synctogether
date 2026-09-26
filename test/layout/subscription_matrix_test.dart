import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/profile/entitlement_service.dart';
import 'package:synctogether/profile/profile_models.dart';
import 'package:synctogether/profile/profile_service.dart';
import 'package:synctogether/profile/subscription_screen.dart';

import '../support/screen_matrix.dart';
import 'layout_support.dart';

/// Lets the one-shot perk stagger land before the screenshot, so the capture
/// shows the page rather than a frame of its entrance.
Future<void> _settle(WidgetTester tester) => tester.pump(const Duration(seconds: 1));

void main() {
  // StoreKit has no host under flutter_test: answer "payments unavailable"
  // so the Apple rail settles on its "couldn't reach the App Store" state
  // instead of reporting a channel error mid-case.
  const storeKit = 'dev.flutter.pigeon.in_app_purchase_storekit.InAppPurchase2API.canMakePayments';
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
      storeKit,
      (_) async => const StandardMessageCodec().encodeMessage(<Object?>[false]),
    );
  });
  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
      storeKit,
      null,
    );
  });
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
  // flavour is forced (the web case also pins off the Apple rail, which iOS
  // cases would otherwise take - and hit an unmocked StoreKit channel).
  screenMatrix('subscription/web', (tester, c, s) async {
    await pumpAtSize(
      tester,
      const SubscriptionScreen(storeBuildOverride: false, appleStoreBuildOverride: false),
      c,
      textScale: s,
    );
    await _settle(tester);
    await finishCase(tester);
  });

  screenMatrix('subscription/store', (tester, c, s) async {
    await pumpAtSize(
      tester,
      const SubscriptionScreen(storeBuildOverride: true, appleStoreBuildOverride: false),
      c,
      textScale: s,
    );
    await _settle(tester);
    await finishCase(tester);
  });

  screenMatrix('subscription/apple-store', (tester, c, s) async {
    await pumpAtSize(
      tester,
      const SubscriptionScreen(storeBuildOverride: true, appleStoreBuildOverride: true),
      c,
      textScale: s,
    );
    await _settle(tester);
    await finishCase(tester);
  });
}
