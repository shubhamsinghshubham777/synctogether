import 'package:flutter/material.dart';

import '../../ui/glass.dart';
import '../../ui/pt_motion.dart';
import '../../ui/pt_theme.dart';
import '../../ui/scroll_fade.dart';
import '../rewards_logic.dart';
import '../rewards_models.dart';
import 'badge_art.dart';
import 'unlock_toast.dart';

/// Every badge there is to see, earned and still to earn, each with the rule
/// that wins it - the board "49 · Badge catalog".
///
/// The rule is the catalogue's own `description`, verbatim: it is a database
/// row that ships with `my_rewards`, the same text `grant_achievements` is
/// keyed to, so this list cannot drift from what the server actually grants.
/// Secrets stay out until they are earned, exactly as on the shelf.
///
/// [focusId] opens on one badge (the earned tile that was tapped): its row is
/// marked and scrolled into view.
Future<void> showBadgeCatalog(BuildContext context, RewardState state, {String? focusId}) {
  return showGlassDialog<void>(
    context: context,
    width: 520,
    scrollable: false,
    sheetOnCompact: true,
    padding: const EdgeInsets.fromLTRB(28, 26, 0, 0),
    builder: (context) => BadgeCatalog(state: state, focusId: focusId),
  );
}

class BadgeCatalog extends StatefulWidget {
  const BadgeCatalog({super.key, required this.state, this.focusId});

  final RewardState state;
  final String? focusId;

  @override
  State<BadgeCatalog> createState() => _BadgeCatalogState();
}

class _BadgeCatalogState extends State<BadgeCatalog> {
  final _focusKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.focusId == null) return;
    // The list is laid out by the first frame; only then does the row have a
    // place to scroll to. Reduce-motion shortens the glide rather than
    // dropping it, since it is what tells the eye where the row went.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final row = _focusKey.currentContext;
      if (row == null || !mounted) return;
      Scrollable.ensureVisible(
        row,
        alignment: 0.1,
        duration: PTMotion.functional(context, PTMotion.state),
        curve: PTMotion.enter,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final earned = state.unlocked;
    final toEarn = badgesToEarn(state.achievements, state.metrics);
    final rows = <Widget>[
      if (earned.isNotEmpty) _Section(label: 'EARNED', count: earned.length),
      for (final a in earned)
        _BadgeRow(
          key: a.id == widget.focusId ? _focusKey : null,
          achievement: a,
          metrics: state.metrics,
          focused: a.id == widget.focusId,
        ),
      if (toEarn.isNotEmpty) _Section(label: 'TO EARN', count: toEarn.length),
      for (final a in toEarn)
        _BadgeRow(
          key: a.id == widget.focusId ? _focusKey : null,
          achievement: a,
          metrics: state.metrics,
          focused: a.id == widget.focusId,
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 4),
        child: Text('Some badges stay hidden until you earn them.', style: PTText.finePrint),
      ),
    ];
    final header = Padding(
      padding: const EdgeInsets.only(right: 28),
      child: GlassDialogHeader(
        eyebrow: 'Badges',
        title: 'Every badge',
        subtitle: _subtitle(earned.length, toEarn.length),
        titleGap: 4,
        onClose: () => Navigator.of(context).pop(),
      ),
    );

    // Below this height a pinned header plus a scrolling list leaves the list
    // no room at all (phone landscape, big text), so it all scrolls as one.
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < MediaQuery.textScalerOf(context).scale(360);
        if (compact) {
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .stretch,
              children: [
                header,
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.only(right: 28, bottom: 22),
                  child: Column(crossAxisAlignment: .stretch, children: rows),
                ),
              ],
            ),
          );
        }
        return Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: [
            header,
            const SizedBox(height: 14),
            Flexible(
              child: ScrollFadeEdge(
                height: 40,
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(0, 0, 28, 22),
                  children: rows,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static String _subtitle(int earned, int toEarn) {
    final parts = [if (earned > 0) '$earned earned', if (toEarn > 0) '$toEarn to go'];
    return '${parts.join(', ')}${parts.isEmpty ? '' : '. '}Each one says exactly how it is won.';
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 6),
      child: Semantics(
        header: true,
        child: Row(
          children: [
            Expanded(child: Text(label, style: PTText.label)),
            Text('$count', style: PTText.mono.copyWith(fontSize: 12, color: PTColors.fgDim)),
          ],
        ),
      ),
    );
  }
}

class _BadgeRow extends StatelessWidget {
  const _BadgeRow({
    super.key,
    required this.achievement,
    required this.metrics,
    required this.focused,
  });

  final Achievement achievement;
  final Map<String, int> metrics;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final a = achievement;
    final earned = a.unlocked;
    final grade = gradeColor(a.grade);
    final progress = earned ? null : badgeProgressLabel(a, metrics);
    final unlockedAt = a.unlockedAt;
    final frame = a.frame;
    final semantics = [
      a.title,
      a.description,
      if (frame != null) 'Comes with the ${frame.label} avatar frame.',
      if (earned)
        unlockedAt == null ? 'Earned.' : 'Earned ${formatBadgeDate(unlockedAt)}.'
      else
        'Not earned yet.${progress == null ? '' : ' $progress.'}',
    ].join(' ');

    return MergeSemantics(
      child: Semantics(
        label: semantics,
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
          decoration: BoxDecoration(
            color: focused ? PTColors.glassBase : null,
            border: Border(
              left: BorderSide(
                color: focused ? PTColors.primary : PTColors.primary.withValues(alpha: 0),
                width: 2,
              ),
              bottom: const BorderSide(color: PTColors.aisle),
            ),
          ),
          child: Row(
            crossAxisAlignment: .start,
            spacing: 14,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: .center,
                decoration: BoxDecoration(
                  color: PTColors.aisle,
                  border: Border.all(color: PTColors.rail),
                  borderRadius: BorderRadius.circular(PTRadius.panel),
                ),
                child: BadgeArt(
                  size: 32,
                  achievementId: a.id,
                  fallbackIcon: a.icon,
                  fallbackColor: earned ? grade : null,
                  locked: !earned,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  spacing: 4,
                  children: [
                    Wrap(
                      crossAxisAlignment: .center,
                      spacing: 10,
                      children: [
                        Text(
                          a.title,
                          style: PTText.body.copyWith(
                            fontSize: 15,
                            fontWeight: .w600,
                            color: earned ? PTColors.fg : PTColors.white(0.6),
                          ),
                        ),
                        Text(
                          a.grade.name.toUpperCase(),
                          style: PTText.label.copyWith(
                            fontSize: 10,
                            color: earned ? grade : PTColors.away,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      a.description,
                      style: PTText.caption.copyWith(
                        fontSize: 13,
                        color: earned ? null : PTColors.away,
                      ),
                    ),
                    if (frame != null)
                      Text(
                        'Comes with the ${frame.label} avatar frame.',
                        style: PTText.finePrint.copyWith(fontSize: 12),
                      ),
                    if (earned && unlockedAt != null)
                      Text(
                        'EARNED ${formatBadgeDate(unlockedAt).toUpperCase()}',
                        style: PTText.label.copyWith(fontSize: 11, color: PTColors.online),
                      ),
                    if (progress != null)
                      _Progress(value: achievementProgress(a, metrics), label: progress),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.value, required this.label});

  final double value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final duration = reducedMotion(context) ? Duration.zero : PTMotion.entrance;
    return Row(
      spacing: 10,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Container(
              height: 4,
              color: PTColors.aisle,
              alignment: .centerLeft,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: value),
                duration: duration,
                curve: PTMotion.enter,
                builder: (context, v, _) => FractionallySizedBox(
                  widthFactor: v,
                  child: Container(color: PTColors.fgDim),
                ),
              ),
            ),
          ),
        ),
        Text(label, style: PTText.mono.copyWith(fontSize: 11, color: PTColors.fgDim)),
      ],
    );
  }
}
