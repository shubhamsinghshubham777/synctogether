import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/profile/entitlement_service.dart';
import 'package:synctogether/profile/profile_models.dart';
import 'package:synctogether/profile/profile_service.dart';
import 'package:synctogether/profile/subscription_screen.dart';

import '../support/screen_matrix.dart';
import 'layout_support.dart';

/// A benefit title may wrap between words, never inside one: its box has to be at
/// least as wide as its longest word. A squeezed table column used to leave a
/// title a sliver wide ("Video faceca / ms") with no overflow to flag it.
void _expectTitlesNeverBreakMidWord(WidgetTester tester, ScreenCase c, double s) {
  for (final title in [
    '16-seat rooms',
    'Video facecams',
    '24-hour rooms',
    'Rooms that stay saved',
    'Every reaction',
    '10 GB shared uploads',
  ]) {
    final f = find.text(title);
    if (f.evaluate().isEmpty) continue;
    final p = tester.renderObject<RenderParagraph>(f.first);
    final longest = title
        .split(RegExp(r'[ -]'))
        .map(
          (w) => (TextPainter(
            text: TextSpan(text: w, style: p.text.style),
            textDirection: TextDirection.ltr,
            textScaler: p.textScaler,
          )..layout()).width,
        )
        .reduce(math.max);
    expect(
      p.size.width + 0.5,
      greaterThanOrEqualTo(longest),
      reason: '${c.name} x$s: "$title" breaks inside a word (box ${p.size.width}, word $longest)',
    );
  }
}

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
      const SubscriptionScreen(appleStoreBuildOverride: false),
      c,
      textScale: s,
      singlePane: true,
    );
    await _settle(tester);
    _expectTitlesNeverBreakMidWord(tester, c, s);
    await finishCase(tester);
  });

  screenMatrix('subscription/apple-store', (tester, c, s) async {
    await pumpAtSize(
      tester,
      const SubscriptionScreen(appleStoreBuildOverride: true),
      c,
      textScale: s,
      singlePane: true,
    );
    await _settle(tester);
    _expectTitlesNeverBreakMidWord(tester, c, s);
    await finishCase(tester);
  });
}
