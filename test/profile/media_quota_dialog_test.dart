import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/profile/entitlement_service.dart';
import 'package:synctogether/profile/media_quota_dialog.dart';
import 'package:synctogether/profile/profile_models.dart';
import 'package:synctogether/profile/profile_service.dart';

void main() {
  group('MediaQuotaDialog', () {
    tearDown(() {
      ProfileService.instance.setProfileForTesting(null);
      EntitlementService.instance.setLimitsForTesting(null);
    });

    testWidgets('renders guest view with Google sign-in and Go Premium CTAs', (tester) async {
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
        MaterialApp(
          theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: const Color(0xFF0D0B14)),
          home: const Scaffold(
            body: Center(child: SingleChildScrollView(child: MediaQuotaDialogBody())),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Media Sharing Quota'), findsOneWidget);
      expect(find.text('Sign in to unlock weekly quota'), findsOneWidget);
      expect(find.text('How Quotas Work'), findsOneWidget);
      expect(find.text('Sign in with Google (Free 2.5 GB)'), findsOneWidget);
      expect(find.text('Sign in with Email (Free 2.5 GB)'), findsOneWidget);
      expect(find.text('Go Premium (Unlimited)'), findsOneWidget);
    });

    testWidgets('renders contextual blockage card when single file limit is exceeded', (
      tester,
    ) async {
      ProfileService.instance.setProfileForTesting(
        const Profile(
          id: 'user-1',
          displayName: 'Alex',
          isGuest: false,
          r2UploadBytes7d: 500 * 1024 * 1024,
        ),
      );
      EntitlementService.instance.setLimitsForTesting(TierLimits.fallback);

      const fileSize = 2500 * 1024 * 1024;
      const maxBytes = 2048 * 1024 * 1024;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: const Color(0xFF0D0B14)),
          home: const Scaffold(
            body: Center(
              child: SingleChildScrollView(
                child: MediaQuotaDialogBody(
                  quotaContext: MediaQuotaContext(
                    reason: .singleFileLimitExceeded,
                    fileName: 'vacation_4k.mp4',
                    fileSize: fileSize,
                    maxBytes: maxBytes,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('SINGLE-FILE LIMIT EXCEEDED'), findsOneWidget);
      expect(find.text('Video Exceeds Free File Limit'), findsOneWidget);
      expect(find.text('vacation_4k.mp4'), findsOneWidget);
      expect(find.text('Upgrade for 10.0 GB Files'), findsOneWidget);
      expect(find.text('Selected Video'), findsOneWidget);
      expect(find.text('Free Plan Cap'), findsOneWidget);
      expect(find.text('Over limit by'), findsOneWidget);
    });

    testWidgets('renders contextual blockage card when weekly quota is exceeded', (tester) async {
      ProfileService.instance.setProfileForTesting(
        const Profile(
          id: 'user-1',
          displayName: 'Alex',
          isGuest: false,
          r2UploadBytes7d: 2000 * 1024 * 1024,
        ),
      );
      EntitlementService.instance.setLimitsForTesting(TierLimits.fallback);

      const fileSize = 800 * 1024 * 1024;
      const remainingBytes = 500 * 1024 * 1024;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: const Color(0xFF0D0B14)),
          home: const Scaffold(
            body: Center(
              child: SingleChildScrollView(
                child: MediaQuotaDialogBody(
                  quotaContext: MediaQuotaContext(
                    reason: .weeklyQuotaExceeded,
                    fileName: 'episode_01.mp4',
                    fileSize: fileSize,
                    remainingBytes: remainingBytes,
                    maxBytes: 2500 * 1024 * 1024,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('WEEKLY QUOTA EXCEEDED'), findsOneWidget);
      expect(find.text('Insufficient Weekly Quota'), findsOneWidget);
      expect(find.text('episode_01.mp4'), findsOneWidget);
      expect(find.text('Get Unlimited with Premium'), findsOneWidget);
      expect(find.text('Selected Video'), findsOneWidget);
      expect(find.text('Remaining'), findsOneWidget);
      expect(find.text('Quota shortfall'), findsOneWidget);
    });

    testWidgets('renders contextual blockage card for guest user attempting upload', (
      tester,
    ) async {
      ProfileService.instance.setProfileForTesting(
        const Profile(id: 'guest-1', displayName: 'Guest-999', isGuest: true),
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
        MaterialApp(
          theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: const Color(0xFF0D0B14)),
          home: const Scaffold(
            body: Center(
              child: SingleChildScrollView(
                child: MediaQuotaDialogBody(quotaContext: MediaQuotaContext(reason: .guestBlocked)),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('SIGN-IN REQUIRED'), findsOneWidget);
      expect(find.text('Media Sharing Requires an Account'), findsOneWidget);
      expect(find.text('Sign in with Google (Free 2.5 GB)'), findsOneWidget);
      expect(find.text('Sign in with Email (Free 2.5 GB)'), findsOneWidget);
    });

    testWidgets('renders signed-in free user view with quota usage and upgrade button', (
      tester,
    ) async {
      ProfileService.instance.setProfileForTesting(
        const Profile(
          id: 'user-1',
          displayName: 'Alex',
          isGuest: false,
          r2UploadBytes7d: 500 * 1024 * 1024,
        ),
      );
      EntitlementService.instance.setLimitsForTesting(TierLimits.fallback);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: const Color(0xFF0D0B14)),
          home: const Scaffold(
            body: Center(child: SingleChildScrollView(child: MediaQuotaDialogBody())),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Media Sharing Quota'), findsOneWidget);
      expect(find.text('7-Day Rolling Usage'), findsOneWidget);
      expect(find.text('Get Unlimited with Premium'), findsOneWidget);
      expect(find.text('Got it'), findsOneWidget);
    });

    testWidgets('renders premium user view with unlimited status', (tester) async {
      ProfileService.instance.setProfileForTesting(
        const Profile(id: 'user-2', displayName: 'Sam', isGuest: false),
      );
      EntitlementService.instance.setLimitsForTesting(
        const TierLimits(
          tier: kPremiumTier,
          maxLiveRooms: 20,
          maxMembers: 16,
          maxSessionMinutes: 240,
          maxTotalSessionMinutes: 1440,
          avLevel: .video,
          persistentRoomCap: 20,
          dormantHours: 24,
          freeExtensionMinutes: 0,
          mediaSharing: 'full',
          mediaSharingWeeklyBytes: 0,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: const Color(0xFF0D0B14)),
          home: const Scaffold(
            body: Center(child: SingleChildScrollView(child: MediaQuotaDialogBody())),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Media Sharing Quota'), findsOneWidget);
      expect(find.text('Unlimited with Premium'), findsOneWidget);
      expect(
        find.text('No upload limits! Share videos up to 10.0 GB each with high-speed priority.'),
        findsOneWidget,
      );
      expect(find.text('Got it'), findsOneWidget);
    });

    testWidgets('adapts smoothly to constrained screen height without overflow', (tester) async {
      ProfileService.instance.setProfileForTesting(
        const Profile(
          id: 'user-1',
          displayName: 'Alex',
          isGuest: false,
          r2UploadBytes7d: 500 * 1024 * 1024,
        ),
      );
      EntitlementService.instance.setLimitsForTesting(TierLimits.fallback);

      // Simulate a compact 560px window height
      tester.view.physicalSize = const Size(800, 560);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: const Color(0xFF0D0B14)),
          home: const Scaffold(
            body: Center(
              child: MediaQuotaDialogBody(
                quotaContext: MediaQuotaContext(
                  reason: .singleFileLimitExceeded,
                  fileName: 'Casino Royale 4K.mkv',
                  fileSize: 7400 * 1024 * 1024,
                  maxBytes: 2048 * 1024 * 1024,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify no overflow occurred
      expect(tester.takeException(), isNull);
      // Verify pinned header and pinned action buttons remain accessible
      expect(find.text('Media Sharing Quota'), findsOneWidget);
      expect(find.text('Upgrade for 10.0 GB Files'), findsOneWidget);
      expect(find.text('Got it'), findsOneWidget);
    });
  });
}
