import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/rewards/rewards_models.dart';
import 'package:synctogether/rewards/rewards_service.dart';
import 'package:synctogether/ui/glass.dart';

import '../support/screen_matrix.dart';

/// Asserts every on-screen Text matching [text] shows whole: no ellipsis and
/// no wrapped line (a one-word label that wraps broke mid-word).
void expectShownWhole(WidgetTester tester, String text) {
  final finder = find.text(text);
  expect(finder, findsAtLeastNWidgets(1), reason: '"$text" missing');
  var checked = 0;
  for (final element in finder.evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    // A FirstFit candidate that lost was never laid out at the real width.
    if (paragraph.debugNeedsLayout) continue;
    checked++;
    expect(paragraph.didExceedMaxLines, isFalse, reason: '"$text" ellipsized');
    final lines = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: text.length),
    );
    expect(
      lines.map((b) => b.top.round()).toSet().length,
      1,
      reason: '"$text" wrapped onto several lines',
    );
  }
  expect(checked, greaterThan(0), reason: '"$text" never laid out');
}

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

Achievement _badge(
  String id,
  String title,
  String description,
  String metric,
  int threshold, {
  RewardGrade grade = RewardGrade.bronze,
  AvatarFrame? frame,
  DateTime? earnedAt,
}) => Achievement(
  id: id,
  title: title,
  description: description,
  icon: 'bolt',
  grade: grade,
  metric: metric,
  threshold: threshold,
  frame: frame,
  unlocked: earnedAt != null,
  unlockedAt: earnedAt,
);

/// The shipped catalogue (the `achievements` seed in the gamification
/// migration, descriptions verbatim) with four earned: what the leaderboard's
/// badge shelf and the badge catalog dialog render.
final sampleBadgesState = RewardState(
  publicProfile: true,
  streak: const StreakState(current: 12, longest: 12, freezes: 2),
  weekRank: 3,
  circleRank: 2,
  metrics: const {
    'longest_streak': 12,
    'max_room_members': 5,
    'longest_session_seconds': 6720,
    'distinct_co_watchers': 6,
    'total_seconds': 32700,
    'reactions_sent': 212,
    'total_hosted': 3,
    'messages_sent': 340,
    'days_active': 12,
  },
  achievements: [
    _badge(
      'first_sync',
      'First Sync',
      'Finish a session with someone else.',
      'total_sessions',
      1,
      earnedAt: DateTime(2026, 8, 12, 12),
    ),
    _badge(
      'week_one',
      'Regular',
      'Keep a 3-day watch streak.',
      'longest_streak',
      3,
      frame: AvatarFrame.ember,
      earnedAt: DateTime(2026, 8, 14, 12),
    ),
    _badge(
      'seven_up',
      'Seven Up',
      'Keep a 7-day watch streak.',
      'longest_streak',
      7,
      grade: RewardGrade.silver,
      earnedAt: DateTime(2026, 8, 22, 12),
    ),
    _badge(
      'unbroken',
      'Unbroken',
      'Keep a 30-day watch streak.',
      'longest_streak',
      30,
      grade: RewardGrade.gold,
      frame: AvatarFrame.aurora,
    ),
    _badge(
      'double_feature',
      'Double Feature',
      'Watch in two different rooms in one day.',
      'double_feature_days',
      1,
      earnedAt: DateTime(2026, 9, 3, 12),
    ),
    _badge(
      'full_house',
      'Full House',
      'Be in a room with 8 or more people.',
      'max_room_members',
      8,
      grade: RewardGrade.silver,
    ),
    _badge(
      'marathon',
      'Marathon',
      'Stay in one session for over 4 hours.',
      'longest_session_seconds',
      14400,
      grade: RewardGrade.silver,
    ),
    _badge('night_owl', 'Night Owl', 'Watch through 2am.', 'night_owl_sessions', 1),
    _badge(
      'wide_circle',
      'Wide Circle',
      'Watch with 10 different people.',
      'distinct_co_watchers',
      10,
      grade: RewardGrade.silver,
      frame: AvatarFrame.halo,
    ),
    _badge(
      'century',
      'Century',
      'Watch 100 hours together.',
      'total_seconds',
      360000,
      grade: RewardGrade.gold,
      frame: AvatarFrame.laurel,
    ),
    _badge('hype_man', 'Hype Machine', 'Send 500 reactions.', 'reactions_sent', 500),
    _badge(
      'host_with_most',
      'Host With The Most',
      'Host 25 sessions.',
      'total_hosted',
      25,
      grade: RewardGrade.silver,
    ),
    _badge('chatterbox', 'Chatterbox', 'Send 1,000 chat messages.', 'messages_sent', 1000),
    _badge(
      'devoted',
      'Devoted',
      'Be active on 100 different days.',
      'days_active',
      100,
      grade: RewardGrade.gold,
    ),
  ],
);
