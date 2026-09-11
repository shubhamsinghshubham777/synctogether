import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:material_symbols_icons/symbols.dart';
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

    Widget buildTestApp({Future<void> Function(lk.MediaDevice? selectedOutput)? onTestSound}) {
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

      expect(find.text('Audio & Video Settings'), findsOneWidget);
      expect(find.text('Microphone'), findsOneWidget);
      expect(find.text('Audio Output'), findsOneWidget);
      expect(find.text('Does not apply to YouTube mode'), findsOneWidget);
      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('Yeti Nano'), findsOneWidget);
      expect(find.text('Internal Speakers'), findsOneWidget);
      expect(find.text('FaceTime HD'), findsOneWidget);
      expect(find.byIcon(Symbols.volume_up_rounded), findsWidgets);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('tapping Cancel dismisses dialog without saving changes', (tester) async {
      await tester.pumpWidget(buildTestApp());

      await tester.tap(find.text('Open Settings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Audio & Video Settings'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('Audio & Video Settings'), findsNothing);
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
      expect(find.text('Audio & Video Settings'), findsNothing);

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
  });
}
