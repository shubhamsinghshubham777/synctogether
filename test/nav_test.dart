import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:synctogether/nav.dart';

/// The app's route table shape (lobby with nested sub-pages) over stub pages.
GoRouter _router(String initial) {
  Widget page(String name, {List<Widget> actions = const []}) => Scaffold(
    body: Column(
      children: [
        Text('page:$name'),
        ...actions,
        Builder(
          builder: (context) => TextButton(
            key: Key('$name-back'),
            onPressed: () => goBack(context),
            child: const Text('back'),
          ),
        ),
      ],
    ),
  );
  Widget open(String key, String path) => Builder(
    builder: (context) =>
        TextButton(key: Key(key), onPressed: () => openPage(context, path), child: Text(key)),
  );
  return GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
        path: '/lobby',
        builder: (_, _) => page(
          'lobby',
          actions: [
            open('to-profile', '/lobby/profile'),
            open('to-leaderboard', '/lobby/leaderboard'),
          ],
        ),
        routes: [
          GoRoute(
            path: 'profile',
            builder: (_, _) => page(
              'profile',
              actions: [
                open('to-leaderboard', '/lobby/leaderboard'),
                open('to-subscribe', '/lobby/subscribe?source=profile'),
              ],
            ),
          ),
          GoRoute(
            path: 'leaderboard',
            builder: (_, _) => page('leaderboard', actions: [open('to-profile', '/lobby/profile')]),
          ),
          GoRoute(path: 'subscribe', builder: (_, _) => page('subscribe')),
          GoRoute(path: 'room/:id', builder: (_, _) => page('room')),
        ],
      ),
    ],
  );
}

Future<GoRouter> _pump(WidgetTester tester, String initial) async {
  final router = _router(initial);
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  return router;
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void _on(String name) => expect(find.text('page:$name'), findsOneWidget, reason: 'on $name');

void main() {
  testWidgets('lobby -> leaderboard -> profile: back retraces', (tester) async {
    final router = await _pump(tester, '/lobby');
    await _tap(tester, 'to-leaderboard');
    await _tap(tester, 'to-profile');
    _on('profile');
    await _tap(tester, 'profile-back');
    _on('leaderboard');
    await _tap(tester, 'leaderboard-back');
    _on('lobby');
    expect(router.canPop(), isFalse);
  });

  testWidgets('lobby -> profile -> subscribe: back retraces', (tester) async {
    await _pump(tester, '/lobby');
    await _tap(tester, 'to-profile');
    await _tap(tester, 'to-subscribe');
    _on('subscribe');
    await _tap(tester, 'subscribe-back');
    _on('profile');
    await _tap(tester, 'profile-back');
    _on('lobby');
  });

  testWidgets('openPage pops to an existing page instead of stacking', (tester) async {
    final router = await _pump(tester, '/lobby');
    await _tap(tester, 'to-profile');
    await _tap(tester, 'to-leaderboard');
    expect(pageStackPaths(router), ['/lobby', '/lobby/profile', '/lobby/leaderboard']);
    await _tap(tester, 'to-profile'); // from leaderboard
    _on('profile');
    expect(pageStackPaths(router), ['/lobby', '/lobby/profile']);
    await _tap(tester, 'profile-back');
    _on('lobby');
  });

  testWidgets('openPage on the page already on top is a no-op', (tester) async {
    final router = await _pump(tester, '/lobby');
    await _tap(tester, 'to-profile');
    final context = tester.element(find.text('page:profile'));
    openPage(context, '/lobby/profile?x=1');
    await tester.pumpAndSettle();
    expect(pageStackPaths(router), ['/lobby', '/lobby/profile']);
  });

  testWidgets('cold start on a sub-page: back reaches the lobby', (tester) async {
    await _pump(tester, '/lobby/profile');
    _on('profile');
    await _tap(tester, 'profile-back');
    _on('lobby');
  });

  testWidgets('goBack falls back when the stack is a single page', (tester) async {
    final router = await _pump(tester, '/lobby');
    router.go('/lobby/subscribe');
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();
    _on('lobby');
    final context = tester.element(find.text('page:lobby'));
    goBack(context, fallback: '/lobby/leaderboard');
    await tester.pumpAndSettle();
    _on('leaderboard');
  });

  testWidgets('a subscribe pushed from a room returns to the room', (tester) async {
    final router = await _pump(tester, '/lobby');
    router.go('/lobby/room/r1');
    await tester.pumpAndSettle();
    router.push('/lobby/subscribe?source=reaction_lock');
    await tester.pumpAndSettle();
    await _tap(tester, 'subscribe-back');
    _on('room');
  });

  testWidgets('leaving via go(/lobby) still shrinks the stack', (tester) async {
    final router = await _pump(tester, '/lobby');
    router.go('/lobby/room/r1');
    await tester.pumpAndSettle();
    router.go('/lobby');
    await tester.pumpAndSettle();
    _on('lobby');
    expect(router.canPop(), isFalse);
  });

  testWidgets('system back pops the same way as the back button', (tester) async {
    await _pump(tester, '/lobby');
    await _tap(tester, 'to-leaderboard');
    await _tap(tester, 'to-profile');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    _on('leaderboard');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    _on('lobby');
  });

  test('pagesAbove', () {
    const stack = ['/lobby', '/lobby/profile', '/lobby/leaderboard'];
    expect(pagesAbove(stack, '/lobby/leaderboard'), 0);
    expect(pagesAbove(stack, '/lobby/profile'), 1);
    expect(pagesAbove(stack, '/lobby'), 2);
    expect(pagesAbove(stack, '/lobby/subscribe'), isNull);
  });
}
