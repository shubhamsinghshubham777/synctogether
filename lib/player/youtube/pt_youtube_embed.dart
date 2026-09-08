import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:synctogether/auth/webview_runtime.dart';
import 'package:synctogether/diagnostics.dart';
import 'package:synctogether/platform.dart';
import 'package:synctogether/player/youtube/pt_youtube_controller.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/pt_theme.dart';
import 'package:url_launcher/url_launcher.dart';

class PTYouTubeEmbed extends StatefulWidget {
  const PTYouTubeEmbed({super.key, required this.controller});

  final PTYouTubeController controller;

  @override
  State<PTYouTubeEmbed> createState() => _PTYouTubeEmbedState();
}

class _PTYouTubeEmbedState extends State<PTYouTubeEmbed> {
  Uri? _url;
  String? _initialHtml;

  @override
  void initState() {
    super.initState();
    _bind(widget.controller);
  }

  @override
  void didUpdateWidget(PTYouTubeEmbed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      _bind(widget.controller);
    }
  }

  void _bind(PTYouTubeController controller) {
    _url = controller.pageUrl;
    _initialHtml = controller.initialHtml;
    controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    final url = widget.controller.pageUrl;
    final html = widget.controller.initialHtml;
    if ((url != _url || html != _initialHtml) && mounted) {
      setState(() {
        _url = url;
        _initialHtml = html;
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (PTWebView.runtimeMissing) return const _MissingRuntime();

    final html = _initialHtml;
    if (html != null) {
      // macOS Store build: serve the embed page as inline data so we don't
      // need to bind an HttpServer (which requires network.server entitlement).
      return Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: InAppWebView(
            initialData: InAppWebViewInitialData(
              data: html,
              baseUrl: WebUri(PTYouTubeController.inlineDataBaseUrl),
              encoding: 'utf-8',
              mimeType: 'text/html',
            ),
            initialSettings: InAppWebViewSettings(
              transparentBackground: true,
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
              disableContextMenu: true,
            ),
            webViewEnvironment: PTWebView.environment,
            onWebViewCreated: widget.controller.attach,
            onConsoleMessage: (_, msg) => trace(
              msg.message,
              category: 'youtube.console',
              data: {'level': msg.messageLevel.toString()},
            ),
            onReceivedError: (_, request, error) => trace(
              'load error: ${error.description}',
              category: 'youtube.webview',
              data: {'url': '${request.url}', 'type': '${error.type}'},
            ),
            onReceivedHttpError: (_, request, response) => trace(
              'http error: ${response.statusCode}',
              category: 'youtube.webview',
              data: {'url': '${request.url}'},
            ),
            onLoadStop: (_, url) =>
                trace('load finished', category: 'youtube.webview', data: {'url': '$url'}),
          ),
        ),
      );
    }

    final url = _url;
    if (url == null) return const SizedBox.shrink();
    return Center(
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri.uri(url)),
          initialSettings: InAppWebViewSettings(
            transparentBackground: true,
            mediaPlaybackRequiresUserGesture: false,
            allowsInlineMediaPlayback: true,
            disableContextMenu: true,
          ),
          webViewEnvironment: PTWebView.environment,
          onWebViewCreated: widget.controller.attach,
          onConsoleMessage: (_, msg) => trace(
            msg.message,
            category: 'youtube.console',
            data: {'level': msg.messageLevel.toString()},
          ),
          onReceivedError: (_, request, error) => trace(
            'load error: ${error.description}',
            category: 'youtube.webview',
            data: {'url': '${request.url}', 'type': '${error.type}'},
          ),
          onReceivedHttpError: (_, request, response) => trace(
            'http error: ${response.statusCode}',
            category: 'youtube.webview',
            data: {'url': '${request.url}'},
          ),
          onLoadStop: (_, url) =>
              trace('load finished', category: 'youtube.webview', data: {'url': '$url'}),
        ),
      ),
    );
  }
}

class _MissingRuntime extends StatelessWidget {
  const _MissingRuntime();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: .min,
          spacing: 12,
          children: [
            Text(
              isStoreBuild
                  ? 'Your PC is missing or needs a repair of the Microsoft Edge WebView2 Runtime, which YouTube videos need.'
                  : 'Your PC is missing a Windows component YouTube videos need. '
                        'Reinstalling SyncTogether will add it, or download the runtime below.',
              textAlign: .center,
              style: PTText.body.copyWith(color: PTColors.white(0.6)),
            ),
            Text(
              'Error webview2-missing',
              style: PTText.mono.copyWith(fontSize: 11.5, color: PTColors.white(0.4)),
            ),
            const SizedBox(height: 4),
            PTButton(
              label: 'Download WebView2 Runtime',
              icon: Icons.download_rounded,
              expand: false,
              height: 42,
              onPressed: () =>
                  launchUrl(PTWebView.downloadUri, mode: LaunchMode.externalApplication),
            ),
            if (isStoreBuild)
              Text(
                'Already installed? In Windows Settings > Apps > Installed apps, choose Microsoft Edge WebView2 Runtime, click … and choose Modify > Repair.',
                textAlign: .center,
                style: PTText.caption.copyWith(color: PTColors.white(0.4), fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }
}
