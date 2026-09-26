import 'package:flutter/material.dart';
import '../../ui/pt_theme.dart';
import '../rewards_models.dart';
import 'badge_art.dart';

/// Permanent placings from monthly seasons.
///
/// The weekly board resets and is forgotten; these do not. A trophy that
/// outlives the month it was won in is the whole reason a monthly board is
/// worth chasing, so it is rendered as an object, not as a past rank.
class SeasonTrophies extends StatelessWidget {
  const SeasonTrophies({super.key, required this.seasons, this.max = 4});

  final List<SeasonAward> seasons;
  final int max;

  static Color colorFor(int rank) => switch (rank) {
    1 => PTColors.premium,
    2 => PTColors.silver,
    _ => PTColors.bronze,
  };

  @override
  Widget build(BuildContext context) {
    if (seasons.isEmpty) return const SizedBox.shrink();
    final shown = seasons.take(max).toList();
    final hidden = seasons.length - shown.length;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final award in shown) _Trophy(award: award),
        if (hidden > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: PTColors.white(0.06),
              border: Border.all(color: PTColors.white(0.12)),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text('+$hidden more', style: PTText.finePrint.copyWith(fontSize: 11.5)),
          ),
      ],
    );
  }
}

class _Trophy extends StatelessWidget {
  const _Trophy({required this.award});

  final SeasonAward award;

  @override
  Widget build(BuildContext context) {
    final colour = SeasonTrophies.colorFor(award.rank);
    return Tooltip(
      message: '${award.label} · ${award.monthLabel}',
      child: Container(
        padding: const EdgeInsets.fromLTRB(7, 5, 12, 5),
        decoration: BoxDecoration(
          color: colour.withValues(alpha: 0.14),
          border: Border.all(color: colour.withValues(alpha: 0.45)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: .min,
          spacing: 6,
          children: [
            BadgeArt(size: 18, seasonRank: award.rank, fallbackIcon: 'emoji_events'),
            Text(
              '#${award.rank} · ${award.monthLabel}',
              style: PTText.finePrint.copyWith(fontSize: 11.5, fontWeight: .w600, color: colour),
            ),
          ],
        ),
      ),
    );
  }
}
