import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:synctogether/profile/entitlement_service.dart';
import 'package:synctogether/profile/profile_models.dart';
import 'package:synctogether/profile/profile_screen.dart';
import 'package:synctogether/profile/profile_service.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/responsive.dart';

void main() {
  group('ProfileScreen', () {
    tearDown(() {
      ProfileService.instance.setProfileForTesting(null);
      EntitlementService.instance.setLimitsForTesting(null);
    });

    testWidgets('renders profile screen for signed-in user on desktop', (tester) async {
      ProfileService.instance.setProfileForTesting(
        const Profile(
          id: 'user-1',
          displayName: 'Alex Smith',
          isGuest: false,
          email: 'alex@example.com',
        ),
      );
      EntitlementService.instance.setLimitsForTesting(TierLimits.fallback);

      await tester.pumpWidget(
        MaterialApp(builder: buildResponsiveWrapper, home: const ProfileScreen()),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Alex Smith'), findsWidgets);
      expect(find.text('alex@example.com'), findsOneWidget);
      expect(find.text('Privacy policy'), findsOneWidget);
      expect(find.text('Terms of service'), findsOneWidget);
    });

    testWidgets('renders profile screen for guest user', (tester) async {
      ProfileService.instance.setProfileForTesting(
        const Profile(id: 'guest-1', displayName: 'Guest-1234', isGuest: true),
      );
      EntitlementService.instance.setLimitsForTesting(
        const TierLimits(
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
        ),
      );

      await tester.pumpWidget(
        MaterialApp(builder: buildResponsiveWrapper, home: const ProfileScreen()),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Guest-1234'), findsWidgets);
      expect(find.text('Keep your identity'), findsOneWidget);
      expect(find.text('End guest session'), findsOneWidget);
      expect(find.text('Privacy policy'), findsOneWidget);
      expect(find.text('Terms of service'), findsOneWidget);
    });

    testWidgets('navigating to profile screen with mouse hover and click does not throw', (
      tester,
    ) async {
      ProfileService.instance.setProfileForTesting(
        const Profile(
          id: 'user-1',
          displayName: 'Alex Smith',
          isGuest: false,
          email: 'alex@example.com',
        ),
      );
      EntitlementService.instance.setLimitsForTesting(TierLimits.fallback);

      final router = GoRouter(
        initialLocation: '/lobby',
        routes: [
          GoRoute(
            path: '/lobby',
            builder: (context, state) => Scaffold(
              body: Center(
                child: GlassPill(
                  onTap: () => context.go('/lobby/profile'),
                  child: const Text('View Profile'),
                ),
              ),
            ),
            routes: [GoRoute(path: 'profile', builder: (context, state) => const ProfileScreen())],
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp.router(builder: buildResponsiveWrapper, routerConfig: router),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Simulate mouse hover over the profile button
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await tester.pump();

      await mouse.moveTo(tester.getCenter(find.text('View Profile')));
      await tester.pump(const Duration(milliseconds: 50));

      // Click to navigate to profile
      await mouse.down(tester.getCenter(find.text('View Profile')));
      await tester.pump(const Duration(milliseconds: 50));
      await mouse.up();
      await tester.pump(const Duration(milliseconds: 200));

      // Move mouse across the newly mounted profile screen
      await mouse.moveTo(const Offset(300, 300));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Privacy policy'), findsOneWidget);
      expect(find.text('Terms of service'), findsOneWidget);
    });

    testWidgets('renders profile screen for signed-in user on mobile portrait', (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      ProfileService.instance.setProfileForTesting(
        const Profile(
          id: 'user-1',
          displayName: 'Alex Smith',
          isGuest: false,
          email: 'alex@example.com',
        ),
      );
      EntitlementService.instance.setLimitsForTesting(TierLimits.fallback);

      await tester.pumpWidget(
        MaterialApp(builder: buildResponsiveWrapper, home: const ProfileScreen()),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Alex Smith'), findsWidgets);
      expect(find.text('alex@example.com'), findsOneWidget);
      expect(find.text('Privacy policy'), findsOneWidget);
      expect(find.text('Terms of service'), findsOneWidget);
    });
  });
}
