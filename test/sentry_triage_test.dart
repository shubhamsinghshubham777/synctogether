import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:synctogether/diagnostics.dart';
import 'package:synctogether/rooms/media_sharing_service.dart';

void main() {
  group('isMissingPkceVerifier', () {
    test('matches the stale and mismatched callbacks', () {
      expect(
        isMissingPkceVerifier(AuthException('Code verifier could not be found in local storage.')),
        isTrue,
      );
      expect(isMissingPkceVerifier(AuthException('code challenge does not match')), isTrue);
    });

    test('leaves real auth failures and other types alone', () {
      expect(isMissingPkceVerifier(AuthException('Invalid login credentials')), isFalse);
      expect(isMissingPkceVerifier(StateError('Code verifier could not be found')), isFalse);
    });
  });

  group('media sharing refusals', () {
    // The RPC's code, and the canonical code the app maps it to.
    const mapped = {
      'active_upload_in_progress': 'concurrent_upload_active',
      'upload_cooldown_active': 'upload_cooldown_active',
    };
    for (final MapEntry(key: code, value: canonical) in mapped.entries) {
      test('$code is a named, expected refusal', () {
        final e = MediaSharingException.fromError({'error': code});
        expect(e.code, canonical);
        expect(e.isExpectedRefusal, isTrue);
        expect(e.message, isNot(contains("didn't go through")));
      });
    }

    test('an unmapped server code is still reported', () {
      final e = MediaSharingException.fromError({'error': 's3_initiate_failed'});
      expect(e.isExpectedRefusal, isFalse);
    });
  });
}
