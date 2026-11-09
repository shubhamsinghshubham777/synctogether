import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:synctogether/app_router.dart';

void main() {
  group('which auth events register this device for push', () {
    test('a sign-in, a refresh and a profile update do', () {
      for (final e in [
        AuthChangeEvent.signedIn,
        AuthChangeEvent.tokenRefreshed,
        AuthChangeEvent.userUpdated,
      ]) {
        expect(authEventStartsPush(e, hasSession: true), isTrue, reason: '$e');
      }
    });

    test('a cold start that restored a session does - the case that was missed', () {
      expect(authEventStartsPush(AuthChangeEvent.initialSession, hasSession: true), isTrue);
    });

    test('a cold start with nobody signed in does not', () {
      expect(authEventStartsPush(AuthChangeEvent.initialSession, hasSession: false), isFalse);
    });

    test('signing out and the rest do not', () {
      expect(authEventStartsPush(AuthChangeEvent.signedOut, hasSession: false), isFalse);
      expect(authEventStartsPush(AuthChangeEvent.passwordRecovery, hasSession: true), isFalse);
    });
  });
}
