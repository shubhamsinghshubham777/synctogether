import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The picture is the product: it is shown whole, letterboxed in whatever box a
/// layout gives it, and never cropped to fill that box - a tall half of a folded
/// phone included. The surface is built in `RoomScreen._video()`; this fails if a
/// cropping fit ever appears there, or the player's fit stops being stated.
void main() {
  test('the room\'s picture is never cropped to fill its box', () {
    final source = File('lib/rooms/room_screen.dart').readAsStringSync();
    final start = source.indexOf('Widget _video() {');
    expect(start, greaterThan(0));
    final end = source.indexOf('\n  }\n', start);
    final body = source.substring(start, end);
    for (final cropping in ['BoxFit.cover', 'BoxFit.fill', 'BoxFit.fitWidth', 'BoxFit.fitHeight']) {
      expect(body.contains(cropping), isFalse, reason: '_video() uses $cropping');
    }
    expect(body.contains('fit: BoxFit.contain'), isTrue, reason: 'the player fit must be stated');
  });
}
