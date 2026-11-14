import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/mock/mock_dependencies.dart';
import 'package:synctogether/pairing/pair_accept_screen.dart';
import 'package:synctogether/pairing/pair_models.dart';
import 'package:synctogether/pairing/pair_screen.dart';
import 'package:synctogether/pairing/pair_service.dart';
import 'package:synctogether/platform.dart';
import 'package:synctogether/profile/profile_models.dart';
import 'package:synctogether/profile/profile_service.dart';
import 'package:synctogether/rewards/rewards_service.dart';
import 'package:synctogether/rooms/lobby_screen.dart';

import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/pt_motion.dart';

import '../support/fake_pair_service.dart';
import '../support/screen_matrix.dart';
import 'layout_support.dart';

/// An account Sign in with Apple gave no name to: the name is the relay
/// address's random local part.
class _AppleHiddenEmailProfile extends MockProfileService {
  @override
  Profile? get profile => const Profile(
    id: 'me',
    displayName: '68tgy66wnh',
    isGuest: false,
    email: '68tgy66wnh@privaterelay.appleid.com',
  );
}

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

  DateNight soon({String? link}) => DateNight(
    id: 'n1',
    title: 'Spirited Away',
    startsAt: DateTime.now().toUtc().add(const Duration(minutes: 10)),
    proposedBy: 'sam',
    status: DateNightStatus.accepted,
    attachKind: link == null ? 'none' : 'youtube',
    youtubeUrl: link,
  );

  screenMatrix('pair/lobby-night-ready', (tester, c, s) async {
    PairService.instance = FakePairService(
      pair: samePairInfo(patron: true),
      online: true,
      nights: [soon(link: 'https://www.youtube.com/watch?v=ByXuk9QqQkk')],
    );
    await lobby(tester, c, s);
    expect(find.text('Your movie is ready'), findsOneWidget);
    expect(find.textContaining('DATE NIGHT'), findsOneWidget);
    await finishCase(tester);
  });

  screenMatrix('pair/lobby-night-nothing-attached', (tester, c, s) async {
    PairService.instance = FakePairService(
      pair: samePairInfo(patron: true),
      online: true,
      nights: [soon()],
    );
    await lobby(tester, c, s);
    expect(find.text('Your movie is ready'), findsNothing, reason: 'never promised early');
    await finishCase(tester);
  });

  screenMatrix('pair/lobby-offline', (tester, c, s) async {
    PairService.instance = FakePairService(pair: samePairInfo());
    await lobby(tester, c, s);
    expect(find.text('Open Our Room'), findsOneWidget);
    expect(find.textContaining('Call Sam'), findsNothing, reason: 'no ring when they are away');
    // "Your person ›" belongs at the card's right edge, in line with the button
    // beneath it - not wherever its half of a shared row happens to start.
    final chevron = find.descendant(
      of: find.ancestor(of: find.text('Your person'), matching: find.byType(PTPressable)),
      matching: find.byType(Icon),
    );
    final button = find.widgetWithText(PTButton, 'Open Our Room');
    expect(
      (tester.getTopRight(chevron).dx - tester.getTopRight(button).dx).abs(),
      lessThan(2),
      reason: 'the link sits flush right',
    );
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
    await tester.ensureVisible(find.text('Send invite'));
    expect(find.text('Send invite'), findsOneWidget, reason: 'the email option is on the page');
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

  screenMatrix('pair/accept-asks-for-a-name', (tester, c, s) async {
    ProfileService.instance = _AppleHiddenEmailProfile();
    PairService.instance = FakePairService(preview: _invite());
    await pumpAtSize(
      tester,
      const PairAcceptScreen(code: 'M4YA7K'),
      c,
      textScale: s,
      singlePane: true,
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('What should your person call you?'), findsOneWidget);
    expect(find.text('Pair with Sam Rivera'), findsOneWidget);
    await finishCase(tester);
  });

  screenMatrix('pair/invite-has-a-code-box', (tester, c, s) async {
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
    await tester.ensureVisible(find.text('Pair with this code'));
    expect(find.text('GOT A CODE FROM YOUR PERSON?'), findsOneWidget);
    expect(find.textContaining('hide their email with Apple'), findsOneWidget);
    await finishCase(tester);
  });

  screenMatrix('pair/hub-free-pair-sees-patron-note', (tester, c, s) async {
    canSellPremiumOverride = true;
    addTearDown(() => canSellPremiumOverride = null);
    PairService.instance = FakePairService(pair: samePairInfo());
    await pumpAtSize(tester, const PairScreen(), c, textScale: s, singlePane: true);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.ensureVisible(find.text('See Patron'));
    expect(find.text('See Patron'), findsOneWidget);
    await finishCase(tester);
  });

  screenMatrix('pair/hub-patron-pair-has-no-note', (tester, c, s) async {
    canSellPremiumOverride = true;
    addTearDown(() => canSellPremiumOverride = null);
    PairService.instance = FakePairService(pair: samePairInfo(patron: true));
    await pumpAtSize(tester, const PairScreen(), c, textScale: s, singlePane: true);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('See Patron'), findsNothing, reason: 'one seat already covers both');
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

  screenMatrix('pair/accept-already-paired', (tester, c, s) async {
    PairService.instance = FakePairService(pair: samePairInfo(), preview: _invite());
    await pumpAtSize(
      tester,
      const PairAcceptScreen(code: 'M4YA7K'),
      c,
      textScale: s,
      singlePane: true,
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(PairErrorCode.alreadyPaired.message), findsOneWidget);
    expect(find.text('Pair with Sam Rivera'), findsNothing, reason: 'a button that can only fail');
    await finishCase(tester);
  });

  screenMatrix('pair/accept-partner-paired', (tester, c, s) async {
    PairService.instance = FakePairService(
      preview: PairInvite(
        code: 'M4YA7K',
        inviter: const PairPartner(id: 'sam', displayName: 'Sam Rivera'),
        inviterPaired: true,
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 40)),
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
    expect(find.text(PairErrorCode.partnerAlreadyPaired.message), findsOneWidget);
    expect(find.text('Pair with Sam Rivera'), findsNothing);
    await finishCase(tester);
  });
}
