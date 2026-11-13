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
  static const String _envSiteUrl = String.fromEnvironment('SITE_URL');
  static const String _envSupportEmail = String.fromEnvironment('SUPPORT_EMAIL');
  static const String _envFirebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const String _envFirebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const String _envFirebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const String _envFirebaseSenderId = String.fromEnvironment('FIREBASE_SENDER_ID');

  /// Well-known local development defaults used when running locally in debug mode
  /// without explicit compile-time defines.
  /// `--dart-define=STREAM_PROXY=false` switches the loopback range proxy off
  /// and mpv opens the shared-media URL directly, as it did before the proxy
  /// existed. On by default; there is no server-side switch because the proxy
  /// is a client delivery detail.
  static const bool _envStreamProxy = bool.fromEnvironment('STREAM_PROXY', defaultValue: true);

  static const String defaultLocalSupabaseUrl = 'http://127.0.0.1:54321';
  static const String defaultLocalSupabasePublishableKey =
      'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH';
  static const String defaultLocalTurnstileSiteKey = '1x00000000000000000000AA';
  static const String defaultLocalSiteUrl = 'http://localhost:3000';

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
  static String? overrideSiteUrl;
  @visibleForTesting
  static String? overrideSupportEmail;
  @visibleForTesting
  static Map<String, String>? overrideFirebaseOptions;
  @visibleForTesting
  static bool? overrideReleaseMode;
  @visibleForTesting
  static bool? overrideStreamProxy;

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
    overrideSiteUrl = null;
    overrideSupportEmail = null;
    overrideFirebaseOptions = null;
    overrideReleaseMode = null;
    overrideStreamProxy = null;
  }

  static bool get streamProxyEnabled => overrideStreamProxy ?? _envStreamProxy;

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

  /// Origin of the web portal this build links to: invites, recaps, profile
  /// pages, Terms/Privacy and the Google sign-in bridge (`/auth/desktop-callback`).
  ///
  /// There is deliberately no built-in production value: a build only ever talks
  /// to the site it was given with `--dart-define=SITE_URL=https://...`, so a
  /// fork can never send invites, sign-ins or legal links through somebody
  /// else's site. Unset (outside a debug run on the local stack) it is null and
  /// every feature that needs a site hides itself. Never ends in a slash.
  static String? get siteUrl {
    // A debug run on the local stack always uses the local website, so its
    // invites and sign-in bridge never leave the machine even when SITE_URL is
    // also set for release builds.
    if (usingLocalStack) return _localSiteUrl();
    final explicit = (overrideSiteUrl ?? _envSiteUrl).trim();
    return explicit.isEmpty ? null : explicit.replaceFirst(RegExp(r'/+$'), '');
  }

  /// The local website. When the local backend is addressed by a LAN host (a
  /// physical phone run via `scripts/run-ios.sh`), the site lives on that same
  /// machine, so use its host: `localhost` on a phone is the phone itself, which
  /// is what stranded the Google sign-in bridge on "localhost not found".
  static String _localSiteUrl() {
    final host = Uri.tryParse(supabaseUrl)?.host ?? '';
    const loopback = {'', 'localhost', '127.0.0.1', '10.0.2.2'};
    return loopback.contains(host) ? defaultLocalSiteUrl : 'http://$host:3000';
  }

  /// Host of [siteUrl], for recognising our own invite links on the clipboard.
  static String? get siteHost {
    final url = siteUrl;
    return url == null ? null : _opt(Uri.tryParse(url)?.host ?? '');
  }

  /// A page on the web portal, or null when this build has none.
  static Uri? sitePage(String path) {
    final url = siteUrl;
    return url == null ? null : Uri.tryParse('$url/$path');
  }

  /// Where reports and appeals are sent. Null (unset) hides the "email us" copy.
  static String? get supportEmail => _opt((overrideSupportEmail ?? _envSupportEmail).trim());

  /// Firebase options for Android push (FCM), or null unless all four are set -
  /// half a configuration is no configuration, and without it the Android build
  /// simply offers no push. There is deliberately no built-in project: a fork
  /// must never send its users' push tokens to someone else's Firebase.
  static Map<String, String>? get firebaseOptions {
    final override = overrideFirebaseOptions;
    if (override != null) return override;
    final options = {
      'apiKey': _envFirebaseApiKey.trim(),
      'appId': _envFirebaseAppId.trim(),
      'projectId': _envFirebaseProjectId.trim(),
      'senderId': _envFirebaseSenderId.trim(),
    };
    return options.values.any((v) => v.isEmpty) ? null : options;
  }

  static String? _opt(String value) => value.isEmpty ? null : value;
}
