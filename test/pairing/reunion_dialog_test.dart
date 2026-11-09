import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/pairing/pair_lobby.dart';
import 'package:synctogether/pairing/pair_logic.dart';
import 'package:synctogether/pairing/pair_models.dart';
import 'package:synctogether/pairing/pair_screen.dart';
import 'package:synctogether/pairing/pair_service.dart';
import 'package:synctogether/ui/pt_theme.dart';

import '../support/fake_pair_service.dart';
import 'package:synctogether/mock/mock_dependencies.dart';

PairInfo _pair({String? setBy, bool shared = true, bool show = true}) => PairInfo(
  pairId: 'p',
  since: DateTime(2026),
  partner: const PairPartner(id: 'sam', displayName: 'Sam'),
  reunionOn: DateTime(2026, 12, 26),
  reunionLabel: 'Heathrow',
  reunionSetBy: setBy,
  reunionSharedEdit: shared,
  showReunion: show,
);

Future<void> _open(WidgetTester tester, PairInfo pair) async {
  PairService.instance = FakePairService(pair: pair);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildPTTheme(),
      home: Builder(
        builder: (context) =>
            ElevatedButton(onPressed: () => editReunion(context), child: const Text('open')),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    installMockDependencies();
  });

  testWidgets('the date has both switches and saves what they say', (tester) async {
    await _open(tester, _pair());
    expect(find.text('Show on the lobby'), findsOneWidget);
    expect(find.text('Either of us can edit'), findsOneWidget);
    await tester.tap(find.text('Either of us can edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect((PairService.instance as FakePairService).calls.last, startsWith('setReunion:'));
  });

  testWidgets('a date its partner keeps to themselves cannot be changed here', (tester) async {
    await _open(tester, _pair(setBy: 'sam', shared: false));
    expect(find.textContaining('keeps it to themselves'), findsOneWidget);
    expect(find.text('Either of us can edit'), findsNothing);
    expect(find.text('Clear'), findsNothing);
    expect(find.text('Done'), findsOneWidget);
    expect(
      find.text('Show on the lobby'),
      findsOneWidget,
      reason: 'the lobby choice is always mine',
    );
  });

  testWidgets('a shared date set by the other person can still be changed', (tester) async {
    await _open(tester, _pair(setBy: 'sam'));
    expect(find.textContaining('Either of you can change it'), findsOneWidget);
    expect(find.textContaining('keeps it to themselves'), findsNothing);
    expect(find.text('Clear'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('under eight days the card counts days and hours', (tester) async {
    final view = reunionView(DateTime(2026, 11, 13), DateTime(2026, 11, 9, 13));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPTTheme(),
        home: Scaffold(
          body: ReunionCard(view: view, label: 'Sam lands'),
        ),
      ),
    );
    expect(find.text('3'), findsOneWidget);
    expect(find.text('days'), findsOneWidget);
    expect(find.text('11'), findsOneWidget);
    expect(find.text('h'), findsOneWidget);
  });
}
