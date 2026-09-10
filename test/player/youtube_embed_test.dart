import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/auth/webview_runtime.dart';
import 'package:synctogether/player/youtube/pt_youtube_controller.dart';
import 'package:synctogether/player/youtube/pt_youtube_embed.dart';

void main() {
  group('PTYouTubeEmbed', () {
    tearDown(() {
      PTWebView.runtimeMissing = false;
    });

    test('handleNavigationPolicy allows internal browser schemes like about:blank', () async {
      expect(
        await PTYouTubeEmbed.handleNavigationPolicy(Uri.parse('about:blank')),
        equals(NavigationActionPolicy.ALLOW),
      );
      expect(
        await PTYouTubeEmbed.handleNavigationPolicy(Uri.parse('data:text/html;base64,abc')),
        equals(NavigationActionPolicy.ALLOW),
      );
      expect(
        await PTYouTubeEmbed.handleNavigationPolicy(Uri.parse('blob:http://localhost/uuid')),
        equals(NavigationActionPolicy.ALLOW),
      );
      expect(
        await PTYouTubeEmbed.handleNavigationPolicy(Uri.parse('javascript:void(0)')),
        equals(NavigationActionPolicy.ALLOW),
      );
    });

    test(
      'handleNavigationPolicy cancels non-http/https schemes without launching externally',
      () async {
        expect(
          await PTYouTubeEmbed.handleNavigationPolicy(Uri.parse('unknown-scheme://foo')),
          equals(NavigationActionPolicy.CANCEL),
        );
      },
    );

    test('handleNavigationPolicy allows loopback and internal youtube subresources', () async {
      expect(
        await PTYouTubeEmbed.handleNavigationPolicy(Uri.parse('http://localhost:54321/')),
        equals(NavigationActionPolicy.ALLOW),
      );
      expect(
        await PTYouTubeEmbed.handleNavigationPolicy(
          Uri.parse('https://www.youtube.com/embed/dQw4w9WgXcQ'),
        ),
        equals(NavigationActionPolicy.ALLOW),
      );
      expect(
        await PTYouTubeEmbed.handleNavigationPolicy(
          Uri.parse('https://rr1---sn.googlevideo.com/videoplayback'),
        ),
        equals(NavigationActionPolicy.ALLOW),
      );
    });

    testWidgets('displays download button and error message when runtime is missing', (
      tester,
    ) async {
      PTWebView.runtimeMissing = true;
      final controller = PTYouTubeController('test-video-id');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PTYouTubeEmbed(controller: controller)),
        ),
      );
      // Wait for server to bind
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Error webview2-missing'), findsOneWidget);
      expect(find.text('Download WebView2 Runtime'), findsOneWidget);

      controller.dispose();
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
