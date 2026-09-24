import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/mock/mock_dependencies.dart';
import 'package:synctogether/rewards/rewards_service.dart';
import 'package:synctogether/rooms/lobby_screen.dart';
import 'package:synctogether/rooms/room_models.dart';
import 'package:synctogether/rooms/room_service.dart';

import '../support/screen_matrix.dart';
import 'layout_support.dart';

class _EmptyRoomService extends MockRoomService {
  @override
  List<MyRoom> get myRooms => const [];

  @override
  Future<List<MyRoom>> loadMyRooms() async => const [];
}

/// The demo rooms plus long-named, ended and member-only rows.
class _FullRoomService extends MockRoomService {
  late final List<MyRoom> _all = [
    ...super.myRooms,
    for (var i = 0; i < 5; i++)
      MyRoom(
        room: Room(
          id: 'extra-$i',
          code: 'ZZ${i}AB$i',
          name: i.isEven
              ? 'An extraordinarily long room name that will not fit on one line at all #$i'
              : 'Room $i',
          createdBy: i == 1 ? 'someone-else' : 'user-alex',
          createdAt: DateTime.now().subtract(Duration(hours: i + 2)),
          durationMinutes: 120,
          expiresAt: DateTime.now().subtract(Duration(minutes: 10 * i + 1)),
          endedAt: DateTime.now().subtract(Duration(minutes: 10 * i + 1)),
          persistent: i == 2,
        ),
        state: .expired,
        role: i == 1 ? 'member' : 'host',
        memberCount: i + 1,
        isOwner: i != 1,
        isMember: i != 3,
      ),
  ];

  @override
  List<MyRoom> get myRooms => _all;

  @override
  Future<List<MyRoom>> loadMyRooms() async => _all;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    installMockDependencies();
    // Loaded rewards is what lights the streak chip; the mock free tier lights
    // the quota and premium chips - so every header chip is visible.
    RewardsService.instance = FakeRewardsService();
  });

  screenMatrix('lobby/empty', (tester, c, s) async {
    RoomService.instance = _EmptyRoomService();
    await pumpAtSize(tester, const LobbyScreen(), c, textScale: s);
    await tester.pump(const Duration(milliseconds: 1500)); // entrance choreography
    await finishCase(tester);
  });

  screenMatrix('lobby/full-rooms', (tester, c, s) async {
    RoomService.instance = _FullRoomService();
    await pumpAtSize(tester, const LobbyScreen(), c, textScale: s);
    await tester.pump(const Duration(milliseconds: 1500));
    await finishCase(tester);
  });
}
