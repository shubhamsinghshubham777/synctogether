import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/mock/mock_dependencies.dart';
import 'package:synctogether/pairing/pair_screen.dart';
import 'package:synctogether/pairing/pair_service.dart';
import 'package:synctogether/ui/loader.dart';
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

  testWidgets('unpairing on the open screen shows a fresh code, not a spinner', (tester) async {
    final fake = FakePairService(pair: samePairInfo());
    await _open(tester, fake);
    expect(find.text('Open Our Room'), findsOneWidget, reason: 'starts on the hub');
    expect(fake.calls, isNot(contains('createInvite')));

    await fake.unpair();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(fake.calls, contains('createInvite'), reason: 'the screen asked for a code itself');
    expect(find.text('M4YA7K'), findsOneWidget);
    expect(find.byType(PTLoader), findsNothing, reason: 'nothing left spinning');
  });

  testWidgets('the same when the partner is the one who unpaired', (tester) async {
    // Nothing on this screen was tapped: the pair simply disappeared under it.
    final fake = FakePairService(pair: samePairInfo());
    await _open(tester, fake);
    await fake.unpair();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('M4YA7K'), findsOneWidget);
  });

  testWidgets('a code that cannot be fetched offers another go instead of spinning', (
    tester,
  ) async {
    final fake = FakePairService(pair: samePairInfo(), failCreateInvite: true);
    await _open(tester, fake);
    await fake.unpair();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text("Couldn't get a code just now."), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.byType(PTLoader), findsNothing);

    fake.failCreateInvite = false;
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('M4YA7K'), findsOneWidget);
  });
}
