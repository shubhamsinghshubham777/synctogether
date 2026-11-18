import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/mock/mock_dependencies.dart';
import 'package:synctogether/pairing/push_service.dart';
import 'package:synctogether/rooms/widgets/seat_taken_host.dart';

import '../pairing/push_service_test.dart' show FakeBridge;

const _id = '4a90e947-e18a-4348-b74e-d96c354d5bf1';
const _route = '/lobby/room/$_id';

ForegroundPush _push({String kind = 'seat_taken', String route = _route}) => ForegroundPush(
  kind: kind,
  title: 'Priya took a seat',
  body: 'Friday Horror Club has someone waiting. Tap to join them.',
  route: route,
);

void main() {
  late FakeBridge bridge;
  late GoRouter router;
  late List<String> joined;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    installMockDependencies();
    bridge = FakeBridge();
    PushService.instance = PushService(
      bridge: bridge,
      register: (_) async {},
      unregister: (_) async {},
    );
    joined = [];
  });

  Future<void> pumpHost(WidgetTester t, {String at = '/lobby'}) async {
    await PushService.instance.start();
    router = GoRouter(
      initialLocation: at,
      routes: [
        GoRoute(
          path: '/lobby',
          builder: (_, _) => const Scaffold(body: Text('lobby')),
        ),
        GoRoute(
          path: '/lobby/room/:id',
          builder: (_, _) => const Scaffold(body: Text('room')),
        ),
      ],
    );
    await t.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        builder: (context, child) =>
            SeatTakenHost(router: router, onJoin: (id) async => joined.add(id), child: child!),
      ),
    );
    await t.pump();
  }

  Future<void> settle(WidgetTester t) async {
    await t.pump(); // the event, and the fold's controller starting
    await t.pump(); // the fold's first tick sets its clock
    await t.pump(const Duration(milliseconds: 600));
  }

  testWidgets('a seat taken while the app is open becomes a banner with Join', (t) async {
    await pumpHost(t);
    expect(find.text('Priya took a seat'), findsNothing);
    bridge.foregroundController.add(_push());
    await settle(t);
    expect(find.text('Priya took a seat'), findsOneWidget);
    expect(find.text('Friday Horror Club has someone waiting.'), findsOneWidget);
    await t.tap(find.text('Join'));
    await settle(t);
    expect(joined, [_id]);
    await t.pump(const Duration(seconds: 13)); // the banner's own timer must not outlive the test
  });

  testWidgets('it does not announce the room you are already in', (t) async {
    await pumpHost(t, at: _route);
    bridge.foregroundController.add(_push());
    await settle(t);
    expect(find.text('Priya took a seat'), findsNothing);
  });

  testWidgets('other kinds and malformed routes are left alone', (t) async {
    await pumpHost(t);
    bridge.foregroundController
      ..add(_push(kind: 'reunion'))
      ..add(_push(route: 'our-room'))
      ..add(_push(route: '/lobby/room/nope'));
    await settle(t);
    expect(find.text('Priya took a seat'), findsNothing);
  });

  testWidgets('it folds away on its own', (t) async {
    await pumpHost(t);
    bridge.foregroundController.add(_push());
    await settle(t);
    expect(find.text('Priya took a seat'), findsOneWidget);
    await t.pump(const Duration(seconds: 13));
    await settle(t);
    expect(find.text('Priya took a seat'), findsNothing);
  });
}
