import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/pairing/pair_links.dart';

void main() {
  group('pair links', () {
    test('a pair code is read from the path and upper-cased', () {
      expect(pairCodeFromLink(Uri.parse('synctogether://pair/m4ya7k')), 'M4YA7K');
      expect(pairCodeFromLink(Uri.parse('synctogether://pair/M4YA7K?x=1')), 'M4YA7K');
    });

    test('anything that is not a well-formed pair link is ignored', () {
      for (final bad in [
        'synctogether://join/M4YA7K',
        'https://synctogether.example/pair/M4YA7K',
        'synctogether://pair/',
        'synctogether://pair/M4YA7',
        'synctogether://pair/M4YA7KK',
        'synctogether://pair/M4YA70', // 0 is not in the server alphabet
        'synctogether://pair/..%2F..',
      ]) {
        expect(pairCodeFromLink(Uri.parse(bad)), isNull, reason: bad);
      }
    });
  });

  group('push links', () {
    PushTarget? target(String url) => pushTargetFromLink(Uri.parse(url));

    test('each route maps to its screen', () {
      expect(target('synctogether://push?route=our-room'), isA<OpenOurRoom>());
      expect(
        (target('synctogether://push?route=date-night') as OpenPath).path,
        '/lobby/pair/nights',
      );
      expect(
        (target('synctogether://push?route=watchlist') as OpenPath).path,
        '/lobby/pair/watchlist',
      );
      expect((target('synctogether://push?route=lobby') as OpenPath).path, '/lobby');
    });

    test('an unknown route, a missing one or another scheme is not a target', () {
      expect(target('synctogether://push?route=elsewhere'), isNull);
      expect(target('synctogether://push'), isNull);
      expect(target('synctogether://join/ABCDEF'), isNull);
      expect(target('https://x.example/push?route=our-room'), isNull);
    });

    test('the raw payload route maps the same way', () {
      expect(pushTargetForRoute('our-room'), isA<OpenOurRoom>());
      expect(pushTargetForRoute(null), isNull);
    });
  });
}
