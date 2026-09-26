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

    testWidgets('renders guest view with sign-in and Get a Patron seat CTAs', (tester) async {
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

      expect(find.text('Sharing needs an account'), findsOneWidget);
      expect(find.text('Sign in with Google (Free 2.5 GB)'), findsOneWidget);
      expect(find.text('Sign in with Email (Free 2.5 GB)'), findsOneWidget);
      expect(find.text('Maybe later'), findsOneWidget);
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

      expect(find.text('Too big to share'), findsOneWidget);
      expect(find.text('vacation_4k.mp4'), findsOneWidget);
      expect(find.text('Play it locally'), findsOneWidget);
      expect(find.text('Patron seats share up to 10 GB'), findsOneWidget);
      expect(find.text('FILE'), findsOneWidget);
      expect(find.text('FREE CAP'), findsOneWidget);
      expect(find.text('OVER BY'), findsOneWidget);
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

      expect(find.text('Not enough allowance left'), findsOneWidget);
      expect(find.text('episode_01.mp4'), findsOneWidget);
      expect(find.text('Patron seats have no weekly cap'), findsOneWidget);
      expect(find.text('FILE'), findsOneWidget);
      expect(find.text('LEFT'), findsOneWidget);
      expect(find.text('SHORT BY'), findsOneWidget);
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

      expect(find.text('Sharing needs an account'), findsOneWidget);
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

      expect(find.text('Sharing allowance'), findsOneWidget);
      expect(find.textContaining('USED THIS WEEK'), findsOneWidget);
      expect(find.text('Get a Patron seat'), findsOneWidget);
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

      expect(find.text('Sharing allowance'), findsOneWidget);
      expect(find.text('No weekly cap. Share videos up to 10 GB each.'), findsOneWidget);
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
      expect(find.text('Too big to share'), findsOneWidget);
      expect(find.text('Play it locally'), findsOneWidget);
    });

    testWidgets('renders premium single-file limit blockage card correctly', (tester) async {
      ProfileService.instance.setProfileForTesting(
        const Profile(id: 'user-prem', displayName: 'Sam', isGuest: false),
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

      const fileSize = 12 * 1024 * 1024 * 1024; // 12 GB
      const maxBytes = 10 * 1024 * 1024 * 1024; // 10 GB

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: const Color(0xFF0D0B14)),
          home: const Scaffold(
            body: Center(
              child: SingleChildScrollView(
                child: MediaQuotaDialogBody(
                  quotaContext: MediaQuotaContext(
                    reason: .singleFileLimitExceeded,
                    fileName: 'giant_movie.mkv',
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

      expect(find.text('Too big to share'), findsOneWidget);
      expect(find.text('PATRON CAP'), findsOneWidget);
      expect(find.text('OVER BY'), findsOneWidget);
      expect(find.text('2.0 GB'), findsOneWidget);
      expect(find.text('Play it locally'), findsOneWidget);
    });

    testWidgets('renders infinity symbol for unlimited remaining quota', (tester) async {
      ProfileService.instance.setProfileForTesting(
        const Profile(id: 'user-prem', displayName: 'Sam', isGuest: false),
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
            body: Center(
              child: SingleChildScrollView(
                child: MediaQuotaDialogBody(
                  quotaContext: MediaQuotaContext(
                    reason: .weeklyQuotaExceeded,
                    fileName: 'video.mp4',
                    fileSize: 500 * 1024 * 1024,
                    remainingBytes: -1,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Unlimited (-1) has no meaningful "left" or shortfall to show.
      expect(find.text('LEFT'), findsNothing);
      expect(find.text('SHORT BY'), findsNothing);
    });
  });
}
