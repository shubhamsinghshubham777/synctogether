import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:material_symbols_icons/symbols.dart';
import 'package:synctogether/av/device_selector_popup.dart';
import 'package:synctogether/ui/loader.dart';

void main() {
  group('showDeviceSelectorPopup', () {
    testWidgets('renders loading state initially then devices list', (tester) async {
      final completer = Completer<List<lk.MediaDevice>>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDeviceSelectorPopup(
                    context: context,
                    anchor: const Rect.fromLTWH(100, 500, 42, 42),
                    title: 'Select Microphone',
                    icon: Symbols.mic_rounded,
                    enumerateDevices: () => completer.future,
                    selectedDeviceId: 'mic-2',
                    onDeviceSelected: (_) {},
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pump();

      // Dialog is opening, shows PTLoader
      expect(find.byType(PTLoader), findsOneWidget);
      expect(find.text('Select Microphone'), findsOneWidget);

      completer.complete([
        const lk.MediaDevice('mic-1', 'Internal Microphone', 'audioinput', null),
        const lk.MediaDevice('mic-2', 'USB Microphone', 'audioinput', null),
      ]);
      await tester.pumpAndSettle();

      expect(find.byType(PTLoader), findsNothing);
      expect(find.text('Internal Microphone'), findsOneWidget);
      expect(find.text('USB Microphone'), findsOneWidget);

      // Selected device has check icon
      expect(find.byIcon(Symbols.check_circle_rounded), findsOneWidget);
    });

    testWidgets('calls onDeviceSelected and closes dialog when tapping a device', (tester) async {
      lk.MediaDevice? selected;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDeviceSelectorPopup(
                    context: context,
                    anchor: const Rect.fromLTWH(100, 500, 42, 42),
                    title: 'Select Camera',
                    icon: Symbols.videocam_rounded,
                    enumerateDevices: () async => [
                      const lk.MediaDevice('cam-1', 'FaceTime HD Camera', 'videoinput', null),
                      const lk.MediaDevice('cam-2', 'External Webcam', 'videoinput', null),
                    ],
                    selectedDeviceId: 'cam-1',
                    onDeviceSelected: (d) => selected = d,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('External Webcam'), findsOneWidget);

      await tester.tap(find.text('External Webcam'));
      await tester.pumpAndSettle();

      expect(selected, isNotNull);
      expect(selected!.deviceId, 'cam-2');
      expect(selected!.label, 'External Webcam');

      // Popup is dismissed
      expect(find.text('External Webcam'), findsNothing);
    });

    testWidgets('shows empty state when no devices are available', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDeviceSelectorPopup(
                    context: context,
                    anchor: const Rect.fromLTWH(100, 500, 42, 42),
                    title: 'Select Camera',
                    icon: Symbols.videocam_rounded,
                    enumerateDevices: () async => [],
                    selectedDeviceId: null,
                    onDeviceSelected: (_) {},
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('No devices found'), findsOneWidget);
    });

    testWidgets('refreshes device list when onDeviceChange emits', (tester) async {
      final streamController = StreamController<List<lk.MediaDevice>>.broadcast();
      addTearDown(streamController.close);

      var devices = [const lk.MediaDevice('mic-1', 'Built-in Mic', 'audioinput', null)];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDeviceSelectorPopup(
                    context: context,
                    anchor: const Rect.fromLTWH(100, 500, 42, 42),
                    title: 'Select Microphone',
                    icon: Symbols.mic_rounded,
                    enumerateDevices: () async => devices,
                    selectedDeviceId: 'mic-1',
                    onDeviceSelected: (_) {},
                    onDeviceChange: streamController.stream,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Built-in Mic'), findsOneWidget);
      expect(find.text('Plugged-in Headset'), findsNothing);

      // Simulate hot-plug
      devices = [
        const lk.MediaDevice('mic-1', 'Built-in Mic', 'audioinput', null),
        const lk.MediaDevice('mic-2', 'Plugged-in Headset', 'audioinput', null),
      ];
      streamController.add(devices);
      await tester.pumpAndSettle();

      expect(find.text('Built-in Mic'), findsOneWidget);
      expect(find.text('Plugged-in Headset'), findsOneWidget);
    });

    testWidgets(
      'resolves selected device by label and shows selection tick when IDs differ (macOS CoreAudio vs WebRTC)',
      (tester) async {
        final devices = [
          const lk.MediaDevice('AppleHDAEngineInput:1', 'USB Audio CODEC', 'audioinput', null),
          const lk.MediaDevice(
            'BuiltInMicrophoneDevice',
            "Shubham's iPhone Microphone",
            'audioinput',
            null,
          ),
          const lk.MediaDevice('com.reincubate.camo', 'Camo Microphone', 'audioinput', null),
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    showDeviceSelectorPopup(
                      context: context,
                      anchor: const Rect.fromLTWH(100, 500, 42, 42),
                      title: 'Select Microphone',
                      icon: Symbols.mic_rounded,
                      enumerateDevices: () async => devices,
                      // WebRTC device ID differs from CoreAudio UID
                      selectedDeviceId: '0',
                      selectedDeviceLabel: 'USB Audio CODEC',
                      onDeviceSelected: (_) {},
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.text('USB Audio CODEC'), findsOneWidget);
        expect(find.text("Shubham's iPhone Microphone"), findsOneWidget);
        expect(find.text('Camo Microphone'), findsOneWidget);

        // Selection tick is rendered for the resolved match
        expect(find.byIcon(Symbols.check_circle_rounded), findsOneWidget);
      },
    );
  });
}
