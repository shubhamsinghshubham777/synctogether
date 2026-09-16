import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:synctogether/auth/auth_service.dart';
import 'package:synctogether/av/livekit_service.dart';
import 'package:synctogether/mock/mock_dependencies.dart';
import 'package:synctogether/profile/profile_service.dart';
import 'package:synctogether/rooms/room_models.dart';
import 'package:synctogether/rooms/room_service.dart';
import 'package:synctogether/ui/identity.dart';

Uint8List _generateTestJpg() {
  final image = img.Image(width: 100, height: 100);
  img.fill(image, color: img.ColorRgb8(120, 80, 200));
  return Uint8List.fromList(img.encodeJpg(image));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Apple Reviewer Demo Environment & Mock Dependencies', () {
    setUp(() {
      installMockDependencies();
    });

    test(
      'MockProfileService handles updateDisplayName and uploadAvatar without Supabase',
      () async {
        final profileService = ProfileService.instance;
        expect(profileService.profile?.displayName, 'Alex Rivers');

        var notified = false;
        profileService.addListener(() => notified = true);

        await profileService.updateDisplayName('Apple Reviewer');
        expect(profileService.profile?.displayName, 'Apple Reviewer');
        expect(notified, isTrue);

        notified = false;
        final testBytes = _generateTestJpg();
        await profileService.uploadAvatar(testBytes);

        expect(notified, isTrue);
        expect(profileService.profile?.avatarUrl, isNotNull);
        expect(File(profileService.profile!.avatarUrl!).existsSync(), isTrue);

        // Clean up temp avatar file
        try {
          File(profileService.profile!.avatarUrl!).deleteSync();
        } catch (_) {}
      },
    );

    test('MockAuthService provides properly typed user and session', () {
      final authService = AuthService.instance;
      expect(authService.user, isNotNull);
      expect(authService.user!.id, 'user-alex');
      expect(authService.user!.email, 'alex@synctogether.app');
      expect(authService.user!.userMetadata?['full_name'], 'Alex Rivers');
      expect(authService.session, isNotNull);
      expect(authService.session!.accessToken, 'mock-access-token');
      expect(authService.session!.user.email, 'alex@synctogether.app');
    });

    test('MockAuthService handles signOut and deleteAccount cleanly', () async {
      final authService = AuthService.instance;
      expect(authService.isSignedIn, isTrue);

      final events = <dynamic>[];
      final sub = authService.onAuthStateChange.listen((event) => events.add(event.event));

      await authService.signOut();
      expect(authService.isSignedIn, isFalse);
      expect(authService.session, isNull);
      expect(authService.user, isNull);
      expect(LiveKitService.isMockMode, isFalse);

      await Future.delayed(const Duration(milliseconds: 10));
      expect(events, contains(AuthChangeEvent.signedOut));
      await sub.cancel();
    });

    test('MockRoomService provides live rooms and handles full room mutations', () async {
      final roomService = RoomService.instance;
      final rooms = await roomService.loadMyRooms();
      expect(rooms.length, 3);
      for (final r in rooms) {
        expect(r.isLive, isTrue);
      }

      // Room 2 has YouTube configured
      expect(mockRoomTwo.mediaKind, RoomMediaKind.youtube);
      expect(mockRoomTwo.mediaUrl, contains('youtube.com'));

      // Create room in mock mode
      final created = await roomService.createRoom(name: 'Reviewer Room', durationMinutes: 90);
      expect(created.name, 'Reviewer Room');
      expect(roomService.myRooms.first.room.id, created.id);

      // Delete room in mock mode
      await roomService.deleteRoom(created.id);
      expect(roomService.myRooms.any((r) => r.room.id == created.id), isFalse);

      // Join room by code
      final joined = await roomService.joinRoom('X7K9P2');
      expect(joined.id, mockRoomOne.id);
    });

    test('LiveKitService mock mode provides safe device getters and operations', () async {
      expect(LiveKitService.isMockMode, isTrue);

      final av = LiveKitService(roomId: 'demo-room-1', avLevel: .video);
      await av.connect();
      expect(av.state, AvConnectionState.connected);

      expect(av.selectedAudioInputId, 'mock-mic-1');
      expect(av.selectedVideoInputId, 'mock-cam-1');
      expect(av.selectedAudioOutputId, 'mock-out-1');

      final mics = await av.audioInputDevices();
      expect(mics.isNotEmpty, isTrue);
      await av.setAudioInputDevice(mics.first);
      expect(av.selectedAudioInput?.deviceId, mics.first.deviceId);

      await av.setMicEnabled(true);
      expect(av.micEnabled, isTrue);
      await av.setCamEnabled(true);
      expect(av.camEnabled, isTrue);

      av.dispose();
    });

    test('resolveAvatarImage safely maps local paths, file URIs, assets, and web URLs', () {
      expect(resolveAvatarImage('/path/to/avatar.jpg'), isA<FileImage>());
      expect(resolveAvatarImage('file:///path/to/avatar.jpg'), isA<FileImage>());
      expect(resolveAvatarImage('assets/store/movie_still.jpg'), isA<AssetImage>());
      expect(resolveAvatarImage('https://example.com/avatar.jpg'), isA<NetworkImage>());
    });

    testWidgets('PTAvatar renders fallback letters and custom presence', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PTAvatar(userId: 'user-alex', displayName: 'Alex Rivers', presence: true),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(PTAvatar), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
    });
  });
}
