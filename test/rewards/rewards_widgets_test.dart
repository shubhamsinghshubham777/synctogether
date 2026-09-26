import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/rewards/rewards_models.dart';
import 'package:synctogether/rewards/widgets/badge_shelf.dart';
import 'package:synctogether/rewards/widgets/streak_chip.dart';
import 'package:synctogether/rewards/widgets/unlock_toast.dart';
import 'package:synctogether/ui/identity.dart';
import 'package:synctogether/ui/pt_theme.dart';

Widget wrap(Widget child) => MaterialApp(
  theme: buildPTTheme(),
  home: Scaffold(body: Center(child: child)),
);

Achievement badge(
  String id, {
  required String metric,
  int threshold = 10,
  bool unlocked = false,
  RewardGrade grade = RewardGrade.bronze,
}) => Achievement(
  id: id,
  title: id,
  description: '$id description',
  icon: 'bolt',
  grade: grade,
  metric: metric,
  threshold: threshold,
  unlocked: unlocked,
);

void main() {
  group('StreakChip', () {
    testWidgets('invites a first streak rather than reporting a zero', (tester) async {
      await tester.pumpWidget(wrap(const StreakChip(streak: StreakState())));
      expect(find.text('Start a streak'), findsOneWidget);
    });

    testWidgets('names the streak once there is one', (tester) async {
      await tester.pumpWidget(
        wrap(const StreakChip(streak: StreakState(current: 6, qualifiedToday: true))),
      );
      expect(find.text('6 day streak'), findsOneWidget);
    });

    testWidgets('shows the day in progress until it qualifies', (tester) async {
      await tester.pumpWidget(
        wrap(const StreakChip(streak: StreakState(current: 2, secondsToday: 600))),
      );
      final ring = tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));
      expect(ring.value, closeTo(0.5, 0.001));
    });

    testWidgets('drops the ring once the day is banked', (tester) async {
      await tester.pumpWidget(
        wrap(
          const StreakChip(
            streak: StreakState(current: 2, secondsToday: 1200, qualifiedToday: true),
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('a guest sees the offer, not an empty slot or a fake streak', (tester) async {
      await tester.pumpWidget(wrap(const StreakChip(streak: StreakState(), locked: true)));
      expect(find.text('Sign in for streaks'), findsOneWidget);
      // No ring: a guest has no day in progress to report, and a half-filled
      // ring would be a promise the account cannot keep.
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('a locked chip never shows a number it cannot honour', (tester) async {
      await tester.pumpWidget(
        wrap(const StreakChip(streak: StreakState(current: 9), locked: true)),
      );
      expect(find.text('9 day streak'), findsNothing);
      expect(find.text('Sign in for streaks'), findsOneWidget);
    });

    testWidgets('shrinks to the number when compact', (tester) async {
      await tester.pumpWidget(
        wrap(const StreakChip(streak: StreakState(current: 6), compact: true)),
      );
      expect(find.text('6'), findsOneWidget);
      expect(find.text('6 day streak'), findsNothing);
    });
  });

  group('BadgeShelf', () {
    testWidgets('invites a first badge when there are none', (tester) async {
      await tester.pumpWidget(wrap(const BadgeShelf(state: RewardState.empty)));
      expect(find.textContaining('first badge'), findsOneWidget);
    });

    testWidgets('shows earned badges and counts the ones in reach', (tester) async {
      await tester.pumpWidget(
        wrap(
          BadgeShelf(
            state: RewardState(
              achievements: [
                badge('earned', metric: 'x', unlocked: true),
                badge('locked', metric: 'x'),
              ],
              metrics: const {'x': 5},
            ),
          ),
        ),
      );
      // Earned badges get a tile; the rest are a count on one dashed tile.
      expect(find.text('earned'), findsOneWidget);
      expect(find.text('locked'), findsNothing);
      expect(find.text('+1'), findsOneWidget);
    });

    testWidgets('never shows a secret that has not been earned', (tester) async {
      await tester.pumpWidget(
        wrap(
          BadgeShelf(
            state: RewardState(
              achievements: [badge('hidden', metric: 'x', grade: RewardGrade.secret)],
            ),
          ),
        ),
      );
      // The secret stays invisible, and with nothing else to show the shelf
      // falls back to its invitation rather than rendering an empty grid.
      expect(find.text('hidden'), findsNothing);
      expect(find.textContaining('first badge'), findsOneWidget);
    });

    testWidgets('shows a secret once it has been earned', (tester) async {
      await tester.pumpWidget(
        wrap(
          BadgeShelf(
            state: RewardState(
              achievements: [
                badge('hidden', metric: 'x', grade: RewardGrade.secret, unlocked: true),
              ],
            ),
          ),
        ),
      );
      expect(find.text('hidden'), findsOneWidget);
    });
  });

  group('UnlockToastHost', () {
    testWidgets('announces each badge once, in order, and then leaves', (tester) async {
      final controller = StreamController<Achievement>.broadcast();
      final announced = <String>[];

      await tester.pumpWidget(
        wrap(
          UnlockToastHost(
            stream: controller.stream,
            onShown: (a) => announced.add(a.id),
            child: const SizedBox(width: 400, height: 400),
          ),
        ),
      );

      expect(find.byType(UnlockCard), findsNothing);

      controller.add(badge('one', metric: 'x', unlocked: true));
      controller.add(badge('two', metric: 'x', unlocked: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Queued, not stacked: two at once must not put two cards on screen.
      expect(find.byType(UnlockCard), findsOneWidget);
      expect(announced, ['one']);

      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(milliseconds: 400));
      expect(announced, ['one', 'two']);

      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(UnlockCard), findsNothing);

      await controller.close();
    });

    testWidgets('the same badge arriving twice is announced once', (tester) async {
      final controller = StreamController<Achievement>.broadcast();
      final announced = <String>[];

      await tester.pumpWidget(
        wrap(
          UnlockToastHost(
            stream: controller.stream,
            onShown: (a) => announced.add(a.id),
            child: const SizedBox(width: 400, height: 400),
          ),
        ),
      );

      controller.add(badge('one', metric: 'x', unlocked: true));
      controller.add(badge('one', metric: 'x', unlocked: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(announced, ['one']);

      await tester.pump(const Duration(seconds: 7));
      expect(announced, ['one']);

      await controller.close();
    });

    testWidgets('the empty overlay does not eat taps on what is underneath', (tester) async {
      var taps = 0;
      final controller = StreamController<Achievement>.broadcast();

      await tester.pumpWidget(
        wrap(
          UnlockToastHost(
            stream: controller.stream,
            child: GestureDetector(
              onTap: () => taps++,
              child: Container(width: 400, height: 400, color: const Color(0xFF000000)),
            ),
          ),
        ),
      );

      await tester.tapAt(tester.getBottomLeft(find.byType(GestureDetector)) - const Offset(-10, 4));
      await tester.pump();
      expect(taps, 1);

      await controller.close();
    });
  });

  group('PTAvatar frames', () {
    testWidgets('a frame renders without disturbing the avatar itself', (tester) async {
      await tester.pumpWidget(
        wrap(const PTAvatar(userId: 'u1', displayName: 'Ana', frame: AvatarFrame.aurora, size: 48)),
      );
      expect(find.text('A'), findsOneWidget);
    });

    testWidgets('a frame and a crown coexist', (tester) async {
      await tester.pumpWidget(
        wrap(
          const PTAvatar(
            userId: 'u1',
            displayName: 'Ana',
            frame: AvatarFrame.aurum,
            premium: true,
            size: 48,
          ),
        ),
      );
      expect(find.byType(PremiumCrown), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
    });

    testWidgets('no frame is the unchanged avatar', (tester) async {
      await tester.pumpWidget(wrap(const PTAvatar(userId: 'u1', displayName: 'Ana')));
      expect(find.text('A'), findsOneWidget);
    });
  });
}
