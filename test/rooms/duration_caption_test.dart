import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  group('the row under the slider', () {
    for (final (name, width, scale) in [
      ('a small phone', 280.0, 1.0),
      ('a small phone at 1.3x text', 280.0, 1.3),
      ('a normal phone', 350.0, 1.0),
    ]) {
      testWidgets('the Patron caption is whole on $name', (tester) async {
        final caption = durationCaption(_limits(session: 240, total: 1440));
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: width,
                    child: DurationBounds(caption: caption),
                  ),
                ),
              ),
            ),
          ),
        );
        final paragraph = tester.renderObject<RenderParagraph>(find.text(caption));
        expect(paragraph.didExceedMaxLines, isFalse, reason: 'cut off at ${width}px, ${scale}x');
        expect(find.text('5 MIN'), findsOneWidget);
      });
    }
  });
}
