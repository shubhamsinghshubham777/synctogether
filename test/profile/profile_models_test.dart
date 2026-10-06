import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/profile/profile_models.dart';

void main() {
  group('Profile Quota Helpers', () {
    test('formatBytes formats various byte sizes correctly', () {
      expect(Profile.formatBytes(-1), '∞ B');
      expect(Profile.formatBytes(0), '0 B');
      expect(Profile.formatBytes(512), '512 B');
      expect(Profile.formatBytes(1024), '1.0 KB');
      expect(Profile.formatBytes(10 * 1024 * 1024), '10 MB');
      expect(Profile.formatBytes(4294967296), '4.0 GB');
      expect(Profile.formatBytes(10737418240), '10 GB');
    });

    test('remainingWeeklyBytes computes remaining bandwidth', () {
      final now = DateTime.now();
      final profile = Profile(
        id: 'u1',
        displayName: 'Alice',
        isGuest: false,
        r2UploadBytes7d: 1024 * 1024 * 1024, // 1 GB
        r2UploadWindowStart: now.subtract(const Duration(days: 2)),
      );

      const weeklyLimit = 4 * 1024 * 1024 * 1024; // 4 GB
      expect(profile.remainingWeeklyBytes(weeklyLimit), 3 * 1024 * 1024 * 1024);
    });

    test('remainingWeeklyBytes returns -1 for unlimited weekly quota', () {
      final profile = Profile(
        id: 'u1',
        displayName: 'Alice',
        isGuest: false,
        r2UploadBytes7d: 1024 * 1024 * 1024,
      );

      expect(profile.remainingWeeklyBytes(0), -1);
      expect(Profile.formatBytes(profile.remainingWeeklyBytes(0)), '∞ B');
    });

    test('remainingWeeklyBytes resets if window start is older than 7 days', () {
      final now = DateTime.now();
      final profile = Profile(
        id: 'u1',
        displayName: 'Alice',
        isGuest: false,
        r2UploadBytes7d: 4 * 1024 * 1024 * 1024, // 4 GB
        r2UploadWindowStart: now.subtract(const Duration(days: 8)),
      );

      const weeklyLimit = 4 * 1024 * 1024 * 1024;
      expect(profile.remainingWeeklyBytes(weeklyLimit), weeklyLimit);
    });

    test('fromJson and copyWith preserve quota fields', () {
      final windowStart = DateTime.now().toUtc();
      final json = {
        'id': 'u1',
        'display_name': 'Alice',
        'is_guest': false,
        'email': 'alice@example.com',
        'r2_upload_bytes_7d': 500000,
        'r2_upload_window_start': windowStart.toIso8601String(),
        'r2_cooldown_until': null,
      };

      final profile = Profile.fromJson(json);
      expect(profile.r2UploadBytes7d, 500000);
      expect(profile.r2UploadWindowStart?.toIso8601String(), windowStart.toIso8601String());

      final updated = profile.copyWith(r2UploadBytes7d: 800000);
      expect(updated.r2UploadBytes7d, 800000);
      expect(updated.displayName, 'Alice');
    });

    test('moderation status and warning flags', () {
      final unmoderated = Profile(id: 'u1', displayName: 'Alice', isGuest: false);
      expect(unmoderated.isBanned, isFalse);
      expect(unmoderated.isWarned, isFalse);
      expect(unmoderated.needsWarningAcknowledgment, isFalse);
      expect(unmoderated.strikesCount, 0);

      final warnedUnacknowledged = Profile(
        id: 'u2',
        displayName: 'Bob',
        isGuest: false,
        strikesCount: 1,
        moderationStatus: 'warned',
        warningReason: 'Shared copyrighted video',
        warningAcknowledged: false,
      );
      expect(warnedUnacknowledged.isWarned, isTrue);
      expect(warnedUnacknowledged.needsWarningAcknowledgment, isTrue);
      expect(warnedUnacknowledged.isBanned, isFalse);

      final warnedAcknowledged = warnedUnacknowledged.copyWith(warningAcknowledged: true);
      expect(warnedAcknowledged.isWarned, isTrue);
      expect(warnedAcknowledged.needsWarningAcknowledgment, isFalse);

      final banned = Profile(
        id: 'u3',
        displayName: 'Charlie',
        isGuest: false,
        strikesCount: 2,
        moderationStatus: 'banned',
        banReason: 'Repeated copyright violations',
      );
      expect(banned.isBanned, isTrue);
      expect(banned.isWarned, isFalse);
      expect(banned.needsWarningAcknowledgment, isFalse);
    });

    test('fromJson parses moderation fields correctly', () {
      final json = {
        'id': 'u4',
        'display_name': 'Dave',
        'is_guest': false,
        'strikes_count': 1,
        'moderation_status': 'warned',
        'warning_reason': 'DMCA infringement notice',
        'warning_acknowledged': false,
        'ban_reason': null,
      };

      final profile = Profile.fromJson(json);
      expect(profile.strikesCount, 1);
      expect(profile.moderationStatus, 'warned');
      expect(profile.warningReason, 'DMCA infringement notice');
      expect(profile.warningAcknowledged, isFalse);
      expect(profile.isWarned, isTrue);
      expect(profile.needsWarningAcknowledgment, isTrue);
      expect(profile.isBanned, isFalse);
    });
  });
}
