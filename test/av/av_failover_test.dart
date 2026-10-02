import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:synctogether/av/av_failover.dart';
import 'package:synctogether/av/livekit_service.dart';

FunctionException _exhausted([Object? retry = 120]) => FunctionException(
  status: 503,
  details: {'error': 'av_capacity_exhausted', 'retry_after_s': retry},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('judgeConnectFailure', () {
    test('a refused token is the endpoint saying no', () {
      expect(
        judgeConnectFailure(lk.ConnectException('no', reason: lk.ConnectionErrorReason.NotAllowed)),
        AvEndpointVerdict.refused,
      );
    });

    test('a silent SFU is unreachable', () {
      expect(
        judgeConnectFailure(lk.ConnectException('x', reason: lk.ConnectionErrorReason.Timeout)),
        AvEndpointVerdict.unreachable,
      );
      expect(judgeConnectFailure(lk.MediaConnectException('x')), AvEndpointVerdict.unreachable);
    });

    test('anything else is not the endpoint', () {
      expect(judgeConnectFailure(StateError('x')), AvEndpointVerdict.unrelated);
    });
  });

  group('shouldFailOver', () {
    test('refusal moves at once', () {
      expect(shouldFailOver(.refused, 0), isTrue);
    });

    test('unreachable waits for repeat failures, so one blip does not move a room', () {
      expect(shouldFailOver(.unreachable, 1), isFalse);
      expect(shouldFailOver(.unreachable, kAvFailoverAfterFailures), isTrue);
    });

    test('unrelated never moves', () {
      expect(shouldFailOver(.unrelated, 99), isFalse);
    });
  });

  group('capacityExhaustedFrom', () {
    test('reads the server retry hint', () {
      expect(capacityExhaustedFrom(_exhausted())?.retryAfter, const Duration(seconds: 120));
    });

    test('falls back when the hint is missing', () {
      expect(capacityExhaustedFrom(_exhausted(null))?.retryAfter, kAvExhaustedRetry);
    });

    test('ignores other 503s and other errors', () {
      expect(capacityExhaustedFrom(const FunctionException(status: 503)), isNull);
      expect(capacityExhaustedFrom(const FunctionException(status: 403)), isNull);
      expect(capacityExhaustedFrom(StateError('x')), isNull);
    });
  });

  group('LiveKitService when every endpoint is spent', () {
    setUp(() => LiveKitService.isConfiguredOverride = true);
    tearDown(() => LiveKitService.isConfiguredOverride = null);

    test('rests instead of erroring, and keeps the mic wish for later', () async {
      var calls = 0;
      final service = LiveKitService(
        roomId: 'room-1',
        avLevel: .video,
        fetchToken: (_, {failedEndpoint, forceEndpoint}) async {
          calls++;
          throw _exhausted();
        },
      );

      await service.connect();
      expect(service.state, AvConnectionState.unavailable);
      expect(calls, 1);

      await service.setMicEnabled(true);
      expect(service.micEnabled, isTrue);

      service.dispose();
    });
  });
}
