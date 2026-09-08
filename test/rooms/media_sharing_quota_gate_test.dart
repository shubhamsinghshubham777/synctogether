import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/profile/entitlement_service.dart';
import 'package:synctogether/profile/profile_models.dart';

void main() {
  group('Media Sharing Quota Gating Logic', () {
    const premiumLimits = TierLimits(
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
    );

    const freeLimits = TierLimits(
      tier: kFreeTier,
      maxLiveRooms: 4,
      maxMembers: 8,
      maxSessionMinutes: 240,
      maxTotalSessionMinutes: 240,
      avLevel: .voice,
      persistentRoomCap: 0,
      dormantHours: 24,
      freeExtensionMinutes: 0,
      mediaSharing: 'limited',
      mediaSharingWeeklyBytes: 2684354560, // 2.5 GB
    );

    const guestLimits = TierLimits(
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

    test('premium tier has unlimited sharing and no weekly quota check', () {
      expect(premiumLimits.isPremium, isTrue);
      expect(premiumLimits.hasUnlimitedSharing, isTrue);
      expect(premiumLimits.hasWeeklyQuota, isFalse);
      expect(premiumLimits.mediaSharingMaxSizeBytes, 10737418240); // 10 GB

      final profile = Profile(
        id: 'u-prem',
        displayName: 'PremiumUser',
        isGuest: false,
        r2UploadBytes7d: 5 * 1024 * 1024 * 1024, // 5 GB uploaded previously
      );

      // Remaining bytes for unlimited tier returns -1 (unlimited)
      final remaining = profile.remainingWeeklyBytes(premiumLimits.mediaSharingWeeklyBytes);
      expect(remaining, -1);
      expect(Profile.formatBytes(remaining), '∞ B');

      // A 117 MB video (like in the reported bug) easily fits under single-file limit
      const fileSize = 117 * 1024 * 1024;
      expect(fileSize <= premiumLimits.mediaSharingMaxSizeBytes, isTrue);

      // Weekly quota check MUST be skipped because hasWeeklyQuota is false
      final shouldCheckWeeklyQuota = premiumLimits.hasWeeklyQuota;
      expect(shouldCheckWeeklyQuota, isFalse);
    });

    test('free tier enforces weekly quota and 2 GB single file limit', () {
      expect(freeLimits.isPremium, isFalse);
      expect(freeLimits.hasUnlimitedSharing, isFalse);
      expect(freeLimits.hasWeeklyQuota, isTrue);
      expect(freeLimits.mediaSharingMaxSizeBytes, 2147483648); // 2 GB

      final now = DateTime.now();
      final profile = Profile(
        id: 'u-free',
        displayName: 'FreeUser',
        isGuest: false,
        r2UploadBytes7d: 2500 * 1024 * 1024, // 2.5 GB used out of 2.5 GB
        r2UploadWindowStart: now.subtract(const Duration(days: 2)),
      );

      final remaining = profile.remainingWeeklyBytes(freeLimits.mediaSharingWeeklyBytes);
      expect(
        remaining,
        (freeLimits.mediaSharingWeeklyBytes - profile.r2UploadBytes7d).clamp(
          0,
          freeLimits.mediaSharingWeeklyBytes,
        ),
      );

      const fileSize = 117 * 1024 * 1024;
      final exceedsWeekly = freeLimits.hasWeeklyQuota && fileSize > remaining;
      expect(exceedsWeekly, isTrue);
    });

    test('guest tier cannot share media and has no weekly quota', () {
      expect(guestLimits.canShareMedia, isFalse);
      expect(guestLimits.hasWeeklyQuota, isFalse);
    });
  });
}
