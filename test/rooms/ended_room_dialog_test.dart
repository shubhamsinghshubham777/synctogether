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

    testWidgets('renders Get Premium button and perk banner', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EndedRoomDialog(
              room: testRoom,
              onStartFresh: () {},
              onUpgrade: () {},
              onDelete: () {},
            ),
          ),
        ),
      );

      expect(find.text('Open a fresh room'), findsOneWidget);
      expect(find.text('Patron: 20 saved rooms'), findsOneWidget);
      expect(find.textContaining('That show has closed'), findsOneWidget);
      expect(find.text('Resume this room'), findsNothing);
    });

    testWidgets('offers Resume only when the room can still be resumed', (tester) async {
      var resumed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => EndedRoomDialog(
                room: testRoom,
                onStartFresh: () {},
                onResume: () => resumed = true,
                onDelete: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('Resume this room'), findsOneWidget);
      expect(find.text('Open a fresh room'), findsOneWidget);
      await tester.tap(find.text('Resume this room'));
      await tester.pump();
      expect(resumed, isTrue);
    });
  });
}
