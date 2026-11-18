import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:synctogether/auth/auth_errors.dart';

void main() {
  group('friendlyAuthMessage', () {
    test('never shows GoTrue\'s raw captcha text', () {
      const raw = 'captcha protection: request disallowed (invalid-input-response)';
      final copy = friendlyAuthMessage(const AuthException(raw));
      expect(copy, isNot(contains('captcha')));
      expect(copy, contains('person'));
    });

    test('rate limits ask the user to wait', () {
      expect(
        friendlyAuthMessage(const AuthException('x', statusCode: '429')),
        contains('Wait a minute'),
      );
      expect(
        friendlyAuthMessage(const AuthException('x', code: 'over_email_send_rate_limit')),
        contains('Wait a minute'),
      );
    });

    test('an expired code asks for a new one', () {
      expect(
        friendlyAuthMessage(const AuthException('Token has expired', code: 'otp_expired')),
        contains('new one'),
      );
    });

    test('anything unknown falls back to a friendly retry, not the server text', () {
      const raw = 'Database error saving new user';
      final copy = friendlyAuthMessage(const AuthException(raw));
      expect(copy, isNot(contains(raw)));
      expect(copy, "Couldn't sign you in. Give it another try.");
    });
  });
}
