import 'package:flutter/material.dart';
import 'package:synctogether/ui/booth_icons.g.dart';
import 'package:flutter_test/flutter_test.dart';
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
    testWidgets('renders inline count in title e.g. "Your tickets" and "(2)"', (tester) async {
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

      expect(find.text('Your tickets (2)'), findsOneWidget);
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
      expect(find.byIcon(BoothIcons.delete), findsNothing);
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
      expect(find.byIcon(BoothIcons.delete), findsOneWidget);
    });
  });

  group('MyRoomsSection motion', () {
    Widget app(List<MyRoom> rooms) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: MyRoomsSection(
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

    testWidgets('a ticket that goes folds shut and the list glides up, no jump', (tester) async {
      // One column (a phone): folding one ticket shrinks the list as it goes. Where two
      // sit side by side the row only closes once both are gone and the rest re-deal.
      tester.view
        ..physicalSize = const Size(400, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final three = [
        _fakeMyRoom(id: '1', name: 'Alpha', isLive: true),
        _fakeMyRoom(id: '2', name: 'Bravo', isLive: true),
        _fakeMyRoom(id: '3', name: 'Charlie', isLive: true),
      ];
      await tester.pumpWidget(app(three));
      await tester.pumpAndSettle();
      final before = tester.getSize(find.byType(MyRoomsSection)).height;
      await tester.pumpWidget(app([three[0], three[2]]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final during = tester.getSize(find.byType(MyRoomsSection)).height;
      expect(find.text('Bravo'), findsOneWidget, reason: 'still folding out');
      await tester.pumpAndSettle();
      final after = tester.getSize(find.byType(MyRoomsSection)).height;
      expect(find.text('Bravo'), findsNothing);
      expect(after, lessThan(before));
      expect(during, lessThan(before), reason: 'already closing');
      expect(during, greaterThan(after), reason: 'not all the way yet');
    });

    testWidgets('Clear ended unfolds beside the title when a room ends', (tester) async {
      await tester.pumpWidget(app([_fakeMyRoom(id: '1', name: 'Alpha', isLive: true)]));
      await tester.pumpAndSettle();
      expect(find.text('Clear ended'), findsNothing);
      await tester.pumpWidget(
        app([
          _fakeMyRoom(id: '1', name: 'Alpha', isLive: true),
          _fakeMyRoom(id: '2', name: 'Bravo'),
        ]),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('Clear ended'), findsOneWidget, reason: 'on its way in');
      await tester.pumpAndSettle();
      expect(find.text('Clear ended'), findsOneWidget);
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
