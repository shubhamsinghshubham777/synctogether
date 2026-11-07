import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/mock/mock_dependencies.dart';
import 'package:synctogether/pairing/pair_accept_screen.dart';
import 'package:synctogether/pairing/pair_models.dart';
import 'package:synctogether/pairing/pair_screen.dart';
import 'package:synctogether/pairing/pair_service.dart';
import 'package:synctogether/rewards/rewards_service.dart';
import 'package:synctogether/rooms/lobby_screen.dart';

import '../support/fake_pair_service.dart';
import '../support/screen_matrix.dart';
import 'layout_support.dart';

PairInvite _invite() => PairInvite(
  code: 'M4YA7K',
  inviter: const PairPartner(id: 'sam', displayName: 'Sam Rivera'),
  expiresAt: DateTime.now().toUtc().add(const Duration(hours: 40)),
  createdAt: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    installMockDependencies();
    RewardsService.instance = FakeRewardsService();
  });

  Future<void> lobby(WidgetTester tester, ScreenCase c, double s) async {
    await pumpAtSize(
      tester,
      const LobbyScreen(),
      c,
      textScale: s,
      singlePane: true,
      twoPaneBook: true,
    );
    await tester.pump(const Duration(milliseconds: 1500));
  }

  screenMatrix('pair/lobby-online', (tester, c, s) async {
    PairService.instance = FakePairService(
      pair: samePairInfo(
        reunionOn: DateTime.now().add(const Duration(days: 47)),
        reunionLabel: 'Sam lands at Heathrow',
      ),
      online: true,
    );
    await lobby(tester, c, s);
    expect(find.text('Open Our Room'), findsWidgets);
    expect(find.textContaining('Call Sam'), findsOneWidget);
    expect(find.text('47'), findsOneWidget);
    await finishCase(tester);
  });

  screenMatrix('pair/lobby-offline', (tester, c, s) async {
    PairService.instance = FakePairService(pair: samePairInfo());
    await lobby(tester, c, s);
    expect(find.text('Open Our Room'), findsOneWidget);
    expect(find.textContaining('Call Sam'), findsNothing, reason: 'no ring when they are away');
    await finishCase(tester);
  });

  screenMatrix('pair/lobby-request', (tester, c, s) async {
    PairService.instance = FakePairService(pending: _invite());
    await lobby(tester, c, s);
    expect(find.textContaining('wants to pair with you'), findsOneWidget);
    expect(find.text('Pair'), findsOneWidget);
    await finishCase(tester);
  });

  screenMatrix('pair/lobby-teaser', (tester, c, s) async {
    PairService.instance = FakePairService();
    await lobby(tester, c, s);
    expect(find.text('Watching with your person?'), findsOneWidget);
    await finishCase(tester);
  });

  screenMatrix('pair/lobby-guest', (tester, c, s) async {
    PairService.instance = FakePairService(account: false);
    await lobby(tester, c, s);
    expect(
      find.text('Watching with your person?'),
      findsNothing,
      reason: 'guests see no pairing UI',
    );
    expect(find.text('Open Our Room'), findsNothing);
    await finishCase(tester);
  });

  screenMatrix('pair/hub', (tester, c, s) async {
    PairService.instance = FakePairService(
      pair: samePairInfo(reunionOn: DateTime.now().add(const Duration(days: 47))),
      online: true,
      stats: const PairStats(streakWeeks: 12),
    );
    await pumpAtSize(tester, const PairScreen(), c, textScale: s, singlePane: true);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Open Our Room'), findsOneWidget);
    expect(find.text('Unpair from Sam Rivera'), findsOneWidget);
    await finishCase(tester);
  });

  screenMatrix('pair/invite', (tester, c, s) async {
    PairService.instance = FakePairService(
      sent: PairInvite(
        code: 'M4YA7K',
        inviter: const PairPartner(id: 'me', displayName: 'You'),
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 46)),
        isMine: true,
      ),
    );
    await pumpAtSize(tester, const PairScreen(), c, textScale: s, singlePane: true);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('M4YA7K'), findsOneWidget);
    expect(find.text('Share invite'), findsOneWidget);
    expect(find.text('Copy code'), findsOneWidget);
    await finishCase(tester);
  });

  screenMatrix('pair/guest', (tester, c, s) async {
    PairService.instance = FakePairService(account: false);
    await pumpAtSize(tester, const PairScreen(), c, textScale: s, singlePane: true);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Pairing lives on an account'), findsOneWidget);
    await finishCase(tester);
  });

  screenMatrix('pair/accept', (tester, c, s) async {
    PairService.instance = FakePairService(preview: _invite());
    await pumpAtSize(
      tester,
      const PairAcceptScreen(code: 'M4YA7K'),
      c,
      textScale: s,
      singlePane: true,
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Sam Rivera wants to pair with you'), findsOneWidget);
    expect(find.text('Pair with Sam Rivera'), findsOneWidget);
    await finishCase(tester);
  });

  screenMatrix('pair/accept-expired', (tester, c, s) async {
    PairService.instance = FakePairService(
      preview: PairInvite(
        code: 'M4YA7K',
        inviter: const PairPartner(id: 'sam', displayName: 'Sam Rivera'),
        status: PairInviteStatus.expired,
        expiresAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
      ),
    );
    await pumpAtSize(
      tester,
      const PairAcceptScreen(code: 'M4YA7K'),
      c,
      textScale: s,
      singlePane: true,
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(PairErrorCode.inviteExpired.message), findsOneWidget);
    expect(find.text('Pair with Sam Rivera'), findsNothing);
    await finishCase(tester);
  });
}
