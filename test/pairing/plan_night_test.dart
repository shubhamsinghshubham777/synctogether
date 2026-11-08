import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/mock/mock_dependencies.dart';
import 'package:synctogether/pairing/date_night_plan.dart';
import 'package:synctogether/pairing/pair_service.dart';
import 'package:synctogether/ui/pt_theme.dart';

import '../support/fake_pair_service.dart';

Future<FakePairService> _open(WidgetTester tester, {String? zone = 'America/New_York'}) async {
  final fake = FakePairService(pair: samePairInfo(patron: true, partnerZone: zone));
  PairService.instance = fake;
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: buildPTTheme(), home: const PlanNightScreen()));
  await tester.pump(const Duration(milliseconds: 400));
  return fake;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    installMockDependencies();
  });

  group('the time block', () {
    testWidgets('two different clocks get the strips, the other person named', (tester) async {
      await _open(tester);
      expect(find.text('BOTH OF YOU, SIDE BY SIDE'), findsOneWidget);
      expect(find.textContaining('New York'), findsWidgets);
    });

    testWidgets('one clock is one plain line, with no strips and no offset', (tester) async {
      await _open(tester, zone: null);
      expect(find.text('BOTH OF YOU, SIDE BY SIDE'), findsNothing);
      expect(find.text('00'), findsNothing, reason: 'no 24-hour axis');
      expect(find.textContaining('Both of you'), findsNothing);
    });
  });

  group('lateness never blocks, it only changes the wording', () {
    test('a small hour for them says "Send anyway"', () {
      final form = PlanNightController(samePairInfo(patron: true, partnerZone: 'Asia/Kolkata'));
      form.when = DateTime.utc(2030, 1, 1, 21, 30).toLocal(); // 3:00 AM in Kolkata
      expect(form.lateForThem, isTrue);
      expect(form.sendLabel, 'Send anyway');
      form.dispose();
    });

    test('an afternoon for them is the plain "Send to Sam"', () {
      final form = PlanNightController(samePairInfo(patron: true, partnerZone: 'Asia/Kolkata'));
      form.when = DateTime.utc(2030, 1, 1, 10).toLocal(); // 3:30 PM in Kolkata
      expect(form.lateForThem, isFalse);
      expect(form.sendLabel, 'Send to Sam');
      form.dispose();
    });
  });

  group('what you are watching', () {
    testWidgets('"we will choose together" is the default and sends no link', (tester) async {
      final fake = await _open(tester);
      await tester.enterText(find.byType(TextField).first, 'Past Lives');
      await tester.tap(find.text('Send to Sam'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(fake.calls, contains('planNight:Past Lives:'));
    });

    testWidgets('a link is checked once typing pauses, then sent in one canonical shape', (
      tester,
    ) async {
      final fake = await _open(tester);
      await tester.enterText(find.byType(TextField).first, 'Spirited Away');
      await tester.tap(find.text('A YouTube link'));
      await tester.pump(const Duration(milliseconds: 300));

      final field = find.byType(TextField).last;
      await tester.enterText(field, 'youtube.com/shorts');
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        find.textContaining("doesn't look like a YouTube link"),
        findsNothing,
        reason: 'a half-typed address is not an error yet',
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.textContaining("doesn't look like a YouTube link"), findsOneWidget);

      await tester.enterText(field, 'https://youtu.be/ByXuk9QqQkk');
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Found it. This plays for both of you.'), findsOneWidget);

      await tester.tap(find.text('Send to Sam'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        fake.calls,
        contains('planNight:Spirited Away:https://www.youtube.com/watch?v=ByXuk9QqQkk'),
      );
    });

    testWidgets('sending with a bad link sends nothing', (tester) async {
      final fake = await _open(tester);
      await tester.enterText(find.byType(TextField).first, 'Spirited Away');
      await tester.tap(find.text('A YouTube link'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField).last, 'not a link');
      await tester.tap(find.text('Send to Sam'));
      await tester.pump(const Duration(milliseconds: 700));
      expect(fake.calls.where((c) => c.startsWith('planNight')), isEmpty);
      expect(find.textContaining("doesn't look like a YouTube link"), findsOneWidget);
    });

    testWidgets('a night with no name is not sent', (tester) async {
      final fake = await _open(tester);
      await tester.tap(find.text('Send to Sam'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(fake.calls.where((c) => c.startsWith('planNight')), isEmpty);
      expect(find.text('Give the night a name first.'), findsOneWidget);
    });
  });
}
