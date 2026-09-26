import 'package:flutter/material.dart';

import '../../ui/glass.dart';
import '../../ui/pt_motion.dart';
import '../../ui/pt_theme.dart';
import '../rewards_logic.dart';
import '../rewards_models.dart';
import 'badge_art.dart';
import 'unlock_toast.dart';

/// The earned badges as a row of compact tiles, then one dashed tile counting
/// what is still to earn - the "12 · Profile" / "Leaderboard" boards.
///
/// Locked badges are a count, not tiles: eighteen full tiles made the earned
/// ones hard to find and squeezed their titles out of a narrow column. Secret
/// badges are absent until they are earned - that absence is the whole point
/// of a secret, and it is what makes one worth screenshotting.
class BadgeShelf extends StatelessWidget {
  const BadgeShelf({super.key, required this.state, this.showLabels = true});

  final RewardState state;

  /// The profile names each badge under its tile; the leaderboard's shelf is
  /// tiles only, with the title in the tooltip.
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    final unlocked = state.unlocked;
    final toEarn = state.locked.where((a) => !a.isSecret).length;

    if (unlocked.isEmpty && toEarn == 0) {
      return Text(
        'Watch something with someone and your first badge lands here.',
        style: PTText.caption,
      );
    }

    final tile = showLabels ? 46.0 : 44.0;
    return Wrap(
      spacing: showLabels ? 2 : 8,
      runSpacing: 12,
      children: [
        for (final (i, a) in unlocked.indexed)
          // Tiles deal in with a short stagger, capped so a big shelf still
          // finishes arriving inside half a second.
          PTEntrance(
            delay: Duration(milliseconds: 25 * (i < 12 ? i : 12)),
            duration: PTMotion.state,
            offset: 6,
            child: BadgeTile(achievement: a, size: tile, showLabel: showLabels),
          ),
        if (toEarn > 0)
          _ToEarnTile(
            count: toEarn,
            size: tile,
            showLabel: showLabels,
            next: nextAchievement(state.achievements, state.metrics),
          ),
      ],
    );
  }
}

class BadgeTile extends StatelessWidget {
  const BadgeTile({super.key, required this.achievement, this.size = 46, this.showLabel = true});

  final Achievement achievement;
  final double size;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: size,
      height: size,
      alignment: .center,
      decoration: BoxDecoration(
        color: PTColors.aisle,
        border: Border.all(color: PTColors.rail),
        borderRadius: BorderRadius.circular(PTRadius.panel),
      ),
      child: BadgeArt(
        size: size - 12,
        achievementId: achievement.id,
        fallbackIcon: achievement.icon,
        fallbackColor: gradeColor(achievement.grade),
      ),
    );
    return Tooltip(
      message: '${achievement.title} · ${achievement.description}',
      child: showLabel ? _Labelled(label: achievement.title, child: box) : box,
    );
  }
}

class _ToEarnTile extends StatelessWidget {
  const _ToEarnTile({required this.count, required this.size, required this.showLabel, this.next});

  final int count;
  final double size;
  final bool showLabel;
  final Achievement? next;

  @override
  Widget build(BuildContext context) {
    final box = CustomPaint(
      painter: DashedRectPainter(color: PTColors.rail, radius: PTRadius.panel),
      child: SizedBox.square(
        dimension: size,
        child: Center(
          child: Text(
            '+$count',
            style: PTText.mono.copyWith(fontSize: 12, color: PTColors.white(0.3)),
          ),
        ),
      ),
    );
    final n = next;
    return Tooltip(
      message: n == null ? '$count to earn' : 'Closest: ${n.title} · ${n.description}',
      child: showLabel ? _Labelled(label: 'to earn', muted: true, child: box) : box,
    );
  }
}

/// A tile with its title underneath, in a column a little wider than the tile
/// so two-word titles ("Double Feature") wrap instead of clipping.
class _Labelled extends StatelessWidget {
  const _Labelled({required this.label, required this.child, this.muted = false});

  final String label;
  final Widget child;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 58,
      child: Column(
        mainAxisSize: .min,
        spacing: 6,
        children: [
          child,
          Text(
            label,
            textAlign: .center,
            maxLines: 2,
            overflow: .ellipsis,
            style: PTText.finePrint.copyWith(
              fontSize: 11,
              height: 1.2,
              color: muted ? PTColors.white(0.4) : PTColors.white(0.75),
            ),
          ),
        ],
      ),
    );
  }
}
