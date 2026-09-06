import 'package:flutter/foundation.dart';

class Env {
  Env._();

  // Compile-time environment defines passed via --dart-define or --dart-define-from-file.
  static const String _envSupabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _envSupabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  static const String _envSupabaseUrlLocal = String.fromEnvironment('SUPABASE_URL_LOCAL');
  static const String _envSupabasePublishableKeyLocal = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY_LOCAL',
  );
  static const String _envLivekitUrl = String.fromEnvironment('LIVEKIT_URL');
  static const String _envTurnstileSiteKey = String.fromEnvironment('TURNSTILE_SITE_KEY');
  static const String _envSentryDsn = String.fromEnvironment('SENTRY_DSN');
  static const String _envPosthogApiKey = String.fromEnvironment('POSTHOG_API_KEY');
  static const String _envPosthogHost = String.fromEnvironment('POSTHOG_HOST');

  /// Well-known local development defaults used when running locally in debug mode
  /// without explicit compile-time defines.
  static const String defaultLocalSupabaseUrl = 'http://127.0.0.1:54321';
  static const String defaultLocalSupabasePublishableKey =
      'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH';
  static const String defaultLocalTurnstileSiteKey = '1x00000000000000000000AA';

  // Testing overrides.
  @visibleForTesting
  static String? overrideSupabaseUrl;
  @visibleForTesting
  static String? overrideSupabasePublishableKey;
  @visibleForTesting
  static String? overrideSupabaseUrlLocal;
  @visibleForTesting
  static String? overrideSupabasePublishableKeyLocal;
  @visibleForTesting
  static String? overrideLivekitUrl;
  @visibleForTesting
  static String? overrideTurnstileSiteKey;
  @visibleForTesting
  static String? overrideSentryDsn;
  @visibleForTesting
  static String? overridePosthogApiKey;
  @visibleForTesting
  static String? overridePosthogHost;
  @visibleForTesting
  static bool? overrideReleaseMode;

  @visibleForTesting
  static void resetOverridesForTesting() {
    overrideSupabaseUrl = null;
    overrideSupabasePublishableKey = null;
    overrideSupabaseUrlLocal = null;
    overrideSupabasePublishableKeyLocal = null;
    overrideLivekitUrl = null;
    overrideTurnstileSiteKey = null;
    overrideSentryDsn = null;
    overridePosthogApiKey = null;
    overridePosthogHost = null;
    overrideReleaseMode = null;
  }

  static bool get _isDebug => overrideReleaseMode == true ? false : kDebugMode;

  /// Debug builds talk to the local Supabase stack when one is configured, so
  /// migrations, RPC changes and destructive testing never touch the project
  /// real users are on. Release builds always take the production values, and
  /// a debug build with no local stack configured falls back to them too.
  static String get supabaseUrl {
    final effectiveLocal = _local(overrideSupabaseUrlLocal ?? _envSupabaseUrlLocal);
    if (effectiveLocal != null) return effectiveLocal;

    final effectiveProd = overrideSupabaseUrl ?? _envSupabaseUrl;
    if (effectiveProd.isNotEmpty) return effectiveProd;

    return _isDebug ? defaultLocalSupabaseUrl : '';
  }

  static String get supabasePublishableKey {
    final effectiveLocal = _local(overrideSupabaseUrlLocal ?? _envSupabaseUrlLocal);
    if (effectiveLocal != null) {
      final key = overrideSupabasePublishableKeyLocal ?? _envSupabasePublishableKeyLocal;
      return key.isNotEmpty ? key : defaultLocalSupabasePublishableKey;
    }

    final effectiveProd = overrideSupabasePublishableKey ?? _envSupabasePublishableKey;
    if (effectiveProd.isNotEmpty) return effectiveProd;

    return _isDebug ? defaultLocalSupabasePublishableKey : '';
  }

  /// True when this build is pointed at a local stack rather than production -
  /// surfaced in the lobby so a debug session can never be mistaken for one.
  static bool get usingLocalStack {
    if (!_isDebug) return false;
    final localUrl = _local(overrideSupabaseUrlLocal ?? _envSupabaseUrlLocal);
    if (localUrl != null) return true;
    final prodUrl = overrideSupabaseUrl ?? _envSupabaseUrl;
    return prodUrl.isEmpty;
  }

  static String? _local(String value) {
    if (!_isDebug) return null;
    return value.isEmpty ? null : value;
  }

  /// Optional until LiveKit is configured; AV features are hidden without it.
  static String? get livekitUrl => _opt(overrideLivekitUrl ?? _envLivekitUrl);

  /// Optional; when set, guest sign-in requires a Turnstile captcha token
  /// (the server enforces it - [auth.captcha] in supabase/config.toml).
  static String? get turnstileSiteKey {
    final override = overrideTurnstileSiteKey;
    if (override != null) return override.isEmpty ? null : override;
    if (_envTurnstileSiteKey.isNotEmpty) return _envTurnstileSiteKey;
    return usingLocalStack ? defaultLocalTurnstileSiteKey : null;
  }

  /// Optional; error reporting is disabled entirely when absent, which is the
  /// normal state for local development. A Sentry DSN is a public write-only
  /// key, so shipping it in the bundle is fine - unlike a server secret.
  static String? get sentryDsn => _opt(overrideSentryDsn ?? _envSentryDsn);

  static String? get posthogApiKey => _opt(overridePosthogApiKey ?? _envPosthogApiKey);

  static String? get posthogHost {
    final val = overridePosthogHost ?? _envPosthogHost;
    return val.isEmpty ? null : val;
  }

  static String? _opt(String value) => value.isEmpty ? null : value;
}
