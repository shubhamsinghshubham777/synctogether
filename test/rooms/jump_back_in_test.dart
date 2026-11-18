import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/analytics.dart';
import 'package:synctogether/mock/mock_dependencies.dart';
import 'package:synctogether/rewards/rewards_service.dart';
import 'package:synctogether/rooms/jump_back_in.dart';
import 'package:synctogether/rooms/lobby_screen.dart';
import 'package:synctogether/rooms/pending_actions.dart';
import 'package:synctogether/rooms/room_models.dart';
import 'package:synctogether/rooms/room_service.dart';
import 'package:synctogether/rooms/widgets/jump_back_in_strip.dart';

import '../layout/layout_support.dart';
import '../support/screen_matrix.dart';

MyRoom room(
  String id,
  String name, {
  bool live = true,
  int members = 3,
  bool member = true,
  DateTime? created,
  Duration left = const Duration(hours: 1),
}) {
  final now = DateTime.now();
  return MyRoom(
    room: Room(
      id: id,
      code: 'C$id',
      name: name,
      createdBy: 'user-alex',
      createdAt: created ?? now.subtract(const Duration(hours: 2)),
      durationMinutes: 120,
      expiresAt: live ? now.add(left) : now.subtract(const Duration(minutes: 5)),
      endedAt: live ? null : now.subtract(const Duration(minutes: 5)),
    ),
    state: live ? .live : .expired,
    role: 'host',
    memberCount: members,
    isOwner: true,
    isMember: member,
  );
}

class _Rooms extends MockRoomService {
  _Rooms(this.all);
  List<MyRoom> all;
  bool failed = false;

  @override
  List<MyRoom> get myRooms => all;
  @override
  bool get myRoomsFailed => failed;
  @override
  DateTime? get myRoomsLoadedAt => null;

  void setRooms(List<MyRoom> next) {
    all = next;
    notifyListeners();
  }
}

const _phone = ScreenCase('phone', Size(390, 844), .iOS);

void main() {
  group('which rooms earn the strip', () {
    test('live, with somebody else in it, and not the one you are in', () {
      final rooms = [
        room('empty', 'Just me', members: 1), // I am the only member: nobody else
        room('busy', 'Busy', members: 3),
        room('ended', 'Over', live: false),
        room('inside', 'Inside', members: 4),
        room('leaving', 'Leaving', members: 2),
      ];
      final picked = jumpBackInRooms(rooms, insideRoomId: 'inside', leavingRoomIds: {'leaving'});
      expect(picked.map((r) => r.room.id), ['busy']);
    });

    test('an owner whose own row is gone counts the rest as others', () {
      // list_my_rooms counts rows; a host who left has none, so memberCount is
      // already "everyone else".
      final r = room('x', 'X', members: 2, member: false);
      expect(othersIn(r), 2);
      expect(othersIn(room('y', 'Y', members: 2)), 1);
    });

    test('newest first', () {
      final now = DateTime.now();
      final picked = jumpBackInRooms([
        room('old', 'Old', created: now.subtract(const Duration(days: 2))),
        room('new', 'New', created: now.subtract(const Duration(minutes: 5))),
      ]);
      expect(picked.map((r) => r.room.id), ['new', 'old']);
    });

    test('only the last few minutes of a timed session are called out', () {
      final now = DateTime.now();
      expect(endingSoonMinutes(room('a', 'A', left: const Duration(minutes: 4)), now), 4);
      expect(endingSoonMinutes(room('a', 'A', left: const Duration(minutes: 40)), now), isNull);
    });
  });

  group('on the phone lobby', () {
    late _Rooms rooms;
    final tapped = <Map<String, Object?>>[];

    Future<void> pumpLobby(WidgetTester tester) async {
      await pumpAtSize(tester, const LobbyScreen(), _phone, singlePane: true, twoPaneBook: true);
      await tester.pump(const Duration(milliseconds: 1500));
    }

    Future<void> settleFolds(WidgetTester t) async {
      await t.pump(); // a fold starts on the frame after the rebuild
      await t.pump(const Duration(seconds: 1));
    }

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      installMockDependencies();
      RewardsService.instance = FakeRewardsService();
      PendingActions.instance = PendingActions();
      addTearDown(PendingActions.instance.resetForTest);
      tapped.clear();
      rooms = RoomService.instance = _Rooms([]);
    });

    testWidgets('no live room: no strip', (t) async {
      await pumpLobby(t);
      expect(find.byType(JumpBackInStrip), findsOneWidget);
      expect(find.text('Jump back in'), findsNothing);
      await finishCase(t);
    });

    testWidgets('one live room: the strip, then it folds away when the room empties', (t) async {
      rooms.all = [room('a', 'Friday Horror Club')];
      await pumpLobby(t);
      await settleFolds(t);
      expect(find.text('Jump back in'), findsOneWidget);
      expect(find.text('NOW SHOWING · 2 IN'), findsOneWidget);
      expect(find.textContaining('ROOMS LIVE'), findsNothing);

      rooms.setRooms([room('a', 'Friday Horror Club', members: 1)]); // only I remain a member
      await settleFolds(t);
      expect(find.text('Jump back in'), findsNothing);
      await finishCase(t);
    });

    testWidgets('two live rooms: a stack that says how many', (t) async {
      final now = DateTime.now();
      rooms.all = [
        room('a', 'Older room', created: now.subtract(const Duration(hours: 3))),
        room('b', 'Newest room', created: now.subtract(const Duration(minutes: 10))),
      ];
      await pumpLobby(t);
      await settleFolds(t);
      expect(find.text('2 ROOMS LIVE'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(JumpBackInStrip), matching: find.text('Newest room')),
        findsOneWidget,
        reason: 'the newest is the one in front',
      );
      expect(
        find.descendant(of: find.byType(JumpBackInStrip), matching: find.text('Older room')),
        findsNothing,
      );
      await finishCase(t);
    });

    testWidgets('a room that ends while the strip is up is explained, not just gone', (t) async {
      rooms.all = [room('a', 'Friday Horror Club')];
      await pumpLobby(t);
      await settleFolds(t);
      rooms.setRooms([room('a', 'Friday Horror Club', live: false)]);
      await settleFolds(t);
      expect(find.text('Friday Horror Club just ended'), findsOneWidget);
      await t.pump(const Duration(seconds: 9)); // the note clears itself
      await settleFolds(t);
      expect(find.text('Friday Horror Club just ended'), findsNothing);
      await finishCase(t);
    });

    testWidgets('a list that failed to refresh dims the strip and stops offering a tap', (t) async {
      rooms.all = [room('a', 'Friday Horror Club')];
      rooms.failed = true;
      await pumpLobby(t);
      await settleFolds(t);
      expect(find.text('Offline'), findsOneWidget);
      expect(find.text('Jump back in'), findsNothing);
      await finishCase(t);
    });

    testWidgets('the strip is never offered for the room you just left', (t) async {
      rooms.all = [room('a', 'Friday Horror Club')];
      PendingActions.instance.start(
        PendingAction(
          kind: .leaveRoom,
          title: 'You left Friday Horror Club',
          roomId: 'a',
          commit: () async {},
        ),
      );
      await pumpLobby(t);
      await settleFolds(t);
      expect(find.text('Jump back in'), findsNothing);
      PendingActions.instance.resetForTest(); // its 5 s timer would outlive the test
      await finishCase(t);
    });

    testWidgets('tapping it counts one product event with the live count', (t) async {
      // There is no router in this harness, so the navigation after the tap throws;
      // the event is sent before it, which is what is under test.
      final onError = FlutterError.onError;
      FlutterError.onError = (_) {};
      addTearDown(() => FlutterError.onError = onError);
      final sent = <Map<String, dynamic>>[];
      Analytics.instance.init(
        apiKey: 'phc_test',
        distinctId: 'u',
        transport: (uri, body) async {
          sent.addAll(
            ((jsonDecode(body) as Map)['batch'] as List).map(
              (e) => (e as Map).cast<String, dynamic>(),
            ),
          );
          return true;
        },
      );
      addTearDown(() => Analytics.instance.setOptedOut(true));
      rooms.all = [room('a', 'Friday Horror Club')];
      await pumpLobby(t);
      await settleFolds(t);
      await Analytics.instance.flush();
      expect(
        sent.where((e) => e['event'] == 'jump_back_in_tapped'),
        isEmpty,
        reason: 'appearing is not a human action',
      );
      await t.tap(find.text('Jump back in'), warnIfMissed: false);
      await t.pump();
      await Analytics.instance.flush();
      final events = sent.where((e) => e['event'] == 'jump_back_in_tapped').toList();
      expect(events, hasLength(1));
      expect((events.single['properties'] as Map)['live_count'], 1);
    });
  });
}
