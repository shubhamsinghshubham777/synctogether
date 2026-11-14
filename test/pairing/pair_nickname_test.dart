import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/mock/mock_dependencies.dart';
import 'package:synctogether/pairing/pair_models.dart';
import 'package:synctogether/pairing/pair_screen.dart';
import 'package:synctogether/pairing/pair_service.dart';
import 'package:synctogether/ui/pt_theme.dart';

import '../support/fake_pair_service.dart';

Future<void> _open(WidgetTester tester, FakePairService fake) async {
  PairService.instance = fake;
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: buildPTTheme(), home: const PairScreen()));
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    installMockDependencies();
  });

  group('what I call my person', () {
    test('a nickname becomes the name everything shows, and their own stays known', () {
      final p = PairPartner.fromJson({
        'id': 'sam',
        'display_name': 'Sam Rivera',
        'nickname': 'Sammy',
      });
      expect(p.displayName, 'Sammy');
      expect(p.nickname, 'Sammy');
      expect(p.nameTheyChose, 'Sam Rivera');
    });

    test('no nickname, or a blank one, shows the name they chose', () {
      for (final nick in [null, '', '   ']) {
        final p = PairPartner.fromJson({
          'id': 'sam',
          'display_name': 'Sam Rivera',
          'nickname': nick,
        });
        expect(p.displayName, 'Sam Rivera', reason: 'nickname: "$nick"');
        expect(p.nickname, isNull);
      }
    });

    test('setting and clearing round-trips through withNickname', () {
      const p = PairPartner(id: 'sam', displayName: 'Sam Rivera');
      final named = p.withNickname(' Sammy ');
      expect(named.displayName, 'Sammy');
      expect(named.nameTheyChose, 'Sam Rivera');
      expect(named.withNickname(null).displayName, 'Sam Rivera');
      expect(named.withNickname('  ').nickname, isNull);
    });
  });

  testWidgets('the pencil by their name opens a rename, and saving shows the new name', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final fake = FakePairService(pair: samePairInfo());
    await _open(tester, fake);

    expect(find.text('Sam Rivera'), findsWidgets);
    await tester.tap(find.bySemanticsLabel('Rename Sam Rivera'));
    await tester.pumpAndSettle();

    expect(find.text('What do you call Sam Rivera?'), findsOneWidget);
    expect(find.textContaining('Only you see this'), findsOneWidget);
    expect(find.text('Use their name'), findsNothing, reason: 'nothing to undo yet');

    await tester.enterText(find.byType(TextField), 'Sammy');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(fake.calls, contains('setPartnerNickname:Sammy'));
    expect(find.text('Sammy'), findsWidgets);
    expect(find.text('Unpair from Sammy'), findsOneWidget, reason: 'it is used everywhere');
    semantics.dispose();
  });

  testWidgets('"Use their name" goes back to what they chose', (tester) async {
    final semantics = tester.ensureSemantics();
    final fake = FakePairService(
      pair: PairInfo(
        pairId: 'pair-1',
        since: DateTime.utc(2026, 3, 2),
        partner: const PairPartner(
          id: 'sam',
          displayName: 'Sammy',
          realName: 'Sam Rivera',
          nickname: 'Sammy',
        ),
      ),
    );
    await _open(tester, fake);

    await tester.tap(find.bySemanticsLabel('Rename Sammy'));
    await tester.pumpAndSettle();
    expect(find.text('What do you call Sam Rivera?'), findsOneWidget);

    await tester.tap(find.text('Use their name'));
    await tester.pumpAndSettle();
    expect(fake.calls, contains('setPartnerNickname:'));
    expect(find.text('Unpair from Sam Rivera'), findsOneWidget);
    semantics.dispose();
  });
}
