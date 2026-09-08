import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:synctogether/auth/webview_runtime.dart';
import 'package:synctogether/diagnostics.dart';
import 'package:synctogether/env.dart';
import 'package:synctogether/platform.dart';
import 'package:synctogether/player/youtube/pt_youtube_controller.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/pt_theme.dart';
import 'package:url_launcher/url_launcher.dart';

/// Runs a Cloudflare Turnstile challenge in a webview and returns the
/// captcha token (null on cancel/failure). The page is served from a throwaway
/// loopback server so its origin really is `localhost` - that hostname must
/// stay in the Turnstile widget allow-list.
Future<String?> showTurnstileDialog(BuildContext context) {
  return showGlassDialog<String>(
    context: context,
    width: 380,
    builder: (_) => const _TurnstileBody(),
  );
}

class _TurnstileBody extends StatefulWidget {
  const _TurnstileBody();

  @override
  State<_TurnstileBody> createState() => _TurnstileBodyState();
}

/// How long the challenge gets before we call it stuck. Turnstile normally
/// resolves in well under a second; this only has to be longer than a slow
/// cold WebView2 start.
const _kChallengeTimeout = Duration(seconds: 20);

class _TurnstileBodyState extends State<_TurnstileBody> {
  bool _failed = false;
  String? _errorCode;
  HttpServer? _server;
  Uri? _pageUrl;

  /// Non-null on macOS Store builds where no loopback server is used.
  /// The InAppWebView is loaded via [InAppWebViewInitialData] with
  /// [PTYouTubeController.inlineDataBaseUrl] as the document origin.
  String? _initialHtml;

  Timer? _timeout;
  bool _pageRequested = false;
  bool _webViewCreated = false;

  @override
  void initState() {
    super.initState();
    // Known before anything is drawn, and no amount of waiting or retrying
    // changes it - so say so immediately instead of after the full deadline.
    if (PTWebView.runtimeMissing) {
      _failed = true;
      _errorCode = 'webview2-missing';
      return;
    }
    _serve();
  }

  /// The silent-failure case, and the reason this timer exists: if the webview
  /// never renders at all, nothing throws and no error-callback fires, so the
  /// dialog just sits there looking patient. Without an explicit deadline that
  /// state produces no telemetry whatsoever - which is exactly the hole we
  /// fell into on Windows.
  void _armTimeout() {
    _timeout?.cancel();
    _timeout = Timer(_kChallengeTimeout, () {
      if (!mounted || _errorCode != null) return;
      reportNonFatal(
        StateError(
          'Turnstile produced neither a token nor an error in '
          '${_kChallengeTimeout.inSeconds}s '
          '(webview created: $_webViewCreated, page requested: $_pageRequested)',
        ),
        StackTrace.current,
        during: 'running the Turnstile challenge',
      );
      setState(() {
        _failed = true;
        // Three distinct causes, and the first two were previously
        // indistinguishable: a webview the platform refused to build at all,
        // one that built but never navigated, and one that loaded the page and
        // then heard nothing back from Cloudflare.
        _errorCode = !_webViewCreated
            ? 'webview-not-created'
            : _pageRequested
            ? 'no-response'
            : 'page-never-requested';
      });
    });
  }

  /// Hands the challenge page a real `http://localhost` origin, either via a
  /// loopback [HttpServer] (all builds except macOS Store) or via
  /// [InAppWebViewInitialData] with a matching [baseUrl] (macOS Store builds
  /// where the App Sandbox forbids binding a listening socket without the
  /// `network.server` entitlement that Apple rejects).
  ///
  /// On non-macOS-Store targets the loopback server is still required because
  /// Windows WebView2 drops `InAppWebViewInitialData.baseUrl` on the floor —
  /// the backend routes initial data through `NavigateToString`, which takes no
  /// baseUrl parameter and always yields an opaque origin, making Turnstile
  /// refuse to issue a token.
  Future<void> _serve() async {
    if (!useLoopbackServer) {
      // macOS Store build: serve the challenge page as inline data.
      // WKWebView on macOS correctly honours InAppWebViewInitialData.baseUrl,
      // so `localhost` is the document origin and matches the Turnstile allow-list.
      _armTimeout();
      setState(() => _initialHtml = _html);
      return;
    }
    try {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      if (!mounted) {
        await server.close(force: true);
        return;
      }
      _server = server;
      server.listen((request) {
        // Distinguishes "the webview never reached us" from "it loaded the page
        // and Turnstile then failed" - the two have completely different causes
        // and look identical from the outside.
        _pageRequested = true;
        trace('challenge page requested', category: 'turnstile', data: {'path': request.uri.path});
        request.response
          ..headers.contentType = ContentType.html
          ..write(_html);
        request.response.close();
      });
      // `localhost` rather than 127.0.0.1: Turnstile matches on hostname, and
      // the literal IP is not what the widget is registered for. Webviews
      // resolve it dual-stack and fall back to the IPv4 loopback we bound.
      final url = Uri.parse('http://localhost:${server.port}/');
      trace('serving challenge', category: 'turnstile', data: {'url': '$url'});
      _armTimeout();
      setState(() => _pageUrl = url);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'starting the Turnstile loopback server');
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _timeout?.cancel();
    _server?.close(force: true);
    super.dispose();
  }

  String get _html =>
      '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<script src="https://challenges.cloudflare.com/turnstile/v0/api.js?onload=onloadTurnstile" async defer></script>
<style>
  body { margin: 0; background: transparent; display: flex; justify-content: center; }
</style>
</head>
<body>
<div id="cf"></div>
<script>
function onloadTurnstile() {
  turnstile.render('#cf', {
    sitekey: '${Env.turnstileSiteKey}',
    theme: 'dark',
    callback: function (token) {
      window.flutter_inappwebview.callHandler('turnstileToken', token);
    },
    'error-callback': function (e) {
      window.flutter_inappwebview.callHandler('turnstileError', String(e));
      return true;
    },
  });
}
</script>
</body>
</html>
''';

  /// "Try again" is the right advice for a challenge that timed out, and the
  /// wrong advice for a PC that is missing the component this renders in -
  /// retrying that forever is precisely what people did.
  String get _failureMessage {
    if (_errorCode == 'webview2-missing') {
      return isStoreBuild
          ? 'Your PC is missing or needs a repair of the Microsoft Edge WebView2 Runtime, which this verification needs.'
          : 'Your PC is missing a Windows component this check needs. '
                'Reinstalling SyncTogether will add it, or download the runtime below.';
    }
    return "Hmm, the check didn't load. Close this and try again.";
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      spacing: 14,
      children: [
        Text('Quick check', style: PTText.cardHeading),
        Text(
          _failed ? _failureMessage : "Just making sure you're human - takes a second.",
          style: PTText.body.copyWith(fontSize: 13.5, color: PTColors.white(0.6)),
        ),
        // Shown only on failure, and deliberately not dressed up as friendly
        // copy: it exists so a bug report can quote it.
        if (_errorCode != null)
          Text(
            'Error $_errorCode',
            style: PTText.mono.copyWith(fontSize: 11.5, color: PTColors.white(0.4)),
          ),
        if (_failed && _errorCode == 'webview2-missing') ...[
          PTButton(
            label: 'Download WebView2 Runtime',
            icon: Icons.download_rounded,
            height: 44,
            onPressed: () => launchUrl(PTWebView.downloadUri, mode: LaunchMode.externalApplication),
          ),
          if (isStoreBuild)
            Text(
              'Already installed? In Windows Settings > Apps > Installed apps, choose Microsoft Edge WebView2 Runtime, click … and choose Modify > Repair.',
              style: PTText.caption.copyWith(color: PTColors.white(0.5), fontSize: 12),
            ),
          PTButton(
            label: 'Close',
            variant: .secondary,
            height: 40,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ] else ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(height: 80, child: _buildWebView(context)),
          ),
          if (_failed)
            PTButton(
              label: 'Close',
              variant: .secondary,
              height: 40,
              onPressed: () => Navigator.of(context).pop(),
            ),
        ],
      ],
    );
  }

  Widget _buildWebView(BuildContext context) {
    final html = _initialHtml;
    final url = _pageUrl;

    // Neither path is ready yet — _serve() hasn't completed its setState call.
    if (html == null && url == null) return const SizedBox.shrink();

    return InAppWebView(
      // macOS Store builds use inline data so no HttpServer is needed.
      // All other builds use the loopback URL.
      initialData: html != null
          ? InAppWebViewInitialData(
              data: html,
              baseUrl: WebUri(PTYouTubeController.inlineDataBaseUrl),
              encoding: 'utf-8',
              mimeType: 'text/html',
            )
          : null,
      initialUrlRequest: url != null ? URLRequest(url: WebUri.uri(url)) : null,
      initialSettings: InAppWebViewSettings(transparentBackground: true),
      // Null off Windows, where the plugin's own default is right.
      webViewEnvironment: PTWebView.environment,
      // Turnstile reports its own diagnostics to the JS console
      // (an unlisted hostname says so there in as many words),
      // and that output is otherwise invisible in a release build.
      onConsoleMessage: (_, msg) => trace(
        msg.message,
        category: 'turnstile.console',
        data: {'level': msg.messageLevel.toString()},
      ),
      onReceivedError: (_, request, error) => trace(
        'load error: ${error.description}',
        category: 'turnstile.webview',
        data: {'url': '${request.url}', 'type': '${error.type}'},
      ),
      onReceivedHttpError: (_, request, response) => trace(
        'http error: ${response.statusCode}',
        category: 'turnstile.webview',
        data: {'url': '${request.url}'},
      ),
      onLoadStop: (_, url) =>
          trace('load finished', category: 'turnstile.webview', data: {'url': '$url'}),
      onWebViewCreated: (controller) {
        // Never fires if the platform could not build the webview
        // - which is the failure this dialog could not previously
        // distinguish from Cloudflare never answering.
        _webViewCreated = true;
        controller.addJavaScriptHandler(
          handlerName: 'turnstileToken',
          callback: (args) {
            final token = args.isNotEmpty ? args.first as String : null;
            if (mounted && token != null) {
              _timeout?.cancel();
              Navigator.of(context).pop(token);
            }
          },
        );
        controller.addJavaScriptHandler(
          handlerName: 'turnstileError',
          callback: (args) {
            // Cloudflare's code is the single most diagnostic
            // thing available here - 110200 is an unlisted
            // hostname, 300xxx/600xxx are render-side failures -
            // so it goes to Sentry *and* on screen, because the
            // person hitting this is usually not the person
            // reading the dashboard.
            final code = args.isNotEmpty ? '${args.first}' : 'unknown';
            _timeout?.cancel();
            reportNonFatal(
              StateError('Turnstile error-callback: $code'),
              StackTrace.current,
              during: 'running the Turnstile challenge',
            );
            if (mounted) {
              setState(() {
                _failed = true;
                _errorCode = code;
              });
            }
          },
        );
      },
    );
  }
}
