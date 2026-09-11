import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/av/device_preference_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DevicePreferenceService', () {
    late DevicePreferenceService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      service = DevicePreferenceService.instance;
      await service.init();
    });

    test('initial state has null preferred devices', () {
      expect(service.preferredMic, isNull);
      expect(service.preferredCam, isNull);
      expect(service.preferredOutput, isNull);
    });

    test('saves and loads preferred microphone', () async {
      const mic = lk.MediaDevice('mic-123', 'Yeti Nano', 'audioinput', null);
      await service.setPreferredMic(mic);

      expect(service.preferredMic?.id, 'mic-123');
      expect(service.preferredMic?.label, 'Yeti Nano');

      // Clear
      await service.setPreferredMic(null);
      expect(service.preferredMic, isNull);
    });

    test('saves and loads preferred camera', () async {
      const cam = lk.MediaDevice('cam-456', 'FaceTime HD', 'videoinput', null);
      await service.setPreferredCam(cam);

      expect(service.preferredCam?.id, 'cam-456');
      expect(service.preferredCam?.label, 'FaceTime HD');

      await service.setPreferredCam(null);
      expect(service.preferredCam, isNull);
    });

    test('saves and loads preferred audio output', () async {
      const spk = lk.MediaDevice('spk-789', 'External Headphones', 'audiooutput', null);
      await service.setPreferredOutput(spk);

      expect(service.preferredOutput?.id, 'spk-789');
      expect(service.preferredOutput?.label, 'External Headphones');

      await service.setPreferredOutput(null);
      expect(service.preferredOutput, isNull);
    });

    test('re-init restores preferences from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'preferred_mic_id': 'saved-mic-id',
        'preferred_mic_label': 'Saved Mic Label',
        'preferred_output_id': 'saved-out-id',
        'preferred_output_label': 'Saved Out Label',
      });

      final prefs = await SharedPreferences.getInstance();
      await service.init(prefs);

      expect(service.preferredMic?.id, 'saved-mic-id');
      expect(service.preferredMic?.label, 'Saved Mic Label');
      expect(service.preferredOutput?.id, 'saved-out-id');
      expect(service.preferredOutput?.label, 'Saved Out Label');
      expect(service.preferredCam, isNull);
    });

    group('resolveDevice fallback hierarchy', () {
      final devices = [
        const lk.MediaDevice('builtin-1', 'MacBook Pro Microphone', 'audioinput', null),
        const lk.MediaDevice('usb-2', 'Yeti Nano Stereo', 'audioinput', null),
        const lk.MediaDevice('bt-3', 'AirPods Pro', 'audioinput', null),
      ];

      test('returns null if available devices is empty', () {
        final resolved = service.resolveDevice([], const PreferredDevice(id: 'any', label: 'any'));
        expect(resolved, isNull);
      });

      test('returns first available if preferred is null', () {
        final resolved = service.resolveDevice(devices, null);
        expect(resolved?.deviceId, 'builtin-1');
      });

      test('Tier 1: resolves by exact deviceId', () {
        final resolved = service.resolveDevice(
          devices,
          const PreferredDevice(id: 'usb-2', label: 'Different Label'),
        );
        expect(resolved?.deviceId, 'usb-2');
        expect(resolved?.label, 'Yeti Nano Stereo');
      });

      test('Tier 2: resolves by exact label if deviceId changed', () {
        final resolved = service.resolveDevice(
          devices,
          const PreferredDevice(id: 'different-id', label: 'AirPods Pro'),
        );
        expect(resolved?.deviceId, 'bt-3');
        expect(resolved?.label, 'AirPods Pro');
      });

      test('Tier 3: resolves by partial label match', () {
        final resolved = service.resolveDevice(
          devices,
          const PreferredDevice(id: 'unknown-id', label: 'Yeti Nano'),
        );
        expect(resolved?.deviceId, 'usb-2');
      });

      test('Tier 4: falls back to system default (first device) if preferred device missing', () {
        final resolved = service.resolveDevice(
          devices,
          const PreferredDevice(id: 'unplugged-id', label: 'Studio Display Mic'),
        );
        expect(resolved?.deviceId, 'builtin-1');
      });
    });
  });
}
