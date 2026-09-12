import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:synctogether/rooms/room_models.dart';
import 'package:synctogether/rooms/widgets/my_rooms_section.dart';
import 'package:synctogether/ui/buttons.dart';

MyRoom _fakeMyRoom({
  required String id,
  required String name,
  bool isLive = false,
  bool persistent = false,
  bool isOwner = true,
}) {
  final now = DateTime.utc(2026, 9, 13, 0);
  return MyRoom(
    room: Room(
      id: id,
      code: 'CODE$id',
      name: name,
      createdBy: isOwner ? 'user-1' : 'user-2',
      createdAt: now.subtract(const Duration(hours: 2)),
      durationMinutes: 120,
      expiresAt: now.add(const Duration(hours: 2)),
      endedAt: isLive ? null : now.subtract(const Duration(minutes: 30)),
      persistent: persistent,
    ),
    state: isLive ? RoomState.live : RoomState.expired,
    role: 'host',
    memberCount: 2,
    isOwner: isOwner,
    isMember: true,
  );
}

void main() {
  group('MyRoomsSection widget tests', () {
    testWidgets('renders inline count in title e.g. "Your rooms" and "(2)"', (tester) async {
      final rooms = [
        _fakeMyRoom(id: '1', name: 'Room 1', isLive: true),
        _fakeMyRoom(id: '2', name: 'Room 2', isLive: false),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MyRoomsSection(
              rooms: rooms,
              serverNow: DateTime.utc(2026, 9, 13, 0),
              busyRoomId: null,
              onOpen: (_) {},
              onDelete: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Your rooms (2)'), findsOneWidget);
    });

    testWidgets('shows "Clear ended" button when non-persistent ended rooms exist', (tester) async {
      final rooms = [
        _fakeMyRoom(id: '1', name: 'Live Room', isLive: true),
        _fakeMyRoom(id: '2', name: 'Ended Room 1', isLive: false),
        _fakeMyRoom(id: '3', name: 'Ended Room 2', isLive: false),
      ];

      List<MyRoom>? clearedRooms;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MyRoomsSection(
              rooms: rooms,
              serverNow: DateTime.utc(2026, 9, 13, 0),
              busyRoomId: null,
              onOpen: (_) {},
              onDelete: (_) {},
              onClearEnded: (list) => clearedRooms = list,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Clear ended'), findsOneWidget);

      await tester.tap(find.text('Clear ended'));
      await tester.pumpAndSettle();

      expect(clearedRooms, isNotNull);
      expect(clearedRooms!.length, 2);
      expect(clearedRooms!.map((r) => r.room.id), containsAll(['2', '3']));
    });

    testWidgets('hides "Clear ended" button when all rooms are live', (tester) async {
      final rooms = [
        _fakeMyRoom(id: '1', name: 'Live Room 1', isLive: true),
        _fakeMyRoom(id: '2', name: 'Live Room 2', isLive: true),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MyRoomsSection(
              rooms: rooms,
              serverNow: DateTime.utc(2026, 9, 13, 0),
              busyRoomId: null,
              onOpen: (_) {},
              onDelete: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Clear ended'), findsNothing);
      expect(find.byIcon(Symbols.delete_sweep_rounded), findsNothing);
    });

    testWidgets('strictly excludes persistent rooms from "Clear ended" target', (tester) async {
      final rooms = [
        _fakeMyRoom(id: '1', name: 'Persistent Room', isLive: false, persistent: true),
        _fakeMyRoom(id: '2', name: 'Ended Ephemeral', isLive: false, persistent: false),
      ];

      List<MyRoom>? clearedRooms;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MyRoomsSection(
              rooms: rooms,
              serverNow: DateTime.utc(2026, 9, 13, 0),
              busyRoomId: null,
              onOpen: (_) {},
              onDelete: (_) {},
              onClearEnded: (list) => clearedRooms = list,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Clear ended'), findsOneWidget);

      await tester.tap(find.text('Clear ended'));
      await tester.pumpAndSettle();

      expect(clearedRooms, isNotNull);
      expect(clearedRooms!.length, 1);
      expect(clearedRooms!.first.room.id, '2');
    });

    testWidgets('excludes non-owned ended rooms from "Clear ended" target', (tester) async {
      final rooms = [
        _fakeMyRoom(id: '1', name: 'Guest In Ended Room', isLive: false, isOwner: false),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MyRoomsSection(
              rooms: rooms,
              serverNow: DateTime.utc(2026, 9, 13, 0),
              busyRoomId: null,
              onOpen: (_) {},
              onDelete: (_) {},
              onClearEnded: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Clear ended'), findsNothing);
    });

    testWidgets('renders compact icon button when compact is true', (tester) async {
      final rooms = [_fakeMyRoom(id: '1', name: 'Ended Room', isLive: false)];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MyRoomsSection(
              rooms: rooms,
              compact: true,
              serverNow: DateTime.utc(2026, 9, 13, 0),
              busyRoomId: null,
              onOpen: (_) {},
              onDelete: (_) {},
              onClearEnded: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PTIconButton), findsWidgets);
      expect(find.byIcon(Symbols.delete_sweep_rounded), findsOneWidget);
    });
  });

  group('ClearEndedRoomsDialog tests', () {
    testWidgets('shows warning, count, and persistent room reassurance note', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ClearEndedRoomsDialog(count: 5, hasPersistentRooms: true)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Clear 5 ended rooms?'), findsOneWidget);
      expect(
        find.textContaining('Your saved persistent rooms will stay safe and untouched.'),
        findsOneWidget,
      );
      expect(find.text('Keep them'), findsOneWidget);
      expect(find.text('Clear 5 rooms'), findsOneWidget);
    });
  });
}
