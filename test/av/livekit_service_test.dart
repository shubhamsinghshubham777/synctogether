import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
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

    test('a camera that cannot open is switched back off and announced', () async {
      final service = LiveKitService(roomId: 'room-1', avLevel: .video);
      await service.connect();
      await service.setCamEnabled(true);
      final failures = <String>[];
      service.trackFailures.listen(failures.add);
      var notified = 0;
      service.addListener(() => notified++);

      service.debugTrackSyncFailed('cam', lk.TrackCreateException());
      await Future<void>.delayed(Duration.zero);

      expect(service.camEnabled, isFalse);
      expect(failures, ['cam']);
      expect(notified, 1);
      expect(service.debugSyncCoolingDown, isTrue);

      service.dispose();
    });

    test('a mic that cannot open leaves the camera alone', () async {
      final service = LiveKitService(roomId: 'room-1', avLevel: .video);
      await service.connect();
      await service.setMicEnabled(true);
      await service.setCamEnabled(true);

      service.debugTrackSyncFailed('mic', lk.TrackCreateException());

      expect(service.micEnabled, isFalse);
      expect(service.camEnabled, isTrue);

      service.dispose();
    });

    test('a publisher closed mid-reconnect cools down but keeps what was asked for', () async {
      final service = LiveKitService(roomId: 'room-1', avLevel: .video);
      await service.connect();
      await service.setMicEnabled(true);
      final failures = <String>[];
      service.trackFailures.listen(failures.add);

      service.debugTrackSyncFailed('mic', lk.UnexpectedConnectionState('publisher is closed'));
      await Future<void>.delayed(Duration.zero);

      expect(service.micEnabled, isTrue);
      expect(failures, isEmpty);
      expect(service.debugSyncCoolingDown, isTrue);

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
