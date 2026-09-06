import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:synctogether/auth/auth_service.dart';
import 'package:synctogether/env.dart';

void main() {
  group('AuthService unconfigured backend', () {
    tearDown(Env.resetOverridesForTesting);

    test('throws AuthException when Supabase URL is empty', () async {
      Env.overrideReleaseMode = true;
      expect(Env.supabaseUrl, isEmpty);

      final auth = AuthService();
      expect(
        () => auth.sendEmailOtp('test@example.com'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            contains('Backend service URL is not configured'),
          ),
        ),
      );

      expect(
        () => auth.verifyEmailOtp(email: 'test@example.com', token: '123456'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            contains('Backend service URL is not configured'),
          ),
        ),
      );

      expect(
        () => auth.signInAsGuest(),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            contains('Backend service URL is not configured'),
          ),
        ),
      );

      expect(
        () => auth.signInWithApple(),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            contains('Backend service URL is not configured'),
          ),
        ),
      );
    });
  });
}
