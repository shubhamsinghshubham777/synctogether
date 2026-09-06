import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:synctogether/analytics.dart';
import 'package:synctogether/diagnostics.dart';
import 'package:synctogether/env.dart';

/// Thin wrapper over Supabase auth. Session persistence and token refresh are
/// handled by supabase_flutter; this only exposes the state the app reacts to.
class AuthService {
  AuthService();
  AuthService._();
  static AuthService instance = AuthService._();

  SupabaseClient get _client => Supabase.instance.client;

  Session? get session => _client.auth.currentSession;
  User? get user => _client.auth.currentUser;
  bool get isSignedIn => session != null;
  bool get isGuest => user?.isAnonymous ?? false;

  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  final _failures = StreamController<String>.broadcast();

  /// Friendly copy for auth failures that happen with no button press to
  /// attach them to - in practice, the OAuth callback. The app shows these as
  /// a snack; nothing else has the context to.
  Stream<String> get failures => _failures.stream;

  StreamSubscription<AuthState>? _stateSub;
  bool _awaitingOAuthCallback = false;
  Timer? _oauthWindow;

  /// Gives the auth stream's *errors* somewhere to go. Call once at startup.
  ///
  /// supabase_flutter handles the `synctogether://auth-callback` deep link
  /// inside its own listener, so the code-for-session exchange runs nowhere
  /// near the sign-in button's try/catch. When it fails, `_handleDeeplink`
  /// hands the AuthException to gotrue's `notifyException`, which calls
  /// `addError` on this stream - and with no error handler attached that
  /// becomes an unhandled zone error: fatal in Sentry, and *nothing at all* on
  /// screen. The login page just sits there. That is how a TLS failure on one
  /// Windows box looked exactly like Google sign-in quietly doing nothing.
  void start() {
    _stateSub ??= _client.auth.onAuthStateChange.listen((state) {
      if (state.session != null) _endOAuthWindow();
      _trackAuthChange(state);
    }, onError: _onAuthStreamError);
  }

  String? _identifiedUserId;
  bool _wasAnonymous = false;

  String _providerFor(User user) {
    if (user.isAnonymous) return 'guest';
    final provider = user.appMetadata['provider'];
    if (provider is String && provider.isNotEmpty) return provider;
    return 'email';
  }

  void _trackAuthChange(AuthState state) {
    if (state.event == AuthChangeEvent.signedOut) {
      _identifiedUserId = null;
      _wasAnonymous = false;
      return;
    }
    final user = state.session?.user;
    if (user == null) return;
    final wasAnonymous = _wasAnonymous;
    final knownUser = _identifiedUserId;
    _wasAnonymous = user.isAnonymous;
    _identifiedUserId = user.id;
    Analytics.instance.identify(user.id, personProperties: {'is_guest': user.isAnonymous});
    switch (state.event) {
      case AuthChangeEvent.signedIn:
        if (knownUser == user.id) return;
        Analytics.instance.track('signed_in', {'method': _providerFor(user)});
      case AuthChangeEvent.userUpdated:
        if (wasAnonymous && !user.isAnonymous) Analytics.instance.track('guest_upgraded');
      default:
        return;
    }
  }

  void _onAuthStreamError(Object error, StackTrace stack) {
    // Token refreshes fail routinely on a flaky connection and recover by
    // themselves; a snack for each one, or a Sentry event, is the noise that
    // trains people to stop reading both. The same error while someone is
    // standing in front of a half-finished sign-in is the whole story, so only
    // that window gets promoted past a breadcrumb.
    if (!_awaitingOAuthCallback) {
      trace('auth stream error outside a sign-in', category: 'auth', data: {'error': '$error'});
      return;
    }
    _endOAuthWindow();
    reportNonFatal(error, stack, during: 'completing the OAuth callback');
    _failures.add(_friendly(error));
  }

  /// Never the raw exception - this lands in a snack bar. The detail that
  /// actually identifies the cause has already gone to Sentry.
  static String _friendly(Object error) => error is AuthRetryableFetchException
      ? "Couldn't reach the sign-in service - check your connection and try again."
      : "Couldn't finish signing you in - give it another try.";

  /// Marks the gap between handing off to the browser and the deep link coming
  /// back, which is the only way to tell a failed callback apart from a routine
  /// background refresh - the two arrive on the same stream, indistinguishable.
  ///
  /// The deadline matters: without it, someone who opens the browser and walks
  /// away leaves the window open forever, and the next unrelated refresh
  /// failure gets reported as their sign-in breaking.
  void _beginOAuthWindow() {
    _awaitingOAuthCallback = true;
    _oauthWindow?.cancel();
    _oauthWindow = Timer(const Duration(minutes: 5), () => _awaitingOAuthCallback = false);
  }

  void _endOAuthWindow() {
    _awaitingOAuthCallback = false;
    _oauthWindow?.cancel();
    _oauthWindow = null;
  }

  /// Native Sign in with Apple is supported on macOS and iOS.
  bool get isAppleSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static String get _authRedirectUrl => kDebugMode && Env.usingLocalStack
      ? 'http://localhost:3000/auth/desktop-callback'
      : 'https://synctogether.app/auth/desktop-callback';

  void _ensureConfigured() {
    if (Env.supabaseUrl.isEmpty) {
      throw const AuthException(
        'Backend service URL is not configured. Please build with SUPABASE_URL.',
      );
    }
  }

  /// Native Sign in with Apple on macOS and iOS via ASAuthorizationAppleIDButton /
  /// Apple ID Credential sheet.
  Future<void> signInWithApple() async {
    _ensureConfigured();
    final rawNonce = _client.auth.generateRawNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
      nonce: hashedNonce,
    );

    final idToken = credential.identityToken;
    if (idToken == null) {
      throw StateError('Apple did not return an identity token');
    }

    final res = await _client.auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
      nonce: rawNonce,
    );

    // Apple only returns name on first authorization. Update profile display name if provided.
    final givenName = credential.givenName;
    final familyName = credential.familyName;
    final fullName = [
      givenName,
      familyName,
    ].where((n) => n != null && n.trim().isNotEmpty).join(' ').trim();
    if (fullName.isNotEmpty && res.user != null) {
      try {
        await _client.from('profiles').update({'display_name': fullName}).eq('id', res.user!.id);
      } catch (e, s) {
        reportNonFatal(e, s, during: 'updating Apple sign-in profile name');
      }
    }
  }

  /// Upgrades a guest to an Apple account in place (same user id).
  Future<void> linkAppleIdentity() async {
    _ensureConfigured();
    final rawNonce = _client.auth.generateRawNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
      nonce: hashedNonce,
    );

    final idToken = credential.identityToken;
    if (idToken == null) {
      throw StateError('Apple did not return an identity token');
    }

    final res = await _client.auth.linkIdentityWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
      nonce: rawNonce,
    );

    final givenName = credential.givenName;
    final familyName = credential.familyName;
    final fullName = [
      givenName,
      familyName,
    ].where((n) => n != null && n.trim().isNotEmpty).join(' ').trim();
    if (fullName.isNotEmpty && res.user != null) {
      try {
        await _client.from('profiles').update({'display_name': fullName}).eq('id', res.user!.id);
      } catch (e, s) {
        reportNonFatal(e, s, during: 'updating Apple linked profile name');
      }
    }
  }

  /// Sends a 6-digit OTP code to the given email address.
  Future<void> sendEmailOtp(String email, {String? captchaToken}) async {
    _ensureConfigured();
    await _client.auth.signInWithOtp(
      email: email.trim(),
      emailRedirectTo: _authRedirectUrl,
      captchaToken: captchaToken,
    );
  }

  /// Verifies a 6-digit OTP token sent to an email address.
  Future<void> verifyEmailOtp({required String email, required String token}) async {
    _ensureConfigured();
    await _client.auth.verifyOTP(email: email.trim(), token: token.trim(), type: OtpType.email);
  }

  /// Browser OAuth + deep-link callback - the one flow that works on every
  /// platform (plan Phase 1). supabase_flutter handles the callback URI.
  Future<void> signInWithGoogle() => _startOAuth(
    () => _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: _authRedirectUrl,
      authScreenLaunchMode: LaunchMode.externalApplication,
    ),
  );

  /// Upgrades a guest to a Google account in place (same user id).
  Future<void> linkGoogleIdentity() => _startOAuth(
    () => _client.auth.linkIdentity(
      OAuthProvider.google,
      redirectTo: _authRedirectUrl,
      authScreenLaunchMode: LaunchMode.externalApplication,
    ),
  );

  Future<void> _startOAuth(Future<bool> Function() launch) async {
    _ensureConfigured();
    _beginOAuthWindow();
    try {
      // launchUrl reports failure by returning false rather than throwing, and
      // supabase_flutter passes that straight through - so a machine with no
      // registered browser fails silently unless we check.
      if (!await launch()) {
        throw StateError('The browser could not be opened for OAuth sign-in');
      }
    } catch (_) {
      _endOAuthWindow();
      rethrow;
    }
  }

  Future<void> signInAsGuest({String? captchaToken}) async {
    _ensureConfigured();
    await _client.auth.signInAnonymously(captchaToken: captchaToken);
  }

  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } on AuthException catch (e) {
      // A revoked/expired session still means "signed out" locally.
      trace('sign-out fell back to a local sign-out', category: 'auth', data: {'error': e.message});
      await _client.auth.signOut(scope: SignOutScope.local);
    }
  }

  Future<void> deleteAccount() async {
    await _client.rpc('delete_account');
    await _client.auth.signOut(scope: SignOutScope.local);
  }
}
