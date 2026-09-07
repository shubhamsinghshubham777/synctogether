import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/auth/webview_runtime.dart';
import 'package:synctogether/player/youtube/pt_youtube_controller.dart';
import 'package:synctogether/player/youtube/pt_youtube_embed.dart';

void main() {
  group('PTYouTubeEmbed', () {
    tearDown(() {
      PTWebView.runtimeMissing = false;
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
