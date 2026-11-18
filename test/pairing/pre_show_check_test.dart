import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/av/system_permissions.dart';
import 'package:synctogether/mock/mock_dependencies.dart';
import 'package:synctogether/pairing/pair_models.dart';
import 'package:synctogether/pairing/pair_service.dart';
import 'package:synctogether/pairing/pre_show_check.dart';
import 'package:synctogether/pairing/pre_show_check_logic.dart';

import '../support/fake_pair_service.dart';
import '../support/fake_pre_show_probes.dart';

DateNight night({
  DateNightStatus status = DateNightStatus.accepted,
  Duration from = const Duration(minutes: 12),
}) => DateNight(
  id: 'tonight',
  title: 'Spirited Away',
  startsAt: DateTime.now().toUtc().add(from),
  proposedBy: 'sam',
  status: status,
);

void main() {
  late FakePairService pair;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    installMockDependencies();
    pair = PairService.instance = FakePairService(pair: samePairInfo(), nights: [night()]);
  });

  Future<void> pump(WidgetTester t, FakeProbes probes, {FilmCheck Function()? roomFilm}) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PreShowCheckPanel(
            probes: probes,
            roomFilm: roomFilm,
            onDone: () {},
            onLeaveForPage: (_) {},
          ),
        ),
      ),
    );
    await t.pump(); // the first reads land and rows change
    await t.pump(); // the folds start their clocks
    await t.pump(const Duration(milliseconds: 800));
  }

  testWidgets('nothing is asked just by opening it, and camera and mic offer a tap', (t) async {
    final p = FakeProbes();
    await pump(t, p);
    expect(find.text('Pre-show check'), findsOneWidget, reason: 'the page title');
    expect(find.text('Turn on camera'), findsOneWidget);
    expect(find.text('Turn on microphone'), findsOneWidget);
    expect(p.calls.where((c) => c.startsWith('request')), isEmpty);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a blocked camera says why and offers the settings page', (t) async {
    final p = FakeProbes(camera: PermissionState.blocked);
    await pump(t, p);
    expect(find.text("SyncTogether can't use your camera"), findsOneWidget);
    await t.tap(find.text('Open settings').first);
    await t.pump();
    expect(p.calls, contains('settings:camera'));
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a flagged row turns the button into Take our seats anyway', (t) async {
    final p = FakeProbes(camera: PermissionState.blocked);
    await pump(t, p);
    expect(find.text('Take our seats anyway'), findsOneWidget);
    expect(find.text('Take our seats'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('offline withholds the button entirely', (t) async {
    final p = FakeProbes(
      latency: const LatencyReading.failed(),
      network: const NetworkInfo(transport: NetworkTransport.none),
    );
    await pump(t, p);
    expect(find.text("You're offline"), findsOneWidget);
    expect(find.textContaining('Take our seats'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a night that moves while the sheet is open says so once', (t) async {
    await pump(t, FakeProbes());
    pair.setNights([night(from: const Duration(minutes: 72))]);
    await t.pump();
    await t.pump(const Duration(milliseconds: 800));
    expect(find.textContaining('moved the night to'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a night cancelled while the sheet is open clears it', (t) async {
    final p = FakeProbes(camera: PermissionState.granted);
    await pump(t, p);
    pair.setNights([night(status: DateNightStatus.cancelled)]);
    await t.pump();
    await t.pump(const Duration(milliseconds: 800));
    expect(find.textContaining('cancelled this date night'), findsOneWidget);
    expect(find.text('Plan another night'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a host\'s room check has film, sound and connection, and a Done button', (t) async {
    await pump(t, FakeProbes(), roomFilm: () => const FilmCheck(FilmKind.local, name: 'film.mkv'));
    expect(find.text('Room check'), findsOneWidget);
    expect(find.text('Camera'), findsNothing);
    expect(find.text('Microphone'), findsNothing);
    expect(find.text('Done'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
