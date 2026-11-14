import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../platform.dart';
import '../../ui/glass.dart';
import '../../ui/pt_motion.dart';
import '../../ui/pt_theme.dart';
import '../rewards_logic.dart';
import '../rewards_models.dart';
import 'badge_art.dart';
import 'badge_catalog_dialog.dart';
import 'unlock_toast.dart';

/// The earned badges as a row of compact tiles, then one dashed tile counting
/// what is still to earn - the "12 · Profile" / "Leaderboard" boards.
///
/// Every tile is a button onto the full catalog (board 49): an earned one opens
/// it on its own row, the dashed one at the top. The dashed tile is the answer
/// to "what are the other fourteen?", so it must never look tappable and not be.
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
            child: BadgeTile(
              achievement: a,
              size: tile,
              showLabel: showLabels,
              onTap: () => unawaited(showBadgeCatalog(context, state, focusId: a.id)),
            ),
          ),
        if (toEarn > 0)
          _ToEarnTile(
            count: toEarn,
            size: tile,
            showLabel: showLabels,
            next: nextAchievement(state.achievements, state.metrics),
            onTap: () => unawaited(showBadgeCatalog(context, state)),
          ),
      ],
    );
  }
}

class BadgeTile extends StatelessWidget {
  const BadgeTile({
    super.key,
    required this.achievement,
    this.size = 46,
    this.showLabel = true,
    this.onTap,
  });

  final Achievement achievement;
  final double size;
  final bool showLabel;

  /// Opens the badge's detail. Without it the tile is a plain picture.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final art = Container(
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
    final tap = onTap;
    final box = tap == null
        ? art
        : _BadgeButton(
            label:
                '${achievement.title}, earned. ${achievement.description} Tap to see all badges.',
            onTap: tap,
            child: (_) => art,
          );
    return Tooltip(
      message: '${achievement.title} · ${achievement.description}',
      excludeFromSemantics: tap != null,
      child: showLabel ? _Labelled(label: achievement.title, spoken: tap == null, child: box) : box,
    );
  }
}

class _ToEarnTile extends StatelessWidget {
  const _ToEarnTile({
    required this.count,
    required this.size,
    required this.showLabel,
    required this.onTap,
    this.next,
  });

  final int count;
  final double size;
  final bool showLabel;
  final VoidCallback onTap;
  final Achievement? next;

  @override
  Widget build(BuildContext context) {
    final box = _BadgeButton(
      label: '$count more badge${count == 1 ? '' : 's'}, tap to see how to earn them',
      onTap: onTap,
      child: (hovered) => CustomPaint(
        painter: DashedRectPainter(
          color: hovered ? PTColors.white(0.7) : PTColors.rail,
          radius: PTRadius.panel,
        ),
        child: SizedBox.square(
          dimension: size,
          child: Center(
            child: Text(
              '+$count',
              style: PTText.mono.copyWith(
                fontSize: 12,
                color: hovered ? PTColors.fg : PTColors.white(0.3),
              ),
            ),
          ),
        ),
      ),
    );
    final n = next;
    return Tooltip(
      message: [
        badgesToEarnLabel(count),
        if (n != null) 'Closest: ${n.title} · ${n.description}',
        '${isDesktop ? 'Click' : 'Tap'} to see how',
      ].join('\n'),
      // The button carries its own label; a second spoken copy would repeat it.
      excludeFromSemantics: true,
      child: showLabel ? _Labelled(label: 'to earn', muted: true, spoken: false, child: box) : box,
    );
  }
}

/// A tile that opens something: pointer cursor and hover, a Beam ring for
/// keyboard focus, Enter/Space to activate, one spoken label, and the kit's
/// press scale. Tiles are 44 px or more, so the hit area needs no padding.
class _BadgeButton extends StatefulWidget {
  const _BadgeButton({required this.label, required this.onTap, required this.child});

  final String label;
  final VoidCallback onTap;
  final Widget Function(bool hovered) child;

  @override
  State<_BadgeButton> createState() => _BadgeButtonState();
}

class _BadgeButtonState extends State<_BadgeButton> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (v) => setState(() => _hovered = v),
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: PTPressable(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: PTMotion.functional(context, PTMotion.hover),
            foregroundDecoration: BoxDecoration(
              border: Border.all(
                color: _focused ? PTColors.primary : PTColors.primary.withValues(alpha: 0),
                width: 2,
              ),
              borderRadius: BorderRadius.circular(PTRadius.panel),
            ),
            child: widget.child(_hovered),
          ),
        ),
      ),
    );
  }
}

/// A tile with its title underneath, in a column a little wider than the tile
/// so two-word titles ("Double Feature") wrap instead of clipping.
class _Labelled extends StatelessWidget {
  const _Labelled({
    required this.label,
    required this.child,
    this.muted = false,
    this.spoken = true,
  });

  final String label;
  final Widget child;
  final bool muted;

  /// False when the tile above already announces these words itself.
  final bool spoken;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 58,
      child: Column(
        mainAxisSize: .min,
        spacing: 6,
        children: [
          child,
          ExcludeSemantics(
            excluding: !spoken,
            child: Text(
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
          ),
        ],
      ),
    );
  }
}
