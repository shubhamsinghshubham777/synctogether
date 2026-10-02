import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Consecutive connect failures on one endpoint, with the token fetch
/// succeeding each time, before we ask for a different endpoint. A refusal
/// (`NotAllowed`, which is how a free LiveKit Cloud project answers once its
/// monthly cap is spent) moves on at once.
const kAvFailoverAfterFailures = 2;

/// Endpoint hops allowed inside one connect attempt before falling back to the
/// ordinary backoff. Bounded so a fully broken network can't spin.
const kAvMaxHopsPerAttempt = 3;

/// Fallback wait before asking again once every endpoint is exhausted, when
/// the server didn't say.
const kAvExhaustedRetry = Duration(minutes: 5);

/// Every endpoint the token function knows is spent or down. An expected
/// answer, not a bug: the room carries on without facecams.
class AvCapacityExhausted implements Exception {
  const AvCapacityExhausted(this.retryAfter);

  final Duration retryAfter;

  @override
  String toString() => 'AvCapacityExhausted(retry in ${retryAfter.inSeconds}s)';
}

/// What a connect failure says about the endpoint we were sent to.
enum AvEndpointVerdict {
  /// The SFU answered and said no - spent quota or a bad key. Move now.
  refused,

  /// The SFU didn't answer although our own token fetch just worked, so the
  /// network is up. Move once it has happened [kAvFailoverAfterFailures] times.
  unreachable,

  /// Nothing to do with the endpoint.
  unrelated,
}

/// Judges an error thrown by `Room.connect` - only ever after a token was
/// minted, which is what lets an unreachable SFU be blamed on the SFU.
AvEndpointVerdict judgeConnectFailure(Object error) => switch (error) {
  lk.ConnectException(:final reason) when reason == lk.ConnectionErrorReason.NotAllowed => .refused,
  lk.ConnectException() || lk.MediaConnectException() || lk.TimeoutException() => .unreachable,
  _ => .unrelated,
};

/// Whether to report [verdict] as a failed endpoint and ask for another.
bool shouldFailOver(AvEndpointVerdict verdict, int consecutiveFailures) => switch (verdict) {
  .refused => true,
  .unreachable => consecutiveFailures >= kAvFailoverAfterFailures,
  .unrelated => false,
};

/// Reads the token function's "nothing left" answer; null for anything else.
AvCapacityExhausted? capacityExhaustedFrom(Object error) {
  if (error is! FunctionException || error.status != 503) return null;
  final details = error.details;
  if (details is! Map || details['error'] != 'av_capacity_exhausted') return null;
  final seconds = details['retry_after_s'];
  return AvCapacityExhausted(
    seconds is num && seconds > 0 ? Duration(seconds: seconds.toInt()) : kAvExhaustedRetry,
  );
}
