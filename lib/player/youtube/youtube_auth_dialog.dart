import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:synctogether/auth/auth_service.dart';
import 'package:synctogether/auth/webview_runtime.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/loader.dart';
import 'package:synctogether/ui/pt_theme.dart';

class YouTubeAuthDialog extends StatefulWidget {
  const YouTubeAuthDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showGlassDialog<bool>(
      context: context,
      width: 640,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
      builder: (_) => const YouTubeAuthDialog(),
    );
  }

  @override
  State<YouTubeAuthDialog> createState() => _YouTubeAuthDialogState();
}

class _YouTubeAuthDialogState extends State<YouTubeAuthDialog> {
  bool _loading = true;
  bool _signedIn = false;
  bool _closing = false;
  bool _wasInAuthFlow = false;
  InAppWebViewController? _webViewController;

  /// Injected at document start across all frames.
  /// WKWebView (macOS) and WebView2 (Windows) advertise WebAuthn/Passkey support by default,
  /// but lack the system biometric sheet bridge in desktop embeds. This causes Google's
  /// passkey assertion (`navigator.credentials.get()`) to hang indefinitely on
  /// "Use your passkey to confirm that it's really you".
  ///
  /// By reporting `isUserVerifyingPlatformAuthenticatorAvailable: false` and rejecting
  /// `credentials.get()` with `NotSupportedError`, Google immediately recognizes that
  /// hardware passkeys are unavailable in this container and presents standard password / 2FA.
  static final _bypassPasskeyUserScript = UserScript(
    groupName: 'disable_webauthn_passkeys',
    source: '''
      (function() {
        try {
          if (window.PublicKeyCredential) {
            window.PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable = function() {
              return Promise.resolve(false);
            };
            if (typeof window.PublicKeyCredential.isConditionalMediationAvailable === 'function') {
              window.PublicKeyCredential.isConditionalMediationAvailable = function() {
                return Promise.resolve(false);
              };
            }
          }
          if (navigator.credentials) {
            navigator.credentials.get = function() {
              return Promise.reject(new DOMException("The operation is not supported.", "NotSupportedError"));
            };
            navigator.credentials.create = function() {
              return Promise.reject(new DOMException("The operation is not supported.", "NotSupportedError"));
            };
          }
        } catch(e) {}
      })();
    ''',
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    forMainFrameOnly: false,
  );

  /// Native desktop user agents tailored to each engine:
  /// - macOS: Native Safari desktop string for WebKit / WKWebView.
  /// - Windows: Native Edge/Chrome desktop string for WebView2 (Chromium).
  static String get _desktopUserAgent {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      return 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
          'AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/133.0.0.0 Safari/537.36 Edg/133.0.0.0';
    }
    return 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) '
        'Version/18.3 Safari/605.1.15';
  }

  Future<void> _clickTryAnotherWay() async {
    await _webViewController?.evaluateJavascript(
      source: '''
      (function() {
        const candidates = Array.from(document.querySelectorAll('button, a, div[role="button"], span[role="button"]'));
        for (const el of candidates) {
          const t = (el.innerText || el.textContent || '').trim().toLowerCase();
          if (t.includes('try another way') || t.includes('another way')) {
            el.click();
            return true;
          }
        }
        window.scrollBy({ top: 300, behavior: 'smooth' });
        return false;
      })();
    ''',
    );
  }

  Future<void> _checkAuthStatus(InAppWebViewController controller, WebUri? url) async {
    if (_closing || !mounted) return;
    final currentUrl = url ?? await controller.getUrl();
    if (currentUrl == null) return;

    final host = currentUrl.host.toLowerCase();
    final path = currentUrl.path.toLowerCase();

    final isYouTubeHost =
        host == 'www.youtube.com' || host == 'youtube.com' || host == 'm.youtube.com';
    final isSigningIn =
        path.contains('/signin') ||
        path.contains('/servicelogin') ||
        path.contains('/v3/signin') ||
        host.contains('accounts.google.com');

    if (isSigningIn) {
      _wasInAuthFlow = true;
    }

    if (isYouTubeHost && !isSigningIn) {
      bool authenticated = false;

      // 1. Check cookies directly from cookie store
      try {
        final cookies = await CookieManager.instance().getCookies(
          url: WebUri('https://www.youtube.com'),
        );
        authenticated = cookies.any(
          (c) => c.name == 'LOGIN_INFO' || c.name == 'SID' || c.name == 'SAPISID',
        );
      } catch (_) {}

      // 2. Fallback to DOM / JS session check
      if (!authenticated) {
        try {
          final jsCheck = await controller.evaluateJavascript(
            source: '''
            (function() {
              try {
                if (window.yt && window.yt.config_ && window.yt.config_.LOGGED_IN === true) return true;
                if (document.querySelector('#avatar-btn, button#avatar-btn, ytd-topbar-menu-button-renderer, .yt-spec-avatar-shape')) return true;
                if (document.cookie && (document.cookie.includes('LOGIN_INFO=') || document.cookie.includes('SID='))) return true;
              } catch(e) {}
              return false;
            })();
          ''',
          );
          if (jsCheck == true || jsCheck == 'true') {
            authenticated = true;
          }
        } catch (_) {}
      }

      // Only auto-close if user went through the login flow in this dialog session
      if (authenticated && mounted && !_closing && _wasInAuthFlow) {
        setState(() {
          _signedIn = true;
          _closing = true;
        });
        await Future.delayed(const Duration(milliseconds: 900));
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = AuthService.instance.user?.email;
    final hint = (email != null && email.isNotEmpty) ? '&Email=${Uri.encodeComponent(email)}' : '';
    final initialUrl = 'https://www.youtube.com/signin?next=%2F$hint';
    final dialogHeight = MediaQuery.sizeOf(context).height.clamp(640.0, 700.0);

    return SizedBox(
      height: dialogHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Symbols.subscriptions_rounded, color: Color(0xFFFF0033), size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'YouTube Account Sign-in',
                      style: PTText.screenTitle.copyWith(fontSize: 18),
                    ),
                    Text(
                      'Sign in to your Google account. If you have YouTube Premium, ad-free playback will automatically apply.',
                      style: PTText.caption.copyWith(color: PTColors.white(0.55)),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                color: PTColors.white(0.6),
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: PTColors.white(0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: PTColors.white(0.1)),
            ),
            child: Row(
              children: [
                const Icon(Symbols.info_rounded, size: 16, color: Color(0xFFC9B8FF)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tip: If prompted for a passkey or security key, click "Use Password / Another Way" below or "Try another way" on screen.',
                    style: PTText.finePrint.copyWith(color: PTColors.white(0.85), height: 1.3),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  InAppWebView(
                    initialUrlRequest: URLRequest(url: WebUri(initialUrl)),
                    initialUserScripts: UnmodifiableListView([_bypassPasskeyUserScript]),
                    initialSettings: InAppWebViewSettings(
                      userAgent: _desktopUserAgent,
                      transparentBackground: false,
                      mediaPlaybackRequiresUserGesture: false,
                      limitsNavigationsToAppBoundDomains: false,
                      javaScriptCanOpenWindowsAutomatically: true,
                      supportMultipleWindows: true,
                    ),
                    webViewEnvironment: PTWebView.environment,
                    onWebViewCreated: (c) => _webViewController = c,
                    onLoadStart: (_, _) {
                      if (mounted) setState(() => _loading = true);
                    },
                    onLoadStop: (controller, url) async {
                      if (mounted) setState(() => _loading = false);
                      // Reinforce passkey bypass and auto-scroll if passkey screen is showing
                      await controller.evaluateJavascript(
                        source: '''
                        (function() {
                          try {
                            if (window.PublicKeyCredential) {
                              window.PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable = function() {
                                return Promise.resolve(false);
                              };
                            }
                            if (document.body && document.body.innerText && document.body.innerText.includes("Use your passkey")) {
                              window.scrollBy({ top: 250, behavior: 'smooth' });
                            }
                          } catch(e) {}
                        })();
                      ''',
                      );
                      await _checkAuthStatus(controller, url);
                    },
                    onUpdateVisitedHistory: (controller, url, isReload) async {
                      await _checkAuthStatus(controller, url);
                    },
                  ),
                  if (_loading)
                    const Positioned.fill(
                      child: ColoredBox(
                        color: Color(0xCC0B0A14),
                        child: Center(child: PTLoader(size: 36)),
                      ),
                    ),
                  if (_signedIn)
                    Positioned.fill(
                      child: ColoredBox(
                        color: const Color(0xEE0B0A14),
                        child: Center(
                          child: Column(
                            mainAxisSize: .min,
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: const BoxDecoration(
                                  color: Color(0x2234D399),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Symbols.check_circle_rounded,
                                  color: Color(0xFF34D399),
                                  size: 36,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'YouTube Account Connected',
                                style: PTText.screenTitle.copyWith(fontSize: 18),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Account connected. Returning to SyncTogether...',
                                style: PTText.body.copyWith(color: PTColors.white(0.7)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              PTButton(
                label: 'Log Out / Clear Cookies',
                variant: .secondary,
                height: 38,
                expand: false,
                onPressed: () async {
                  await CookieManager.instance().deleteAllCookies();
                  _wasInAuthFlow = false;
                  _signedIn = false;
                  if (context.mounted) {
                    Navigator.of(context).pop(false);
                  }
                },
              ),
              const SizedBox(width: 8),
              PTButton(
                label: 'Use Password Instead',
                variant: .secondary,
                height: 38,
                expand: false,
                onPressed: _clickTryAnotherWay,
              ),
              const Spacer(),
              PTButton(
                label: 'Done',
                height: 38,
                expand: false,
                onPressed: () async {
                  bool hasAuth = false;
                  try {
                    final cookies = await CookieManager.instance().getCookies(
                      url: WebUri('https://www.youtube.com'),
                    );
                    hasAuth = cookies.any(
                      (c) => c.name == 'LOGIN_INFO' || c.name == 'SID' || c.name == 'SAPISID',
                    );
                  } catch (_) {}
                  if (context.mounted) {
                    Navigator.of(context).pop(hasAuth);
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
