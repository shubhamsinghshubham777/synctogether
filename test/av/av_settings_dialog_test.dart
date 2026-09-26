import 'dart:async';
import 'package:synctogether/ui/booth_icons.g.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/av/av_settings_dialog.dart';
import 'package:synctogether/av/device_preference_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AvSettingsDialog', () {
    final mockMics = [
      const lk.MediaDevice('mic-1', 'MacBook Microphone', 'audioinput', null),
      const lk.MediaDevice('mic-2', 'Yeti Nano', 'audioinput', null),
    ];
    final mockCams = [
      const lk.MediaDevice('cam-1', 'FaceTime HD', 'videoinput', null),
      const lk.MediaDevice('cam-2', 'External Webcam', 'videoinput', null),
    ];
    final mockOutputs = [
      const lk.MediaDevice('out-1', 'Internal Speakers', 'audiooutput', null),
      const lk.MediaDevice('out-2', 'External Headphones', 'audiooutput', null),
    ];

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'preferred_mic_id': 'mic-2',
        'preferred_mic_label': 'Yeti Nano',
        'preferred_cam_id': 'cam-1',
        'preferred_cam_label': 'FaceTime HD',
        'preferred_output_id': 'out-1',
        'preferred_output_label': 'Internal Speakers',
      });
      final prefs = await SharedPreferences.getInstance();
      await DevicePreferenceService.instance.init(prefs);
    });

    Widget buildTestApp({
      Future<void> Function(lk.MediaDevice? selectedOutput)? onTestSound,
      MicLevels? micLevels,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showAvSettingsDialog(
                context,
                enumerateAudioInputs: () async => mockMics,
                enumerateVideoInputs: () async => mockCams,
                enumerateAudioOutputs: () async => mockOutputs,
                onTestSound: onTestSound,
                micLevels: micLevels,
              ),
              child: const Text('Open Settings'),
            ),
          ),
        ),
      );
    }

    testWidgets('renders dialog with audio & video settings sections and Cancel/Save buttons', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestApp());

      await tester.tap(find.text('Open Settings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Test your mic and camera'), findsOneWidget);
      expect(find.text('MICROPHONE'), findsOneWidget);
      expect(find.text('AUDIO OUTPUT'), findsOneWidget);
      expect(find.text('Does not apply to YouTube mode'), findsOneWidget);
      expect(find.text('CAMERA'), findsOneWidget);
      expect(find.text('Yeti Nano'), findsOneWidget);
      expect(find.text('Internal Speakers'), findsOneWidget);
      expect(find.text('FaceTime HD'), findsOneWidget);
      expect(find.byIcon(BoothIcons.volume), findsWidgets);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('tapping Cancel dismisses dialog without saving changes', (tester) async {
      await tester.pumpWidget(buildTestApp());

      await tester.tap(find.text('Open Settings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Test your mic and camera'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('Test your mic and camera'), findsNothing);
      expect(DevicePreferenceService.instance.preferredMic?.id, 'mic-2');
    });

    testWidgets(
      'selecting a device updates dialog UI reactively without writing immediately to storage',
      (tester) async {
        await tester.pumpWidget(buildTestApp());

        await tester.tap(find.text('Open Settings'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump(const Duration(milliseconds: 100));

        // Initially Yeti Nano is selected
        expect(find.text('Yeti Nano'), findsOneWidget);

        // Tap Yeti Nano dropdown to open popup
        await tester.tap(find.text('Yeti Nano'));
        await tester.pumpAndSettle();

        // Tap "MacBook Microphone" option
        await tester.tap(find.text('MacBook Microphone').last);
        await tester.pumpAndSettle();

        // UI is reactively updated to show MacBook Microphone
        expect(find.text('MacBook Microphone'), findsOneWidget);

        // But preference service is UNTOUCHED because user hasn't clicked Save!
        expect(DevicePreferenceService.instance.preferredMic?.id, 'mic-2');

        // Now cancel the dialog
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        // Preference service is still mic-2
        expect(DevicePreferenceService.instance.preferredMic?.id, 'mic-2');

        // Re-open dialog - it must show Yeti Nano (the saved preference), NOT the discarded draft
        await tester.tap(find.text('Open Settings'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Yeti Nano'), findsOneWidget);
      },
    );

    testWidgets('tapping Save commits draft changes to DevicePreferenceService and closes dialog', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestApp());

      await tester.tap(find.text('Open Settings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 100));

      // Select MacBook Microphone
      await tester.tap(find.text('Yeti Nano'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('MacBook Microphone').last);
      await tester.pumpAndSettle();

      // Select External Headphones
      await tester.tap(find.text('Internal Speakers'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('External Headphones').last);
      await tester.pumpAndSettle();

      // Select External Webcam
      await tester.tap(find.text('FaceTime HD'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('External Webcam').last);
      await tester.pumpAndSettle();

      // Preferences still not saved before tapping Save
      expect(DevicePreferenceService.instance.preferredMic?.id, 'mic-2');
      expect(DevicePreferenceService.instance.preferredOutput?.id, 'out-1');
      expect(DevicePreferenceService.instance.preferredCam?.id, 'cam-1');

      // Tap Save
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Dialog is closed
      expect(find.text('Test your mic and camera'), findsNothing);

      // Preferences are now committed
      expect(DevicePreferenceService.instance.preferredMic?.id, 'mic-1');
      expect(DevicePreferenceService.instance.preferredOutput?.id, 'out-2');
      expect(DevicePreferenceService.instance.preferredCam?.id, 'cam-2');

      // Reopening shows the newly saved preferences
      await tester.tap(find.text('Open Settings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('MacBook Microphone'), findsOneWidget);
      expect(find.text('External Headphones'), findsOneWidget);
      expect(find.text('External Webcam'), findsOneWidget);
    });

    testWidgets('tapping Test output button routes to the currently selected draft output device', (
      tester,
    ) async {
      lk.MediaDevice? testedDevice;
      await tester.pumpWidget(
        buildTestApp(
          onTestSound: (device) async {
            testedDevice = device;
          },
        ),
      );

      await tester.tap(find.text('Open Settings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 100));

      // Select External Headphones in draft dropdown
      await tester.tap(find.text('Internal Speakers'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('External Headphones').last);
      await tester.pumpAndSettle();

      final testButton = find.byTooltip('Test output');
      expect(testButton, findsOneWidget);

      await tester.tap(testButton);
      await tester.pump();

      expect(testedDevice?.deviceId, 'out-2');
      expect(testedDevice?.label, 'External Headphones');
    });

    testWidgets('Test mic opens the selected device only when asked and releases it on Stop', (
      tester,
    ) async {
      final opened = <String?>[];
      final controllers = <StreamController<List<double>>>[];
      Stream<List<double>> fakeLevels(String? deviceId) {
        opened.add(deviceId);
        final c = StreamController<List<double>>();
        controllers.add(c);
        return c.stream;
      }

      await tester.pumpWidget(buildTestApp(micLevels: fakeLevels));
      await tester.tap(find.text('Open Settings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));

      // Nothing touches the mic until asked.
      expect(opened, isEmpty);
      await tester.tap(find.text('Test mic'));
      await tester.pump();
      expect(opened, ['mic-2']);
      expect(find.text('Say something'), findsOneWidget);

      controllers.last.add(List.filled(16, 0.6));
      await tester.pump();

      await tester.tap(find.text('Stop'));
      await tester.pump();
      expect(controllers.last.hasListener, isFalse);
      expect(find.text('Test mic'), findsOneWidget);
    });

    testWidgets('a mic that fails to open says so and stops testing', (tester) async {
      await tester.pumpWidget(
        buildTestApp(micLevels: (_) => Stream<List<double>>.error(StateError('no device'))),
      );
      await tester.tap(find.text('Open Settings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));

      await tester.tap(find.text('Test mic'));
      await tester.pump();
      await tester.pump();
      expect(find.text("Couldn't open that mic"), findsOneWidget);
      expect(find.text('Test mic'), findsOneWidget);
    });
  });
}
