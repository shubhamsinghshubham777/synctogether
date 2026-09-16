import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:synctogether/rewards/rewards_models.dart';
import 'package:synctogether/rewards/widgets/badge_art.dart';
import 'package:synctogether/rewards/widgets/badge_shelf.dart';
import 'package:synctogether/ui/pt_theme.dart';

Widget wrap(Widget child) => MaterialApp(
  theme: buildPTTheme(),
  home: Scaffold(body: Center(child: child)),
);

Achievement badge(String id, {bool unlocked = false}) => Achievement(
  id: id,
  title: id,
  description: '$id description',
  icon: 'bolt',
  grade: RewardGrade.bronze,
  metric: 'x',
  threshold: 10,
  unlocked: unlocked,
);

/// Achievement ids seeded by the gamification migration. Parsed rather than
/// hardcoded, so this test keeps working when the catalogue grows.
Set<String> _achievementIdsInMigration() {
  final sql = File('supabase/migrations/20260914100000_gamification.sql').readAsStringSync();
  final block = RegExp(
    r"insert into public\.achievements \([^)]*\) values(.*?);",
    dotAll: true,
  ).firstMatch(sql);
  expect(block, isNotNull, reason: 'the achievement seed block moved or was renamed');
  return RegExp(
    r"^\s*\('([a-z0-9_]+)'",
    multiLine: true,
  ).allMatches(block!.group(1)!).map((m) => m.group(1)!).toSet();
}

void main() {
  group('the art manifest matches what is on disk', () {
    test('every badge claiming art actually has a file', () {
      for (final id in kBadgeArt) {
        expect(
          File('assets/badges/$id.png').existsSync(),
          isTrue,
          reason:
              'kBadgeArt lists "$id" but assets/badges/$id.png is missing, so it '
              'would render a broken image instead of falling back to its glyph',
        );
      }
    });

    test('every badge claiming art is a real achievement', () {
      final ids = _achievementIdsInMigration();
      expect(
        kBadgeArt.difference(ids),
        isEmpty,
        reason:
            'art is shipped for badges that no achievement grants - dead weight '
            'in every installer',
      );
    });

    test('a badge in the catalogue without art is allowed, and falls back', () {
      // Not a failure: `achievements` is a database table, so the catalogue is
      // free to run ahead of the client. This documents that, and proves the
      // fallback path is the one such a badge takes.
      final withoutArt = _achievementIdsInMigration().difference(kBadgeArt);
      for (final id in withoutArt) {
        expect(badgeArtAsset(id), isNull);
      }
    });

    test('all three season placings have a trophy', () {
      for (var rank = 1; rank <= 3; rank++) {
        expect(seasonArtAsset(rank), 'assets/badges/season_$rank.png');
        expect(File('assets/badges/season_$rank.png').existsSync(), isTrue);
      }
    });

    test('a rank off the podium has no trophy to draw', () {
      expect(seasonArtAsset(0), isNull);
      expect(seasonArtAsset(4), isNull);
    });
  });

  group('BadgeArt', () {
    testWidgets('draws the artwork when there is some', (tester) async {
      await tester.pumpWidget(
        wrap(const BadgeArt(size: 44, achievementId: 'unbroken', fallbackIcon: 'bolt')),
      );
      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(Icon), findsNothing);
    });

    testWidgets('falls back to the glyph when there is none', (tester) async {
      await tester.pumpWidget(
        wrap(const BadgeArt(size: 44, achievementId: 'invented_next_year', fallbackIcon: 'bolt')),
      );
      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Symbols.bolt_rounded), findsOneWidget);
    });

    testWidgets('a locked badge is dimmed and drained, not hidden', (tester) async {
      await tester.pumpWidget(
        wrap(
          const BadgeArt(size: 44, achievementId: 'unbroken', fallbackIcon: 'bolt', locked: true),
        ),
      );
      // Still the real artwork: showing somebody the shape of what they have
      // not earned is the point.
      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(ColorFiltered), findsOneWidget);
      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, lessThan(0.5));
    });

    testWidgets('a locked badge with no art still gets a padlock', (tester) async {
      await tester.pumpWidget(
        wrap(
          const BadgeArt(
            size: 44,
            achievementId: 'invented_next_year',
            fallbackIcon: 'bolt',
            locked: true,
          ),
        ),
      );
      expect(find.byIcon(Symbols.lock_rounded), findsOneWidget);
    });

    testWidgets('a season placing draws its cup', (tester) async {
      await tester.pumpWidget(
        wrap(const BadgeArt(size: 18, seasonRank: 2, fallbackIcon: 'emoji_events')),
      );
      expect(find.byType(Image), findsOneWidget);
    });
  });

  group('BadgeShelf with art', () {
    testWidgets('earned badges draw art, locked ones draw it dimmed', (tester) async {
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 400,
            child: BadgeShelf(
              state: RewardState(
                achievements: [badge('unbroken', unlocked: true), badge('century')],
                metrics: const {'x': 5},
              ),
            ),
          ),
        ),
      );
      expect(find.byType(Image), findsNWidgets(2));
      expect(find.byType(ColorFiltered), findsOneWidget);
      // The progress ring says "not yet"; a padlock on top would say it twice.
      expect(find.byIcon(Symbols.lock_rounded), findsNothing);
    });
  });
}
