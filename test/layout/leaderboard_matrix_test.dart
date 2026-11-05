import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/profile/entitlement_service.dart';
import 'package:synctogether/profile/profile_models.dart';
import 'package:synctogether/profile/profile_service.dart';
import 'package:synctogether/rewards/leaderboard_screen.dart';
import 'package:synctogether/rewards/rewards_models.dart';
import 'package:synctogether/rewards/rewards_service.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/cinema_marquee_bar.dart';
import 'package:synctogether/ui/booth_icons.g.dart';

import '../support/screen_matrix.dart';
import 'layout_support.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ProfileService.instance.setProfileForTesting(
      const Profile(id: 'user-alex', displayName: 'Alex Rivers', isGuest: false),
    );
    EntitlementService.instance.setLimitsForTesting(TierLimits.fallback);
  });
  tearDown(() {
    ProfileService.instance.setProfileForTesting(null);
    EntitlementService.instance.setLimitsForTesting(null);
  });

  screenMatrix('leaderboard/circle', (tester, c, s) async {
    RewardsService.instance = FakeRewardsService();
    await pumpAtSize(tester, const LeaderboardScreen(), c, textScale: s);
    // The board arrives a frame after the first pump and deals its rows in;
    // capture the settled board, not the first frame of the stagger.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 400));
    await finishCase(tester);
  });

  screenMatrix('leaderboard/guest', (tester, c, s) async {
    RewardsService.instance = FakeRewardsService(
      fakeState: const RewardState(tier: 'guest'),
      rows: const [],
    );
    await pumpAtSize(tester, const LeaderboardScreen(), c, textScale: s);
    // The board arrives a frame after the first pump and deals its rows in;
    // capture the settled board, not the first frame of the stagger.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 400));
    await finishCase(tester);
  });

  // With the global board open there are two tab groups (scope and period).
  // Side by side they used to ellipsize each other on a phone into "Your ..."
  // and "WE...", which expectNoOverflow cannot see - so assert on the text.
  screenMatrix('leaderboard/open-board-tabs', (tester, c, s) async {
    RewardsService.instance = FakeRewardsService(
      fakeState: const RewardState(
        publicProfile: true,
        streak: StreakState(current: 12, longest: 12),
        circleRank: 2,
        globalBoard: GlobalBoardStatus(open: true, participants: 340),
      ),
    );
    await pumpAtSize(tester, const LeaderboardScreen(), c, textScale: s);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 400));
    for (final label in ['Your circle', 'Everyone', 'WEEK', 'MONTH', 'ALL TIME']) {
      // "WEEK" is also the standing label on a phone; check every match.
      for (final element in find.text(label).evaluate()) {
        final paragraph = element.renderObject! as RenderParagraph;
        expect(paragraph.didExceedMaxLines, isFalse, reason: '"$label" is ellipsized');
      }
    }
    await finishCase(tester);
  });

  // The badge shelf with the dashed "+10" tile (board 49): the tile is a button
  // at least 44 px square, wherever the layout puts it.
  screenMatrix('leaderboard/badges', (tester, c, s) async {
    RewardsService.instance = FakeRewardsService(fakeState: sampleBadgesState);
    await pumpAtSize(tester, const LeaderboardScreen(), c, textScale: s);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 400));
    final tile = find.text('+10', skipOffstage: false);
    expect(tile, findsOneWidget, reason: 'the to-earn tile');
    final size = tester.getSize(find.ancestor(of: tile, matching: find.byType(CustomPaint)).first);
    expect(size.width, greaterThanOrEqualTo(44), reason: 'touch target');
    expect(size.height, greaterThanOrEqualTo(44), reason: 'touch target');
    await finishCase(tester);
  });

  // The header used to sit directly on the page it scrolls: the scroll area
  // began at the back button's bottom edge, so content slid under the button
  // box. It starts 12 px below now, and the period tabs - the first thing that
  // reaches the header - clear it too once scrolled right up under it.
  screenMatrix('leaderboard/header-clearance', (tester, c, s) async {
    RewardsService.instance = FakeRewardsService(fakeState: sampleBadgesState);
    await pumpAtSize(tester, const LeaderboardScreen(), c, textScale: s);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 400));
    if (find.byType(CinemaMarqueeBar).evaluate().isEmpty) {
      final back = tester.getRect(
        find.ancestor(of: find.byIcon(BoothIcons.arrowBack), matching: find.byType(PTIconButton)),
      );
      final scroll = find.byType(SingleChildScrollView).first;
      final scrollTop = tester.getTopLeft(scroll).dy;
      expect(
        scrollTop - back.bottom,
        greaterThanOrEqualTo(12),
        reason: 'scroll area clears header',
      );
      final tabTop = tester.getTopLeft(find.text('MONTH')).dy;
      await tester.drag(scroll, Offset(0, -(tabTop - scrollTop)));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.getTopLeft(find.text('MONTH')).dy - back.bottom,
        greaterThanOrEqualTo(12),
        reason: 'tabs clear the back button',
      );
    }
    await finishCase(tester);
  });
}
