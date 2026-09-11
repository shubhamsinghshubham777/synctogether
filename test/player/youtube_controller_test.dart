import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/player/youtube/pt_youtube_controller.dart';

class FakeInAppWebViewController extends Fake implements InAppWebViewController {
  final Map<String, JavaScriptHandlerCallback> handlers = {};
  final List<String> executedJs = [];

  @override
  void addJavaScriptHandler({
    required String handlerName,
    required JavaScriptHandlerCallback callback,
  }) {
    handlers[handlerName] = callback;
  }

  @override
  Future<dynamic> evaluateJavascript({required String source, ContentWorld? contentWorld}) async {
    executedJs.add(source);
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PTYouTubeController', () {
    test('initializes with default values and attaches handlers', () async {
      final controller = PTYouTubeController('dQw4w9WgXcQ');
      final fakeWeb = FakeInAppWebViewController();

      controller.attach(fakeWeb);

      expect(fakeWeb.handlers.containsKey('ytReady'), isTrue);
      expect(fakeWeb.handlers.containsKey('ytState'), isTrue);
      expect(fakeWeb.handlers.containsKey('ytTick'), isTrue);
      expect(fakeWeb.handlers.containsKey('ytError'), isTrue);
      expect(fakeWeb.handlers.containsKey('ytAdState'), isTrue);

      expect(controller.isReady, isFalse);
      expect(controller.isAdPlaying, isFalse);
      expect(controller.playerState, equals(PTYtPlayerState.unknown));

      controller.dispose();
    });

    test('transitions to unstarted on ready if no state was provided', () async {
      final controller = PTYouTubeController('dQw4w9WgXcQ');
      final fakeWeb = FakeInAppWebViewController();
      controller.attach(fakeWeb);

      fakeWeb.handlers['ytReady']!([
        {'duration': 120, 'position': 0},
      ]);

      expect(controller.isReady, isTrue);
      expect(controller.playerState, equals(PTYtPlayerState.unstarted));
      expect(controller.duration, equals(const Duration(seconds: 120)));

      controller.dispose();
    });

    test('detects ad active and prevents duration/position corruption', () async {
      final controller = PTYouTubeController('dQw4w9WgXcQ');
      final fakeWeb = FakeInAppWebViewController();
      controller.attach(fakeWeb);

      // Normal video ready
      fakeWeb.handlers['ytReady']!([
        {'duration': 1800, 'position': 0, 'state': -1},
      ]);
      expect(controller.duration, equals(const Duration(seconds: 1800)));

      // Ad starts playing (e.g. 15 second bumper ad)
      fakeWeb.handlers['ytAdState']!([
        {'isAd': true},
      ]);
      expect(controller.isAdPlaying, isTrue);

      // Snapshot ticks with ad duration and position
      fakeWeb.handlers['ytTick']!([
        {'duration': 15, 'position': 3, 'isAd': true},
      ]);

      // Main video duration and position must NOT be corrupted by ad values
      expect(controller.duration, equals(const Duration(seconds: 1800)));
      expect(controller.position, equals(Duration.zero));

      // Seeking during ad should be deferred
      controller.seekTo(const Duration(seconds: 45));
      // ptSeek should not be sent while ad is playing
      expect(fakeWeb.executedJs.any((js) => js.contains('ptSeek')), isFalse);

      // Ad finishes
      fakeWeb.handlers['ytAdState']!([
        {'isAd': false},
      ]);
      expect(controller.isAdPlaying, isFalse);

      // Deferred seek is now executed
      expect(fakeWeb.executedJs.any((js) => js.contains('ptSeek(45.0)')), isTrue);

      controller.dispose();
    });

    test('debugToggleAdState toggles ad state, pauses/plays, and resists ticker clobber', () async {
      final controller = PTYouTubeController('dQw4w9WgXcQ');
      final fakeWeb = FakeInAppWebViewController();
      controller.attach(fakeWeb);

      expect(controller.isAdPlaying, isFalse);
      expect(controller.debugSimulatedAd, isFalse);

      // 1. Enable simulated ad
      controller.debugToggleAdState();
      expect(controller.isAdPlaying, isTrue);
      expect(controller.debugSimulatedAd, isTrue);
      expect(fakeWeb.executedJs.contains('ptPause()'), isTrue);

      // 2. Incoming ticker snapshot with isAd: false must not clobber simulated ad
      fakeWeb.handlers['ytTick']!([
        {'position': 10.0, 'duration': 100.0, 'state': 1, 'isAd': false},
      ]);
      expect(controller.isAdPlaying, isTrue);

      // 3. Disable simulated ad
      controller.debugToggleAdState();
      expect(controller.isAdPlaying, isFalse);
      expect(controller.debugSimulatedAd, isFalse);
      expect(fakeWeb.executedJs.contains('ptPlay()'), isTrue);

      controller.dispose();
    });

    test('receives ytCaptions and updates captionTracks and selectedCaptionTrack', () async {
      final controller = PTYouTubeController('dQw4w9WgXcQ');
      final fakeWeb = FakeInAppWebViewController();
      controller.attach(fakeWeb);

      expect(controller.captionTracks.length, equals(1));
      expect(controller.captionTracks.first.isOff, isTrue);

      fakeWeb.handlers['ytCaptions']!([
        {
          'tracks': [
            {'languageCode': 'en', 'displayName': 'English', 'kind': 'standard'},
            {'languageCode': 'hi', 'displayName': 'Hindi', 'kind': 'standard'},
          ],
          'active': {'languageCode': 'en'},
        },
      ]);

      expect(controller.captionTracks.length, equals(3));
      expect(controller.captionTracks[0].isOff, isTrue);
      expect(controller.captionTracks[1].languageCode, equals('en'));
      expect(controller.captionTracks[2].languageCode, equals('hi'));
      expect(controller.selectedCaptionTrack?.languageCode, equals('en'));

      // Set caption track to Hindi
      controller.setCaptionTrack(controller.captionTracks[2]);
      expect(controller.selectedCaptionTrack?.languageCode, equals('hi'));
      expect(
        fakeWeb.executedJs.any((js) => js.contains('ptSetCaption') && js.contains('hi')),
        isTrue,
      );

      // Turn off captions
      controller.setCaptionTrack(PTYouTubeCaptionTrack.off());
      expect(controller.selectedCaptionTrack?.isOff, isTrue);
      expect(fakeWeb.executedJs.any((js) => js.contains('ptSetCaption({})')), isTrue);

      controller.dispose();
    });

    test(
      'user explicit caption track selection is not clobbered by subsequent ytCaptions events',
      () async {
        final controller = PTYouTubeController('dQw4w9WgXcQ');
        final fakeWeb = FakeInAppWebViewController();
        controller.attach(fakeWeb);

        // Initial tracks received, default English
        fakeWeb.handlers['ytCaptions']!([
          {
            'tracks': [
              {'languageCode': 'en', 'displayName': 'English', 'kind': 'standard'},
              {'languageCode': 'ja', 'displayName': 'Japanese', 'kind': 'standard'},
            ],
            'active': {'languageCode': 'en'},
          },
        ]);
        expect(controller.selectedCaptionTrack?.languageCode, equals('en'));

        // User selects Japanese
        controller.setCaptionTrack(controller.captionTracks[2]);
        expect(controller.selectedCaptionTrack?.languageCode, equals('ja'));

        // Stale event arrives from YouTube with active: en (e.g. onApiChange / getOption quirk)
        fakeWeb.handlers['ytCaptions']!([
          {
            'tracks': [
              {'languageCode': 'en', 'displayName': 'English', 'kind': 'standard'},
              {'languageCode': 'ja', 'displayName': 'Japanese', 'kind': 'standard'},
            ],
            'active': {'languageCode': 'en'},
          },
        ]);

        // User selection must remain Japanese!
        expect(controller.selectedCaptionTrack?.languageCode, equals('ja'));

        controller.dispose();
      },
    );
  });
}
