import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:synctogether/rooms/widgets/room_control_bar.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/inputs.dart';

void main() {
  group('RoomControlBar AV Controls (TDD)', () {
    testWidgets('mic and cam buttons are live with standard tooltips', (tester) async {
      bool? micToggledValue;
      bool? camToggledValue;

      final actions = RoomControlBarActions(
        onPlayPause: () {},
        onSeek: (_) {},
        onSkip: (_) {},
        onMicToggle: (v) => micToggledValue = v,
        onCamToggle: (v) => camToggledValue = v,
        onAudioTracks: () {},
        onSubtitles: () {},
        onSwitchSource: () {},
        onOpenFile: () {},
        onVolume: (_) {},
        onToggleMute: () {},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomControlBar(
              playing: false,
              position: Duration.zero,
              duration: const Duration(minutes: 10),
              volume: 1.0,
              micOn: false,
              camOn: false,
              avAvailable: true,
              camAvailable: true,
              actions: actions,
            ),
          ),
        ),
      );

      final micFinder = find.widgetWithIcon(PTIconButton, Symbols.mic_rounded);
      final camFinder = find.widgetWithIcon(PTIconButton, Symbols.videocam_rounded);

      expect(micFinder, findsOneWidget);
      expect(camFinder, findsOneWidget);

      final micButton = tester.widget<PTIconButton>(micFinder);
      final camButton = tester.widget<PTIconButton>(camFinder);

      expect(micButton.onPressed, isNotNull);
      expect(camButton.onPressed, isNotNull);

      expect(
        find.byWidgetPredicate((w) => w is Tooltip && w.message == 'Mic on (D)'),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate((w) => w is Tooltip && w.message == 'Camera on (E)'),
        findsOneWidget,
      );

      await tester.tap(micFinder);
      await tester.pump();
      expect(micToggledValue, isTrue);

      await tester.tap(camFinder);
      await tester.pump();
      expect(camToggledValue, isTrue);
    });

    testWidgets('shows Mute mic and Camera off when micOn and camOn are true', (tester) async {
      final actions = RoomControlBarActions(
        onPlayPause: () {},
        onSeek: (_) {},
        onSkip: (_) {},
        onMicToggle: (_) {},
        onCamToggle: (_) {},
        onAudioTracks: () {},
        onSubtitles: () {},
        onSwitchSource: () {},
        onOpenFile: () {},
        onVolume: (_) {},
        onToggleMute: () {},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomControlBar(
              playing: false,
              position: Duration.zero,
              duration: const Duration(minutes: 10),
              volume: 1.0,
              micOn: true,
              camOn: true,
              avAvailable: true,
              camAvailable: true,
              actions: actions,
            ),
          ),
        ),
      );

      expect(
        find.byWidgetPredicate((w) => w is Tooltip && w.message == 'Mute mic (D)'),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate((w) => w is Tooltip && w.message == 'Camera off (E)'),
        findsOneWidget,
      );
    });

    testWidgets('hides mic and cam buttons entirely when avAvailable is false', (tester) async {
      final actions = RoomControlBarActions(
        onPlayPause: () {},
        onSeek: (_) {},
        onSkip: (_) {},
        onMicToggle: (_) {},
        onCamToggle: (_) {},
        onAudioTracks: () {},
        onSubtitles: () {},
        onSwitchSource: () {},
        onOpenFile: () {},
        onVolume: (_) {},
        onToggleMute: () {},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomControlBar(
              playing: false,
              position: Duration.zero,
              duration: const Duration(minutes: 10),
              volume: 1.0,
              micOn: false,
              camOn: false,
              avAvailable: false,
              camAvailable: true,
              actions: actions,
            ),
          ),
        ),
      );

      expect(find.widgetWithIcon(PTIconButton, Symbols.mic_rounded), findsNothing);
      expect(find.widgetWithIcon(PTIconButton, Symbols.videocam_rounded), findsNothing);
    });

    testWidgets(
      'shows dropdown carets when device select callbacks are provided and triggers on tap',
      (tester) async {
        BuildContext? micContext;
        BuildContext? camContext;
        BuildContext? audioOutputContext;

        final actions = RoomControlBarActions(
          onPlayPause: () {},
          onSeek: (_) {},
          onSkip: (_) {},
          onMicToggle: (_) {},
          onCamToggle: (_) {},
          onMicDeviceSelect: (ctx) => micContext = ctx,
          onCamDeviceSelect: (ctx) => camContext = ctx,
          onAudioOutputSelect: (ctx) => audioOutputContext = ctx,
          onAudioTracks: () {},
          onSubtitles: () {},
          onSwitchSource: () {},
          onOpenFile: () {},
          onVolume: (_) {},
          onToggleMute: () {},
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RoomControlBar(
                playing: false,
                position: Duration.zero,
                duration: const Duration(minutes: 10),
                volume: 1.0,
                micOn: false,
                camOn: false,
                avAvailable: true,
                camAvailable: true,
                actions: actions,
              ),
            ),
          ),
        );

        expect(find.byTooltip('Select microphone'), findsOneWidget);
        expect(find.byTooltip('Select camera'), findsOneWidget);
        expect(find.byTooltip('Select audio output'), findsOneWidget);

        await tester.tap(find.byTooltip('Select microphone'));
        await tester.pump();
        expect(micContext, isNotNull);

        await tester.tap(find.byTooltip('Select camera'));
        await tester.pump();
        expect(camContext, isNotNull);

        await tester.tap(find.byTooltip('Select audio output'));
        await tester.pump();
        expect(audioOutputContext, isNotNull);
      },
    );

    testWidgets('does not show dropdown carets when device select callbacks are null', (
      tester,
    ) async {
      final actions = RoomControlBarActions(
        onPlayPause: () {},
        onSeek: (_) {},
        onSkip: (_) {},
        onMicToggle: (_) {},
        onCamToggle: (_) {},
        onMicDeviceSelect: null,
        onCamDeviceSelect: null,
        onAudioOutputSelect: null,
        onAudioTracks: () {},
        onSubtitles: () {},
        onSwitchSource: () {},
        onOpenFile: () {},
        onVolume: (_) {},
        onToggleMute: () {},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomControlBar(
              playing: false,
              position: Duration.zero,
              duration: const Duration(minutes: 10),
              volume: 1.0,
              micOn: false,
              camOn: false,
              avAvailable: true,
              camAvailable: true,
              actions: actions,
            ),
          ),
        ),
      );

      expect(find.byTooltip('Select microphone'), findsNothing);
      expect(find.byTooltip('Select camera'), findsNothing);
      expect(find.byTooltip('Select audio output'), findsNothing);
    });

    testWidgets(
      'shows disabled audio output caret with disabled tooltip when audioOutputDisabledTooltip is provided',
      (tester) async {
        final actions = RoomControlBarActions(
          onPlayPause: () {},
          onSeek: (_) {},
          onSkip: (_) {},
          onMicToggle: (_) {},
          onCamToggle: (_) {},
          onAudioOutputSelect: null,
          audioOutputDisabledTooltip: 'Audio output selection is unavailable for YouTube',
          onAudioTracks: () {},
          onSubtitles: () {},
          onSwitchSource: () {},
          onOpenFile: () {},
          onVolume: (_) {},
          onToggleMute: () {},
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RoomControlBar(
                playing: false,
                position: Duration.zero,
                duration: const Duration(minutes: 10),
                volume: 1.0,
                micOn: false,
                camOn: false,
                avAvailable: true,
                camAvailable: true,
                actions: actions,
              ),
            ),
          ),
        );

        expect(find.byTooltip('Audio output selection is unavailable for YouTube'), findsOneWidget);

        // Tapping disabled caret should not crash
        await tester.tap(find.byTooltip('Audio output selection is unavailable for YouTube'));
        await tester.pump();
      },
    );

    testWidgets('shows hide controls button and triggers onHideControls on tap', (tester) async {
      bool hideTriggered = false;
      final actions = RoomControlBarActions(
        onPlayPause: () {},
        onSeek: (_) {},
        onSkip: (_) {},
        onMicToggle: (_) {},
        onCamToggle: (_) {},
        onAudioTracks: () {},
        onSubtitles: () {},
        onSwitchSource: () {},
        onOpenFile: () {},
        onVolume: (_) {},
        onToggleMute: () {},
        onHideControls: () => hideTriggered = true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomControlBar(
              playing: false,
              position: Duration.zero,
              duration: const Duration(minutes: 10),
              volume: 1.0,
              micOn: false,
              camOn: false,
              avAvailable: true,
              actions: actions,
            ),
          ),
        ),
      );

      final hideFinder = find.byTooltip('Hide controls (H)');
      expect(hideFinder, findsOneWidget);

      await tester.tap(hideFinder);
      await tester.pump();

      expect(hideTriggered, isTrue);
    });

    testWidgets('shows hide controls button in compact mode and triggers on tap', (tester) async {
      bool hideTriggered = false;
      final actions = RoomControlBarActions(
        onPlayPause: () {},
        onSeek: (_) {},
        onSkip: (_) {},
        onMicToggle: (_) {},
        onCamToggle: (_) {},
        onAudioTracks: () {},
        onSubtitles: () {},
        onSwitchSource: () {},
        onOpenFile: () {},
        onVolume: (_) {},
        onToggleMute: () {},
        onHideControls: () => hideTriggered = true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomControlBar(
              playing: false,
              position: Duration.zero,
              duration: const Duration(minutes: 10),
              volume: 1.0,
              micOn: false,
              camOn: false,
              avAvailable: true,
              compact: true,
              actions: actions,
            ),
          ),
        ),
      );

      final hideFinder = find.byTooltip('Hide controls (H)');
      expect(hideFinder, findsOneWidget);

      await tester.tap(hideFinder);
      await tester.pump();

      expect(hideTriggered, isTrue);
    });

    testWidgets('shows fullscreen button and toggles fullscreen state', (tester) async {
      bool fullscreenTriggered = false;
      final actions = RoomControlBarActions(
        onPlayPause: () {},
        onSeek: (_) {},
        onSkip: (_) {},
        onMicToggle: (_) {},
        onCamToggle: (_) {},
        onAudioTracks: () {},
        onSubtitles: () {},
        onSwitchSource: () {},
        onOpenFile: () {},
        onVolume: (_) {},
        onToggleMute: () {},
        onFullscreenToggle: () => fullscreenTriggered = true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomControlBar(
              playing: false,
              position: Duration.zero,
              duration: const Duration(minutes: 10),
              volume: 1.0,
              micOn: false,
              camOn: false,
              avAvailable: true,
              fullscreen: false,
              actions: actions,
            ),
          ),
        ),
      );

      final fsFinder = find.byTooltip('Fullscreen (F)');
      expect(fsFinder, findsOneWidget);
      expect(find.widgetWithIcon(PTIconButton, Symbols.fullscreen_rounded), findsOneWidget);

      await tester.tap(fsFinder);
      await tester.pump();

      expect(fullscreenTriggered, isTrue);
    });

    testWidgets('shows exit fullscreen button when fullscreen is true in compact mode', (
      tester,
    ) async {
      bool fullscreenTriggered = false;
      final actions = RoomControlBarActions(
        onPlayPause: () {},
        onSeek: (_) {},
        onSkip: (_) {},
        onMicToggle: (_) {},
        onCamToggle: (_) {},
        onAudioTracks: () {},
        onSubtitles: () {},
        onSwitchSource: () {},
        onOpenFile: () {},
        onVolume: (_) {},
        onToggleMute: () {},
        onFullscreenToggle: () => fullscreenTriggered = true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomControlBar(
              playing: false,
              position: Duration.zero,
              duration: const Duration(minutes: 10),
              volume: 1.0,
              micOn: false,
              camOn: false,
              avAvailable: true,
              compact: true,
              fullscreen: true,
              actions: actions,
            ),
          ),
        ),
      );

      final exitFsFinder = find.byTooltip('Exit fullscreen (F)');
      expect(exitFsFinder, findsOneWidget);
      expect(find.widgetWithIcon(PTIconButton, Symbols.fullscreen_exit_rounded), findsOneWidget);

      await tester.tap(exitFsFinder);
      await tester.pump();

      expect(fullscreenTriggered, isTrue);
    });
  });

  group('RoomControlBar playhead', () {
    final actions = RoomControlBarActions(
      onPlayPause: () {},
      onSeek: (_) {},
      onSkip: (_) {},
      onMicToggle: (_) {},
      onCamToggle: (_) {},
      onAudioTracks: () {},
      onSubtitles: () {},
      onSwitchSource: () {},
      onOpenFile: () {},
      onVolume: (_) {},
      onToggleMute: () {},
    );

    Widget bar({required bool playing, required Duration position}) => MaterialApp(
      home: Scaffold(
        body: RoomControlBar(
          playing: playing,
          position: position,
          duration: const Duration(minutes: 10),
          volume: 1,
          micOn: false,
          camOn: false,
          avAvailable: false,
          actions: actions,
        ),
      ),
    );

    double fill(WidgetTester tester) => tester.widget<PTSlider>(find.byType(PTSlider).first).value;

    testWidgets('glides forward between position reports while playing', (tester) async {
      await tester.pumpWidget(bar(playing: true, position: const Duration(minutes: 1)));
      final start = fill(tester);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 300));
      expect(fill(tester), greaterThan(start), reason: 'fill advances with no new report');
      // A report slightly behind what was drawn must not twitch the fill back.
      final drawn = fill(tester);
      await tester.pumpWidget(
        bar(playing: true, position: const Duration(minutes: 1, milliseconds: 100)),
      );
      expect(fill(tester), greaterThanOrEqualTo(drawn));
    });

    testWidgets('a seek snaps, and pausing stops every frame', (tester) async {
      await tester.pumpWidget(bar(playing: true, position: const Duration(minutes: 1)));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(bar(playing: true, position: const Duration(minutes: 5)));
      expect(fill(tester), closeTo(0.5, 0.001));

      await tester.pumpWidget(bar(playing: false, position: const Duration(minutes: 5)));
      await tester.pumpAndSettle();
      expect(fill(tester), closeTo(0.5, 0.001));
      expect(tester.binding.hasScheduledFrame, isFalse, reason: 'a paused bar costs no frames');
    });
  });
}
