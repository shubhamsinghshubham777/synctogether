import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:synctogether/auth/auth_service.dart';

void main() {
  const missing = AuthException('Code verifier could not be found in local storage.');
  AuthStreamOutcome classify(Object e, {bool awaiting = true, bool session = false}) =>
      AuthService.classifyAuthStreamError(e, awaitingCallback: awaiting, hasSession: session);

  test('missing verifier and no session is a stale callback', () {
    expect(classify(missing), AuthStreamOutcome.staleCallback);
  });
  test('missing verifier with a session is a duplicate', () {
    expect(classify(missing, session: true), AuthStreamOutcome.duplicateCallback);
  });
  test('window closed is ignored', () {
    expect(classify(missing, awaiting: false), AuthStreamOutcome.ignore);
  });
  test('other errors inside the window are failures', () {
    expect(classify(const AuthException('boom')), AuthStreamOutcome.failure);
  });
}
