import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/mock/mock_dependencies.dart';
import 'package:synctogether/pairing/pair_models.dart';
import 'package:synctogether/pairing/pair_screen.dart';
import 'package:synctogether/pairing/pair_service.dart';
import 'package:synctogether/ui/pt_theme.dart';

import '../support/fake_pair_service.dart';

PairInvite _mine() => PairInvite(
  code: 'M4YA7K',
  inviter: const PairPartner(id: 'me', displayName: 'You'),
  expiresAt: DateTime.now().toUtc().add(const Duration(hours: 46)),
  isMine: true,
);

Future<void> _open(WidgetTester tester, FakePairService fake) async {
  PairService.instance = fake;
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: buildPTTheme(), home: const PairScreen()));
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  setUp(installMockDependencies);

  testWidgets('sending to an address says only "on its way, if that address has an account"', (
    tester,
  ) async {
    final fake = FakePairService(sent: _mine());
    await _open(tester, fake);

    await tester.enterText(find.byKey(const ValueKey('pair-email')), 'sam@example.test');
    await tester.tap(find.text('Send invite'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(fake.calls, contains('inviteByEmail:sam@example.test'));
    expect(find.textContaining('Invite on its way'), findsOneWidget);
    expect(
      find.textContaining('not found'),
      findsNothing,
      reason: 'no hint about whether it matched',
    );
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('pair-email'))).controller!.text,
      isEmpty,
      reason: 'the address is cleared after sending',
    );
  });

  testWidgets('a refused address shows friendly copy, never a raw code', (tester) async {
    final fake = FakePairService(sent: _mine(), failInviteWith: Exception('invalid_email'));
    await _open(tester, fake);

    await tester.enterText(find.byKey(const ValueKey('pair-email')), 'nonsense');
    await tester.tap(find.text('Send invite'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(PairErrorCode.invalidEmail.message), findsOneWidget);
    expect(find.textContaining('invalid_email'), findsNothing);
    expect(find.textContaining('Invite on its way'), findsNothing);
  });

  testWidgets('hitting the daily limit points at the link instead', (tester) async {
    final fake = FakePairService(sent: _mine(), failInviteWith: Exception('too_many_invites'));
    await _open(tester, fake);

    await tester.enterText(find.byKey(const ValueKey('pair-email')), 'a@example.test');
    await tester.tap(find.text('Send invite'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(PairErrorCode.tooManyInvites.message), findsOneWidget);
  });
}
