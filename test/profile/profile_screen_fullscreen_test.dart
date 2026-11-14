import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_app_window.dart';

import 'package:synctogether/profile/entitlement_service.dart';
import 'package:synctogether/profile/profile_models.dart';
import 'package:synctogether/profile/profile_screen.dart';
import 'package:synctogether/profile/profile_service.dart';
import 'package:synctogether/ui/cinema_marquee_bar.dart';
import 'package:synctogether/ui/responsive.dart';

void main() {
  group('ProfileScreen fullscreen behavior', () {
    tearDown(() {
      ProfileService.instance.setProfileForTesting(null);
      EntitlementService.instance.setLimitsForTesting(null);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('renders 78px traffic light inset in windowed mode on macOS', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      ProfileService.instance.setProfileForTesting(
        const Profile(id: 'user-1', displayName: 'Alex Smith', isGuest: false),
      );
      EntitlementService.instance.setLimitsForTesting(TierLimits.fallback);

      FakeAppWindow(fullScreen: false).install();

      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.reset());

      await tester.pumpWidget(
        MaterialApp(builder: buildResponsiveWrapper, home: const ProfileScreen()),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // In windowed mode, 78px inset is present
      final inset = find.byWidgetPredicate(
        (w) => w is SizedBox && w.width == CinemaMarqueeBar.macOsTrafficLightInset,
      );
      expect(inset, findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('collapses traffic light inset to 0px in fullscreen mode on macOS', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      ProfileService.instance.setProfileForTesting(
        const Profile(id: 'user-1', displayName: 'Alex Smith', isGuest: false),
      );
      EntitlementService.instance.setLimitsForTesting(TierLimits.fallback);

      FakeAppWindow(fullScreen: true).install();

      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.reset());

      await tester.pumpWidget(
        MaterialApp(builder: buildResponsiveWrapper, home: const ProfileScreen()),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // In fullscreen mode, the 78px inset should be omitted
      final inset = find.byWidgetPredicate(
        (w) => w is SizedBox && w.width == CinemaMarqueeBar.macOsTrafficLightInset,
      );
      expect(inset, findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
