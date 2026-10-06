import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/rooms/moderation_service.dart';

void main() {
  group('ReportReason', () {
    test('contains all expected report reasons with valid wire strings', () {
      expect(ReportReason.copyright.wire, 'copyright');
      expect(ReportReason.copyright.label, 'Copyright infringement');

      expect(ReportReason.harassment.wire, 'harassment');
      expect(ReportReason.hateSpeech.wire, 'hate_speech');
      expect(ReportReason.sexualContent.wire, 'sexual_content');
      expect(ReportReason.violence.wire, 'violence');
      expect(ReportReason.spam.wire, 'spam');
      expect(ReportReason.other.wire, 'other');

      for (final reason in ReportReason.values) {
        expect(reason.wire, isNotEmpty);
        expect(reason.label, isNotEmpty);
      }
    });
  });

  group('BlockedUser', () {
    test('fromJson parses correctly', () {
      final json = {
        'user_id': 'user-123',
        'display_name': 'PirateCaptain',
        'avatar_url': 'https://example.com/avatar.png',
        'created_at': '2026-10-04T12:00:00.000Z',
      };

      final blocked = BlockedUser.fromJson(json);
      expect(blocked.userId, 'user-123');
      expect(blocked.displayName, 'PirateCaptain');
      expect(blocked.avatarUrl, 'https://example.com/avatar.png');
      expect(blocked.blockedAt, DateTime.utc(2026, 10, 4, 12));
    });

    test('fromJson provides fallback display name when null', () {
      final json = {
        'user_id': 'user-456',
        'display_name': null,
        'created_at': '2026-10-04T12:00:00.000Z',
      };

      final blocked = BlockedUser.fromJson(json);
      expect(blocked.displayName, 'Someone');
      expect(blocked.avatarUrl, isNull);
    });
  });

  group('ModerationService in-memory state', () {
    late ModerationService service;

    setUp(() {
      service = ModerationService();
    });

    test('starts empty with no blocks', () {
      expect(service.hasBlocks, isFalse);
      expect(service.blockedIds, isEmpty);
      expect(service.blockedUsers, isEmpty);
      expect(service.isBlocked('user-1'), isFalse);
      expect(service.isBlocked(null), isFalse);
    });

    test('setBlockedForTesting sets blocked ids and notifies listeners', () {
      var notified = false;
      service.addListener(() => notified = true);

      service.setBlockedForTesting({'user-1', 'user-2'});

      expect(notified, isTrue);
      expect(service.hasBlocks, isTrue);
      expect(service.isBlocked('user-1'), isTrue);
      expect(service.isBlocked('user-2'), isTrue);
      expect(service.isBlocked('user-3'), isFalse);
    });

    test('clear resets blocked state', () {
      service.setBlockedForTesting({'user-1'});
      expect(service.hasBlocks, isTrue);

      service.clear();
      expect(service.hasBlocks, isFalse);
      expect(service.isBlocked('user-1'), isFalse);
    });
  });
}
