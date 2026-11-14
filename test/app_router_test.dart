import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:synctogether/app_router.dart';
import 'package:synctogether/ui/not_found_screen.dart';

void main() {
  group('room path helpers', () {
    test('the prefix keeps rooms nested under the lobby', () {
      expect(kRoomPathPrefix, '/lobby/room/');
      expect(kRoomPathPrefix.startsWith('/lobby/'), isTrue);
    });

    test('roomPath and roomIdOfPath are inverses', () {
      const ids = [
        'r1',
        '550e8400-e29b-41d4-a716-446655440000',
        'ABC123',
        'a',
        '0',
        'id-with-dashes',
        'id_with_underscores',
        'id.with.dots',
      ];
      for (final id in ids) {
        expect(roomIdOfPath(roomPath(id)), id, reason: id);
      }
    });

    test('roomPath builds the nested location', () {
      expect(roomPath('r1'), '/lobby/room/r1');
    });

    test('non-room locations read as not-in-a-room', () {
      expect(roomIdOfPath('/lobby'), isNull);
      expect(roomIdOfPath('/login'), isNull);
      expect(roomIdOfPath('/lobby/profile'), isNull);
      expect(roomIdOfPath('/'), isNull);
      expect(roomIdOfPath(''), isNull);
      expect(roomIdOfPath('/room/r1'), isNull);
      expect(roomIdOfPath('lobby/room/r1'), isNull);
    });

    test('a prefix with no id reads as an empty id, not as null', () {
      expect(roomIdOfPath('/lobby/room/'), '');
    });

    test('ids containing odd characters survive the round trip verbatim', () {
      const odd = ['id with spaces', 'id/with/slashes', 'id?with=query', 'id#frag', 'ID%20enc'];
      for (final id in odd) {
        expect(roomIdOfPath(roomPath(id)), id, reason: id);
      }
    });

    test('a trailing segment stays part of the id rather than being split off', () {
      expect(roomIdOfPath('/lobby/room/r1/extra'), 'r1/extra');
    });
  });

  group('app-scheme links', () {
    test('only the synctogether scheme is treated as a link', () {
      expect(isAppSchemeLink(Uri.parse('synctogether://join/ABC123')), isTrue);
      expect(isAppSchemeLink(Uri.parse('synctogether://auth-callback?code=x')), isTrue);
      expect(isAppSchemeLink(Uri.parse('/lobby')), isFalse);
      expect(isAppSchemeLink(Uri.parse('/lobby/room/r1')), isFalse);
      expect(isAppSchemeLink(Uri.parse('https://synctogether.app/join/ABC123')), isFalse);
    });

    test('the fallback is the current location, or the lobby when nothing is shown', () {
      expect(locationForAppSchemeLink(null), '/lobby');
      expect(
        locationForAppSchemeLink(Uri.parse('/lobby/room/r1?chat=true')),
        '/lobby/room/r1?chat=true',
      );
    });

    // The real router needs a live Supabase client, so this drives a router
    // wired with the same redirect shape: the link must not produce a
    // "Page Not Found", and must not move the user off their current page.
    testWidgets('a link arriving as a location keeps the current page', (tester) async {
      late final GoRouter router;
      router = GoRouter(
        initialLocation: '/lobby/room/r1',
        redirect: (context, state) {
          if (!isAppSchemeLink(state.uri)) return null;
          final config = router.routerDelegate.currentConfiguration;
          return locationForAppSchemeLink(config.isEmpty ? null : config.uri);
        },
        routes: [
          GoRoute(
            path: '/lobby',
            builder: (_, _) => const Text('lobby', textDirection: TextDirection.ltr),
          ),
          GoRoute(
            path: '/lobby/room/:id',
            builder: (_, s) =>
                Text('room ${s.pathParameters['id']}', textDirection: TextDirection.ltr),
          ),
        ],
      );
      await tester.pumpWidget(
        WidgetsApp.router(routerConfig: router, color: const Color(0xFF000000)),
      );
      await tester.pumpAndSettle();
      expect(find.text('room r1'), findsOneWidget);

      router.go('synctogether://join/ABC123');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('room r1'), findsOneWidget);
      expect(router.routerDelegate.currentConfiguration.uri.path, '/lobby/room/r1');
    });
  });

  group('unmatched locations', () {
    testWidgets('render the in-app Not Found screen and lead back to the lobby', (tester) async {
      final router = GoRouter(
        initialLocation: '/lobby',
        errorBuilder: notFoundBuilder,
        routes: [
          GoRoute(
            path: '/lobby',
            builder: (_, _) => const Text('lobby', textDirection: TextDirection.ltr),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router, theme: ThemeData.dark()));
      await tester.pumpAndSettle();
      expect(find.text('lobby'), findsOneWidget);

      // A query is present on purpose: it must not reach the screen.
      router.go('/definitely/not/a/route?access_token=secret');
      await tester.pumpAndSettle();
      expect(find.byType(NotFoundScreen), findsOneWidget);
      expect(find.text('Lost in sync'), findsOneWidget);
      expect(
        tester.widget<NotFoundScreen>(find.byType(NotFoundScreen)).location,
        '/definitely/not/a/route',
      );
      expect(find.textContaining('GoException'), findsNothing);

      await tester.tap(find.text('Back to lobby'));
      await tester.pumpAndSettle();
      expect(find.text('lobby'), findsOneWidget);
    });
  });
}
