import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/rewards/rewards_models.dart';
import 'package:synctogether/rewards/rewards_service.dart';
import 'package:synctogether/ui/glass.dart';

import '../support/screen_matrix.dart';

/// Asserts no overflow and - inside a [screenMatrix] case that has not opted
/// out - that every control respects the system insets, then unmounts so periodic timers (lobby polling,
/// loaders) are cancelled before the test ends.
Future<void> finishCase(WidgetTester tester) async {
  await captureScreenshot(tester);
  expectNoOverflow(tester);
  if (insetCheckActive) {
    await expectRespectsInsets(tester);
    expectNoOverflow(tester);
  }
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 50));
  // Anything thrown while tearing down is a bug too, but not a layout one.
  tester.takeException();
}

/// Pumps a button at [c], taps it to open [builder] through [showGlassDialog],
/// and lets the entrance transition finish (bounded - no pumpAndSettle).
Future<void> pumpGlassDialog(
  WidgetTester tester,
  ScreenCase c,
  double textScale,
  WidgetBuilder builder, {
  double width = 430,
}) {
  return pumpDialogOpener(
    tester,
    c,
    textScale,
    (context) => showGlassDialog<void>(context: context, width: width, builder: builder),
  );
}

/// Same as [pumpGlassDialog] for dialogs that own their `show*` entry point.
Future<void> pumpDialogOpener(
  WidgetTester tester,
  ScreenCase c,
  double textScale,
  void Function(BuildContext context) open,
) async {
  await pumpAtSize(
    tester,
    Scaffold(
      body: Builder(
        builder: (context) => Align(
          alignment: Alignment.topLeft,
          child: TextButton(onPressed: () => open(context), child: const Text('open')),
        ),
      ),
    ),
    c,
    textScale: textScale,
  );
  // The opener itself is not under test.
  tester.takeException();
  await tester.tap(find.text('open'), warnIfMissed: false);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 100));
}

/// Rewards with no backend: loaded, a live streak, and a populated board.
class FakeRewardsService extends RewardsService {
  FakeRewardsService({this.fakeState = sampleRewardState, this.rows = sampleBoard});

  final RewardState fakeState;
  final List<LeaderboardRow> rows;

  @override
  RewardState get state => fakeState;

  @override
  bool get loaded => true;

  @override
  Future<RewardState?> load() async => fakeState;

  @override
  Future<List<LeaderboardRow>> leaderboard({
    LeaderboardScope scope = LeaderboardScope.circle,
    LeaderboardPeriod period = LeaderboardPeriod.week,
    int limit = 100,
  }) async => rows;

  @override
  Future<int> loadReferrals() async => 3;

  @override
  Future<List<SharedRecap>> loadSharedRecaps() async => const [];
}

const sampleRewardState = RewardState(
  publicProfile: true,
  streak: StreakState(current: 12, longest: 30, freezes: 2),
  weekRank: 3,
  circleRank: 2,
);

const sampleBoard = [
  LeaderboardRow(
    rank: 1,
    userId: 'u1',
    displayName: 'Maximiliana Featherstonehaugh-Wolfeschlegel',
    points: 123456,
    isPremium: true,
    streak: 41,
    seconds: 360000,
  ),
  LeaderboardRow(
    rank: 2,
    userId: 'user-alex',
    displayName: 'Alex Rivers',
    points: 9800,
    isMe: true,
    streak: 12,
  ),
  LeaderboardRow(rank: 3, userId: 'u3', displayName: 'Sam', points: 7200, streak: 3),
  LeaderboardRow(rank: 4, userId: 'u4', displayName: 'Priya Ramanathan', points: 4100),
  LeaderboardRow(rank: 5, userId: 'u5', displayName: 'Jo', points: 12),
];
