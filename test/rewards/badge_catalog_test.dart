import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/rewards/rewards_models.dart';
import 'package:synctogether/rewards/widgets/badge_catalog_dialog.dart';
import 'package:synctogether/rewards/widgets/badge_shelf.dart';
import 'package:synctogether/ui/pt_theme.dart';

Widget wrap(Widget child) => MaterialApp(
  theme: buildPTTheme(),
  home: Scaffold(body: Center(child: child)),
);

Achievement badge(
  String id, {
  String? title,
  String? description,
  String metric = 'x',
  int threshold = 10,
  DateTime? earnedAt,
  RewardGrade grade = RewardGrade.bronze,
  AvatarFrame? frame,
}) => Achievement(
  id: id,
  title: title ?? id,
  description: description ?? '$id rule',
  icon: 'bolt',
  grade: grade,
  metric: metric,
  threshold: threshold,
  frame: frame,
  unlocked: earnedAt != null,
  unlockedAt: earnedAt,
);

final state = RewardState(
  achievements: [
    badge('first', title: 'First One', threshold: 1, earnedAt: DateTime(2026, 8, 12, 12)),
    badge('far', title: 'Far Off', description: 'Go the distance.', threshold: 100),
    badge('near', title: 'Nearly There', description: 'Almost done.', threshold: 10),
    badge('hidden', title: 'Hidden One', grade: RewardGrade.secret),
  ],
  metrics: const {'x': 8},
);

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  group('the to-earn tile', () {
    testWidgets('opens the catalog with every visible badge and its rule', (tester) async {
      await tester.pumpWidget(wrap(BadgeShelf(state: state)));
      await settle(tester);
      await tester.tap(find.text('+2'));
      await settle(tester);

      expect(find.text('Every badge'), findsOneWidget);
      expect(find.text('1 earned, 2 to go. Each one says exactly how it is won.'), findsOneWidget);
      // The rule is the catalogue's own text, earned or not.
      expect(find.text('first rule'), findsOneWidget);
      expect(find.text('Go the distance.'), findsOneWidget);
      expect(find.text('Almost done.'), findsOneWidget);
      // Earned: dated. Locked: progress from the metrics the server sent.
      expect(find.text('EARNED 12 AUG 2026'), findsOneWidget);
      expect(find.text('8 of 10'), findsOneWidget);
      expect(find.text('8 of 100'), findsOneWidget);
      // A locked secret stays a secret.
      expect(find.text('Hidden One'), findsNothing);
      expect(find.text('Some badges stay hidden until you earn them.'), findsOneWidget);
    });

    testWidgets('lists the closest badge first', (tester) async {
      await tester.pumpWidget(wrap(BadgeShelf(state: state)));
      await settle(tester);
      await tester.tap(find.text('+2'));
      await settle(tester);
      expect(
        tester.getTopLeft(find.text('Nearly There')).dy,
        lessThan(tester.getTopLeft(find.text('Far Off')).dy),
      );
    });

    testWidgets('is announced as a button that says what it does', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(wrap(BadgeShelf(state: state)));
      await settle(tester);
      final node = tester.getSemantics(
        find.bySemanticsLabel('2 more badges, tap to see how to earn them'),
      );
      expect(node.flagsCollection.isButton, isTrue);
      handle.dispose();
    });

    testWidgets('says "1 more badge" in the singular', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        wrap(
          BadgeShelf(
            state: RewardState(
              achievements: [
                badge('one'),
                badge('first', earnedAt: DateTime(2026)),
              ],
            ),
          ),
        ),
      );
      await settle(tester);
      expect(find.bySemanticsLabel('1 more badge, tap to see how to earn them'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('can be reached and opened from the keyboard', (tester) async {
      await tester.pumpWidget(wrap(BadgeShelf(state: state)));
      await settle(tester);
      // One earned tile, then the dashed one.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await settle(tester);
      expect(find.text('Every badge'), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await settle(tester);
      expect(find.text('Every badge'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);
      expect(find.text('Every badge'), findsOneWidget);
    });

    testWidgets('shows a preview on hover', (tester) async {
      await tester.pumpWidget(wrap(BadgeShelf(state: state)));
      await settle(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('+2')));
      await tester.pump(const Duration(seconds: 2));
      expect(find.textContaining('2 more badges to earn'), findsOneWidget);
      expect(find.textContaining('Closest: Nearly There'), findsOneWidget);
      expect(find.textContaining('to see how'), findsOneWidget);
    });

    testWidgets('is at least 44 px square', (tester) async {
      await tester.pumpWidget(wrap(BadgeShelf(state: state, showLabels: false)));
      await settle(tester);
      final size = tester.getSize(
        find.ancestor(of: find.text('+2'), matching: find.byType(CustomPaint)).first,
      );
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    });
  });

  group('an earned tile', () {
    testWidgets('opens the catalog on its own row', (tester) async {
      await tester.pumpWidget(wrap(BadgeShelf(state: state, showLabels: false)));
      await settle(tester);
      // Tiles carry their title in the tooltip, not as text.
      await tester.tap(find.byTooltip('First One · first rule'));
      await settle(tester);
      expect(find.text('Every badge'), findsOneWidget);
      expect(find.text('EARNED 12 AUG 2026'), findsOneWidget);
      // Only the tapped badge's row is marked (a Seat fill with the Beam rule).
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.padding == const EdgeInsets.fromLTRB(12, 12, 4, 12) &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).color == PTColors.glassBase,
        ),
        findsOneWidget,
      );
    });
  });

  group('BadgeCatalog', () {
    testWidgets('names the frame a badge comes with', (tester) async {
      await tester.pumpWidget(
        wrap(
          SizedBox(
            height: 700,
            child: BadgeCatalog(
              state: RewardState(
                achievements: [badge('reg', frame: AvatarFrame.ember, earnedAt: DateTime(2026))],
              ),
            ),
          ),
        ),
      );
      await settle(tester);
      expect(find.text('Comes with the Ember avatar frame.'), findsWidgets);
    });

    testWidgets('has a close button', (tester) async {
      await tester.pumpWidget(wrap(BadgeShelf(state: state)));
      await settle(tester);
      await tester.tap(find.text('+2'));
      await settle(tester);
      await tester.tap(find.byTooltip('Close'));
      await settle(tester);
      expect(find.text('Every badge'), findsNothing);
    });

    testWidgets('can be opened directly', (tester) async {
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showBadgeCatalog(context, state, focusId: 'far'),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await settle(tester);
      expect(find.text('Far Off'), findsOneWidget);
    });
  });
}
