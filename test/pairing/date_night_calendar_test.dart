import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/mock/mock_dependencies.dart';
import 'package:synctogether/pairing/calendar_bridge.dart';
import 'package:synctogether/pairing/date_night_screen.dart';
import 'package:synctogether/pairing/pair_models.dart';
import 'package:synctogether/pairing/pair_service.dart';
import 'package:synctogether/ui/pt_theme.dart';

import '../support/fake_pair_service.dart';

class _Calendar implements CalendarBridge {
  _Calendar(this.answer);
  final CalendarResult answer;
  final added = <({String title, DateTime start, DateTime end, String? notes})>[];

  @override
  Future<CalendarResult> addEvent({
    required String title,
    required DateTime start,
    required DateTime end,
    String? notes,
  }) async {
    added.add((title: title, start: start, end: end, notes: notes));
    return answer;
  }
}

void main() {
  late DateTime start;

  setUp(() {
    installMockDependencies();
    start = DateTime.now().toUtc().add(const Duration(days: 3));
    PairService.instance = FakePairService(
      pair: samePairInfo(patron: true),
      nights: [
        DateNight(
          id: 'n1',
          title: 'Spirited Away',
          startsAt: start,
          proposedBy: 'sam',
          status: DateNightStatus.accepted,
        ),
      ],
    );
  });

  tearDown(() => calendarBridge = ChannelCalendarBridge());

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: buildPTTheme(), home: const DateNightScreen()));
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('the system calendar gets the night, two hours long, with the title', (tester) async {
    final bridge = _Calendar(CalendarResult.added);
    calendarBridge = bridge;
    await open(tester);

    await tester.tap(find.text('Add to calendar'));
    await tester.pump(const Duration(milliseconds: 300));

    final call = bridge.added.single;
    expect(call.title, 'Date night: Spirited Away');
    expect(call.start, start);
    expect(call.end, start.add(const Duration(hours: 2)));
    expect(call.notes, contains('Sam'));
    expect(find.text('Added to your calendar.'), findsOneWidget);
  });

  testWidgets('a dismissed sheet is not announced as success', (tester) async {
    calendarBridge = _Calendar(CalendarResult.dismissed);
    await open(tester);

    await tester.tap(find.text('Add to calendar'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Added to your calendar.'), findsNothing);
  });

  testWidgets('with no native calendar it falls back to sharing a file, without crashing', (
    tester,
  ) async {
    final bridge = _Calendar(CalendarResult.unsupported);
    calendarBridge = bridge;
    await open(tester);

    await tester.tap(find.text('Add to calendar'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(bridge.added, hasLength(1), reason: 'the native route is tried first');
    expect(find.text('Added to your calendar.'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
