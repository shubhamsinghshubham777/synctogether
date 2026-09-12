import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/av/livekit_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    LiveKitService.isConfiguredOverride = true;
    LiveKitService.isMockMode = true;
  });

  tearDown(() {
    LiveKitService.isConfiguredOverride = null;
    LiveKitService.isMockMode = false;
  });

  group('LiveKitService', () {
    test('initializes disconnected with mic and cam off', () {
      final service = LiveKitService(roomId: 'room-1', avLevel: .video);

      expect(service.state, AvConnectionState.disconnected);
      expect(service.micEnabled, isFalse);
      expect(service.camEnabled, isFalse);
      expect(service.canPublishCamera, isTrue);

      service.dispose();
    });

    test('voice-only room restricts camera publishing', () {
      final service = LiveKitService(roomId: 'room-1', avLevel: .voice);

      expect(service.canPublishCamera, isFalse);

      service.dispose();
    });

    test('mock connect transitions to connected state', () async {
      final service = LiveKitService(roomId: 'room-1', avLevel: .video);
      var notifications = 0;
      service.addListener(() => notifications++);

      await service.connect();

      expect(service.state, AvConnectionState.connected);
      expect(notifications, greaterThan(0));

      service.dispose();
    });

    test('retains desired mic and cam states across toggles', () async {
      final service = LiveKitService(roomId: 'room-1', avLevel: .video);
      await service.connect();

      await service.setMicEnabled(true);
      expect(service.micEnabled, isTrue);

      await service.setCamEnabled(true);
      expect(service.camEnabled, isTrue);

      await service.setMicEnabled(false);
      expect(service.micEnabled, isFalse);
      expect(service.camEnabled, isTrue);

      await service.setCamEnabled(false);
      expect(service.camEnabled, isFalse);

      service.dispose();
    });

    test('ignores camera enable in voice-only rooms', () async {
      final service = LiveKitService(roomId: 'room-1', avLevel: .voice);
      await service.connect();

      await service.setCamEnabled(true);
      expect(service.camEnabled, isFalse);

      service.dispose();
    });

    test('dispose cleans up timers and marks service disposed', () async {
      final service = LiveKitService(roomId: 'room-1', avLevel: .video);
      await service.connect();

      service.dispose();
      expect(service.state, AvConnectionState.connected);
    });
  });
}
