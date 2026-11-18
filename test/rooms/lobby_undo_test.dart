import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/mock/mock_dependencies.dart';
import 'package:synctogether/rewards/rewards_service.dart';
import 'package:synctogether/rooms/lobby_screen.dart';
import 'package:synctogether/rooms/pending_actions.dart';
import 'package:synctogether/rooms/room_models.dart';
import 'package:synctogether/rooms/room_service.dart';
import 'package:synctogether/ui/banners.dart';
import 'package:synctogether/ui/buttons.dart';

import '../layout/layout_support.dart';
import '../support/finders.dart';
import '../support/screen_matrix.dart';

MyRoom _room(String id, String name, {required bool live, required int members}) {
  final now = DateTime.now();
  return MyRoom(
    room: Room(
      id: id,
      code: 'C$id',
      name: name,
      createdBy: 'user-alex',
      createdAt: now.subtract(const Duration(hours: 2)),
      durationMinutes: 120,
      expiresAt: live
          ? now.add(const Duration(hours: 1))
          : now.subtract(const Duration(minutes: 5)),
      endedAt: live ? null : now.subtract(const Duration(minutes: 5)),
    ),
    state: live ? .live : .expired,
    role: 'host',
    memberCount: members,
    isOwner: true,
    isMember: true,
  );
}

/// The real hide/unhide contract over a fixed list, recording server calls.
class _Rooms extends MockRoomService {
  _Rooms(this.all);
  final List<MyRoom> all;
  final hidden = <String>{};
  final deleted = <String>[];

  @override
  List<MyRoom> get myRooms => all.where((r) => !hidden.contains(r.room.id)).toList();

  @override
  void hideRooms(Set<String> ids) {
    hidden.addAll(ids);
    notifyListeners();
  }

  @override
  void unhideRooms(Set<String> ids) {
    hidden.removeAll(ids);
    notifyListeners();
  }

  @override
  Future<void> deleteRoom(String roomId) async {
    deleted.add(roomId);
    all.removeWhere((r) => r.room.id == roomId);
  }
}

const _phone = ScreenCase('phone', Size(390, 844), .iOS);

void main() {
  late _Rooms rooms;

  Future<void> pumpLobby(WidgetTester tester) async {
    await pumpAtSize(tester, const LobbyScreen(), _phone, singlePane: true, twoPaneBook: true);
    await tester.pump(const Duration(milliseconds: 1500));
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    installMockDependencies();
    RewardsService.instance = FakeRewardsService();
    rooms = RoomService.instance = _Rooms([
      _room('quiet', 'Ghibli Sundays', live: false, members: 1),
      _room('busy', 'Friday Horror Club', live: true, members: 4),
    ]);
    PendingActions.instance = PendingActions();
    addTearDown(PendingActions.instance.resetForTest);
  });

  /// The list is below the fold on a phone: scroll to the button first.
  Future<void> tapDelete(WidgetTester t, {required bool last}) async {
    final all = byUiTooltip('Delete room');
    final target = last ? all.last : all.first;
    await t.ensureVisible(target);
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(target);
  }

  testWidgets('delete: the ticket goes at once, Undo brings it back, no server call', (t) async {
    await pumpLobby(t);
    expect(find.text('Ghibli Sundays'), findsOneWidget);
    await tapDelete(t, last: false);
    await t.pump(); // the fold starts on the frame after the rebuild
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('Deleted Ghibli Sundays'), findsOneWidget);
    expect(find.byType(PTBanner), findsOneWidget);
    expect(rooms.deleted, isEmpty, reason: 'the call waits out the window');

    await t.tap(find.widgetWithText(PTButton, 'Undo'));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Deleted Ghibli Sundays'), findsNothing, reason: 'the banner folds away');
    expect(rooms.hidden, isEmpty, reason: 'the ticket is back');
    expect(find.text('Ghibli Sundays'), findsOneWidget);
    await t.pump(const Duration(seconds: 10));
    expect(rooms.deleted, isEmpty, reason: 'Undo is a real undo');
    await finishCase(t);
  });

  testWidgets('delete then wait: exactly one server call after 5 s', (t) async {
    await pumpLobby(t);
    await tapDelete(t, last: false);
    await t.pump(const Duration(seconds: 4));
    expect(rooms.deleted, isEmpty);
    await t.pump(const Duration(seconds: 2));
    expect(rooms.deleted, ['quiet']);
    await t.pump(const Duration(seconds: 10));
    expect(rooms.deleted, ['quiet'], reason: 'once, not per tick');
    await finishCase(t);
  });

  testWidgets('delete then background: commits at once', (t) async {
    await pumpLobby(t);
    await tapDelete(t, last: false);
    await t.pump(const Duration(seconds: 1));
    expect(rooms.deleted, isEmpty);
    PendingActions.instance.didChangeAppLifecycleState(AppLifecycleState.paused);
    await t.pump();
    expect(rooms.deleted, ['quiet']);
    await finishCase(t);
  });

  testWidgets('a live room with other people in it still asks first', (t) async {
    await pumpLobby(t);
    await tapDelete(t, last: true);
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('Delete this room?'), findsOneWidget);
    expect(PendingActions.instance.current, isNull, reason: 'no Undo path for others\' seats');
    expect(rooms.deleted, isEmpty);
    await finishCase(t);
  });
}
