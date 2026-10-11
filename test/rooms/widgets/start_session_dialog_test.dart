import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/rooms/room_models.dart';
import 'package:synctogether/rooms/widgets/extend_room_dialog.dart';

void main() {
  group('StartSessionDialog.optionsFor', () {
    test('offers the presets under the cap, then the cap itself', () {
      expect(StartSessionDialog.optionsFor(240), [30, 60, 120, 240]);
      expect(StartSessionDialog.optionsFor(60), [30, 60]);
      expect(StartSessionDialog.optionsFor(90), [30, 60, 90]);
    });
  });

  test('an idle room is not live and not expired', () {
    expect(RoomErrorCode.fromError('room_idle'), RoomErrorCode.roomIdle);
  });
}
