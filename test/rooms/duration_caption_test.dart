import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/profile/entitlement_service.dart';
import 'package:synctogether/rooms/lobby_screen.dart';

TierLimits _limits({required int session, required int total}) => TierLimits(
  tier: 'x',
  maxLiveRooms: 4,
  maxMembers: 8,
  maxSessionMinutes: session,
  maxTotalSessionMinutes: total,
  avLevel: .voice,
  persistentRoomCap: 0,
  dormantHours: 0,
  freeExtensionMinutes: 0,
);

void main() {
  group('the caption under the duration slider', () {
    test('a free room can only be as long as the slider says', () {
      expect(durationCaption(_limits(session: 240, total: 240)), '4 HOURS MAX');
    });

    test('a guest room is in minutes', () {
      expect(durationCaption(_limits(session: 60, total: 60)), '60 MIN MAX');
    });

    test('a Patron room says it can grow, and by how much', () {
      expect(durationCaption(_limits(session: 240, total: 1440)), '4 HOURS · EXTEND TO 24 H');
    });
  });
}
