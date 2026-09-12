import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/av/livekit_service.dart';
import 'package:synctogether/rooms/widgets/facecam_rail.dart';
import 'package:synctogether/sync/sync_logic.dart';

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

  group('FacecamRail', () {
    testWidgets('renders tiles for present members', (tester) async {
      final av = LiveKitService(roomId: 'room-1', avLevel: .video);
      await av.connect();

      final members = [
        PresentMember(
          userId: 'user-bob',
          displayName: 'Bob',
          role: 'member',
          joinedAt: DateTime(2026, 1, 1, 12, 0),
        ),
        PresentMember(
          userId: 'user-alice',
          displayName: 'Alice',
          role: 'host',
          joinedAt: DateTime(2026, 1, 1, 11, 0),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FacecamRail(av: av, present: members, selfId: 'user-alice', layout: .railLeft),
          ),
        ),
      );

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);

      av.dispose();
    });

    testWidgets('does not reset self state when another member joins', (tester) async {
      final av = LiveKitService(roomId: 'room-1', avLevel: .video);
      await av.connect();
      await av.setCamEnabled(true);

      final initialMembers = [
        PresentMember(
          userId: 'user-alice',
          displayName: 'Alice',
          role: 'host',
          joinedAt: DateTime(2026, 1, 1, 11, 0),
        ),
        PresentMember(
          userId: 'user-bob',
          displayName: 'Bob',
          role: 'member',
          joinedAt: DateTime(2026, 1, 1, 12, 0),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FacecamRail(
              av: av,
              present: initialMembers,
              selfId: 'user-alice',
              layout: .railLeft,
            ),
          ),
        ),
      );

      expect(av.camEnabled, isTrue);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);

      // Charlie joins
      final updatedMembers = [
        ...initialMembers,
        PresentMember(
          userId: 'user-charlie',
          displayName: 'Charlie',
          role: 'member',
          joinedAt: DateTime(2026, 1, 1, 12, 5),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FacecamRail(
              av: av,
              present: updatedMembers,
              selfId: 'user-alice',
              layout: .railLeft,
            ),
          ),
        ),
      );

      // Camera state should remain ON and Charlie should now be rendered
      expect(av.camEnabled, isTrue);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Charlie'), findsOneWidget);

      av.dispose();
    });
  });
}
