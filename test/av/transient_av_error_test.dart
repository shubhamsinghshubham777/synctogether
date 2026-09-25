import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:synctogether/av/livekit_service.dart';

void main() {
  test('an unreachable backend is transient', () {
    // The local stack with no functions runtime answers exactly this.
    expect(
      isTransientAvError(
        const FunctionsHttpException(status: 503, details: {'message': 'name resolution failed'}),
      ),
      isTrue,
    );
    expect(isTransientAvError(const FunctionsFetchException()), isTrue);
    expect(isTransientAvError(const FunctionException(status: 429)), isTrue);
    expect(isTransientAvError(const SocketException('offline')), isTrue);
    expect(isTransientAvError(TimeoutException('slow')), isTrue);
    expect(
      isTransientAvError(lk.ConnectException('ws', reason: lk.ConnectionErrorReason.Timeout)),
      isTrue,
    );
  });

  test('a real answer from the token function is not', () {
    expect(isTransientAvError(const FunctionException(status: 403)), isFalse);
    expect(isTransientAvError(const FunctionException(status: 400)), isFalse);
    expect(
      isTransientAvError(lk.ConnectException('401', reason: lk.ConnectionErrorReason.NotAllowed)),
      isFalse,
    );
    expect(isTransientAvError(StateError('bug')), isFalse);
    expect(isTransientAvError(const FormatException('bad token payload')), isFalse);
  });
}
