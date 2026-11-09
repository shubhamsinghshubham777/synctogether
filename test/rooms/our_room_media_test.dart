import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/rooms/our_room_media.dart';

void main() {
  test('a free pair is told 36 hours, in plain words', () {
    final note = ourRoomKeepNote(patron: false);
    expect(note, contains('36 hours'));
    expect(note, contains('continue tomorrow'));
  });

  test('a pair with Patron on either side is told 7 days', () {
    final note = ourRoomKeepNote(patron: true);
    expect(note, contains('7 days'));
    expect(note, isNot(contains('36')));
  });

  test('the mirrors say what the server setting says', () {
    expect(kOurRoomFreeKeepHours, 36);
    expect(kOurRoomPatronKeepHours, 168, reason: '7 days');
  });

  test('the expiry line says how long it was kept', () {
    expect(ourRoomCopyExpiredSubtitle(patron: false), contains('36 hours'));
    expect(ourRoomCopyExpiredSubtitle(patron: true), contains('7 days'));
  });
}
