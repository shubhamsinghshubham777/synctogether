import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/rooms/room_models.dart';
import 'package:synctogether/rooms/widgets/ended_room_dialog.dart';

void main() {
  group('EndedRoomDialog', () {
    final testRoom = Room(
      id: 'room-1',
      code: 'ABC123',
      name: 'Movie Night',
      createdBy: 'user-1',
      createdAt: DateTime.now(),
      durationMinutes: 60,
      expiresAt: DateTime.now(),
    );

    testWidgets('renders Get Premium button and perk banner on non-Apple builds', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EndedRoomDialog(
              room: testRoom,
              onStartFresh: () {},
              onUpgrade: () {},
              onDelete: () {},
              appleStoreBuildOverride: false,
            ),
          ),
        ),
      );

      expect(find.text('Start fresh room'), findsOneWidget);
      expect(find.text('Get Premium'), findsOneWidget);
      expect(find.text('Premium keeps up to 20 rooms saved forever.'), findsOneWidget);
      expect(find.textContaining('upgrade to Premium'), findsOneWidget);
    });

    testWidgets('hides Get Premium button and upsells on Apple Store builds', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EndedRoomDialog(
              room: testRoom,
              onStartFresh: () {},
              onUpgrade: () {},
              onDelete: () {},
              appleStoreBuildOverride: true,
            ),
          ),
        ),
      );

      expect(find.text('Start fresh room'), findsOneWidget);
      expect(find.text('Get Premium'), findsNothing);
      expect(find.text('Premium keeps up to 20 rooms saved forever.'), findsNothing);
      expect(find.textContaining('upgrade to Premium'), findsNothing);
      expect(
        find.textContaining(
          'Free watch rooms are session-based and close once the party wraps up.',
        ),
        findsOneWidget,
      );
    });
  });
}
