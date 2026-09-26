import 'package:flutter/material.dart';

import '../../ui/glass.dart';
import '../../ui/pt_motion.dart';
import '../../ui/pt_theme.dart';
import '../rewards_logic.dart';
import '../rewards_models.dart';
import 'badge_art.dart';
import 'unlock_toast.dart';

/// The badge grid: unlocked first, then whatever is in reach.
///
/// Secret badges are absent until they are earned - that absence is the whole
/// point of a secret, and it is what makes one worth screenshotting.
class BadgeShelf extends StatelessWidget {
  const BadgeShelf({super.key, required this.state, this.crossAxisCount = 4});

  final RewardState state;
  final int crossAxisCount;

  @override
  Widget build(BuildContext context) {
    final unlocked = state.unlocked;
    final locked =
        [
          for (final a in state.locked)
            if (!a.isSecret) a,
        ]..sort(
          (a, b) => achievementProgress(
            b,
            state.metrics,
          ).compareTo(achievementProgress(a, state.metrics)),
        );
    final items = [...unlocked, ...locked];

    if (items.isEmpty) {
      return Text(
        'Watch something with someone and your first badge lands here.',
        style: PTText.caption,
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.84,
      ),
      itemCount: items.length,
      // Tiles deal in with a short stagger, capped so a big shelf still
      // finishes arriving inside half a second.
      itemBuilder: (context, i) => PTEntrance(
        delay: Duration(milliseconds: 25 * (i < 12 ? i : 12)),
        duration: PTMotion.state,
        offset: 6,
        child: BadgeTile(
          achievement: items[i],
          progress: achievementProgress(items[i], state.metrics),
        ),
      ),
    );
  }
}

class BadgeTile extends StatelessWidget {
  const BadgeTile({super.key, required this.achievement, this.progress = 0});

  final Achievement achievement;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final unlocked = achievement.unlocked;
    final colour = unlocked ? gradeColor(achievement.grade) : PTColors.white(0.35);

    return Tooltip(
      message: unlocked
          ? achievement.description
          : '${achievement.description}  ·  ${(progress * 100).round()}%',
      child: GlassPanel(
        radius: 16,
        opacity: unlocked ? 0.5 : 0.3,
        blur: 18,
        shadow: false,
        borderColor: unlocked ? colour.withValues(alpha: 0.35) : PTColors.white(0.08),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Column(
          mainAxisAlignment: .center,
          mainAxisSize: .min,
          spacing: 6,
          children: [
            Stack(
              alignment: .center,
              children: [
                // No tinted chip behind the art: the artwork carries its own
                // glow, and a disc under it would be a second container inside
                // the tile this already sits in.
                BadgeArt(
                  size: 42,
                  achievementId: achievement.id,
                  fallbackIcon: achievement.icon,
                  locked: !unlocked,
                  fallbackColor: colour,
                ),
                if (!unlocked && progress > 0)
                  SizedBox.square(
                    dimension: 44,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: progress),
                      duration: PTMotion.functional(context, PTMotion.entrance),
                      curve: PTMotion.enter,
                      builder: (context, value, _) => CircularProgressIndicator(
                        value: value,
                        strokeWidth: 2,
                        backgroundColor: PTColors.white(0.08),
                        valueColor: AlwaysStoppedAnimation(PTColors.primary.withValues(alpha: 0.7)),
                      ),
                    ),
                  ),
              ],
            ),
            // Flexible: the art is taller than the glyph chip it replaced, so a
            // long two-line title would otherwise overflow the tile.
            Flexible(
              child: Text(
                achievement.title,
                textAlign: .center,
                maxLines: 2,
                overflow: .ellipsis,
                style: PTText.finePrint.copyWith(
                  fontSize: 11,
                  fontWeight: .w600,
                  color: unlocked ? PTColors.white(0.9) : PTColors.white(0.45),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
