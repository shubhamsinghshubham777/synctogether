import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' show ClientException;
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthApiException, AuthRetryableFetchException, FunctionException, PostgrestException;

/// Whether [error] is the network or an upstream proxy failing rather than
/// our code: an offline laptop, a dropped Wi-Fi, a reset socket, Cloudflare
/// answering 5xx in front of Supabase. These are retried or recovered from by
/// whoever caught them, and reporting them buried every real issue in Sentry
/// under connection resets.
///
/// A certificate failure is deliberately *not* transient - that is the
/// Windows root-store bug `lib/tls.dart` exists for, and it must stay visible.
bool isTransientNetworkError(Object error) => switch (error) {
  HandshakeException(:final message, :final osError) =>
    !'$message ${osError?.message ?? ''}'.contains('CERTIFICATE'),
  TlsException() => false,
  SocketException() || OSError() || HttpException() || TimeoutException() => true,
  ClientException() || AuthRetryableFetchException() => true,
  // An access token that expired between refreshes, or a refresh token the
  // server no longer knows (signed out elsewhere, session revoked). The SDK
  // refreshes or signs out and the router redirects; there is nothing to fix.
  AuthApiException(:final code) =>
    code == 'refresh_token_not_found' ||
        code == 'session_not_found' ||
        code == 'refresh_token_already_used',
  PostgrestException(:final code) when code == 'PGRST303' => true,
  FunctionException(:final status) =>
    status == 0 || status == 408 || status == 429 || status >= 500,
  // `code` is an HTTP status for gateway failures (Cloudflare's 520) but a
  // five-character SQLSTATE for real answers - 42501 is RLS, not a 5xx.
  PostgrestException(:final code, :final message) => switch (_gatewayStatus(code, message)) {
    final status? => status == 408 || status == 429 || status >= 500,
    null => false,
  },
  _ => false,
};

/// The HTTP status behind a [PostgrestException] that came from a gateway
/// rather than from Postgres, or null for a real database answer.
///
/// `code` is a five-character SQLSTATE for real answers - 42501 is RLS, not a
/// 5xx - and a status only when PostgREST itself answered. Cloudflare's 520
/// arrives as the plain-text body `error code: 520`, with no code at all.
int? _gatewayStatus(String? code, String message) {
  final status = int.tryParse(code ?? '');
  if (status != null) return status < 600 ? status : null;
  final match = RegExp(r'^error code: (\d{3})$').firstMatch(message.trim());
  return match == null ? null : int.parse(match.group(1)!);
}

/// A transient failure that stopped being transient: the caller retried and
/// it stayed down. A type of its own so it is not mistaken for the noise it is
/// made of - [isTransientNetworkError] does not match it, so it survives the
/// `beforeSend` filter - and so Sentry groups outages apart from one-off blips.
class PersistentOutage implements Exception {
  const PersistentOutage(this.cause);

  final Object cause;

  @override
  String toString() => 'PersistentOutage: $cause';
}

/// Reports a failure the app deliberately recovers from, without changing any
/// control flow.
///
/// Use it wherever a `catch` would otherwise be empty **and the failure has
/// consequences a user or a developer would want to know about** - a stranded
/// room membership, a chat line that never reached the database, canonical
/// media left stale. Routing through [FlutterError] means these land in the
/// error console with the same framing as any other Flutter error, show up in
/// DevTools, and still print in release via `debugPrint`.
///
/// Deliberately *not* for expected outcomes. A 10 s duration probe timing out,
/// a polled JS eval firing before the iframe exists, a `Uri` decode hitting a
/// stray `%` - those are the documented normal path, and reporting them is the
/// noise that trains people to stop reading logs.
///
/// When `SENTRY_DSN` is configured these also reach Sentry, because Sentry
/// installs its own `FlutterError.onError` during init - nothing here needs to
/// know about it.
///
/// A transient network failure ([isTransientNetworkError]) becomes a [trace]
/// instead, unless [persistent] says the caller has already watched it fail
/// repeatedly and an outage that long is itself worth knowing about.
void reportNonFatal(
  Object error,
  StackTrace? stack, {
  required String during,
  bool persistent = false,
}) {
  if (!persistent && isTransientNetworkError(error)) {
    trace('network unavailable: $during', category: 'network', data: {'error': '$error'});
    return;
  }
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: persistent ? PersistentOutage(error) : error,
      stack: stack,
      library: 'synctogether',
      context: ErrorDescription(during),
    ),
  );
}

/// Records a step on a flow we expect to have to debug from a machine we do not
/// have - a Windows release build, say - so that whatever error eventually
/// arrives comes with the sequence that led to it attached.
///
/// Breadcrumbs are buffered and only transmitted alongside a captured event, so
/// a flow that succeeds costs nothing and sends nothing. That is the whole
/// reason to prefer these over [reportNonFatal] for routine steps: they are
/// free until something goes wrong. No-ops when reporting is not configured.
void trace(String message, {String? category, Map<String, dynamic>? data}) {
  if (kDebugMode) debugPrint('[$category] $message ${data ?? ''}');
  Sentry.addBreadcrumb(Breadcrumb(message: message, category: category, data: data));
}
