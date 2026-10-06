import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:synctogether/diagnostics.dart';

void main() {
  group('isTransientNetworkError', () {
    test('connectivity failures are transient', () {
      expect(isTransientNetworkError(const SocketException('Failed host lookup')), isTrue);
      expect(isTransientNetworkError(const OSError('Connection reset by peer', 54)), isTrue);
      expect(isTransientNetworkError(TimeoutException('slow')), isTrue);
      expect(isTransientNetworkError(ClientException('Connection reset by peer')), isTrue);
      expect(
        isTransientNetworkError(AuthRetryableFetchException(message: 'Operation timed out')),
        isTrue,
      );
      expect(
        isTransientNetworkError(const HandshakeException('Connection terminated during handshake')),
        isTrue,
      );
    });

    test('a certificate failure is not transient - lib/tls.dart must see it', () {
      expect(
        isTransientNetworkError(
          const HandshakeException(
            'Handshake error in client',
            OSError('CERTIFICATE_VERIFY_FAILED: unable to get local issuer certificate'),
          ),
        ),
        isFalse,
      );
    });

    test('upstream 5xx is transient, a real answer is not', () {
      expect(isTransientNetworkError(const PostgrestException(message: 'x', code: '520')), isTrue);
      expect(isTransientNetworkError(const PostgrestException(message: 'x', code: '500')), isTrue);
      // Cloudflare's body, with no code at all.
      expect(isTransientNetworkError(const PostgrestException(message: 'error code: 520')), isTrue);
      expect(
        isTransientNetworkError(const PostgrestException(message: 'not_host', code: 'P0001')),
        isFalse,
      );
      expect(
        isTransientNetworkError(const PostgrestException(message: 'rls', code: '42501')),
        isFalse,
      );
      expect(isTransientNetworkError(const FunctionException(status: 503)), isTrue);
      expect(isTransientNetworkError(const FunctionException(status: 0)), isTrue);
      expect(isTransientNetworkError(const FunctionException(status: 403)), isFalse);
    });

    test('an expired or revoked session is expected, not a bug', () {
      expect(
        isTransientNetworkError(const PostgrestException(message: 'JWT expired', code: 'PGRST303')),
        isTrue,
      );
      expect(
        isTransientNetworkError(
          AuthApiException('gone', statusCode: '400', code: 'refresh_token_not_found'),
        ),
        isTrue,
      );
      expect(
        isTransientNetworkError(AuthApiException('bad', statusCode: '400', code: 'weak_password')),
        isFalse,
      );
    });

    test('a persistent outage is not transient, so beforeSend lets it through', () {
      const outage = PersistentOutage(SocketException('Failed host lookup'));
      expect(isTransientNetworkError(outage), isFalse);
      expect(outage.toString(), contains('Failed host lookup'));
    });

    test('ordinary bugs are not transient', () {
      expect(isTransientNetworkError(StateError('bad')), isFalse);
      expect(isTransientNetworkError(const FormatException('x')), isFalse);
    });
  });
}
