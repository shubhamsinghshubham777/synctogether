import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../ui/booth.dart';
import '../../ui/glass.dart';
import '../../ui/pt_motion.dart';
import '../../ui/pt_theme.dart';
import '../rewards_models.dart';
import 'badge_art.dart';

Color gradeColor(RewardGrade grade) => switch (grade) {
  RewardGrade.bronze => PTColors.bronze,
  RewardGrade.silver => PTColors.silver,
  RewardGrade.gold => PTColors.premium,
  RewardGrade.secret => PTColors.gradientEnd,
};

/// Slides an unlocked badge in from the bottom for a few seconds, then leaves.
///
/// Queue-driven rather than one-at-a-time: a session that crosses three
/// thresholds at once must not stack three cards on top of each other, and must
/// not drop two of them either.
class UnlockToastHost extends StatefulWidget {
  const UnlockToastHost({super.key, required this.stream, required this.child, this.onShown});

  final Stream<Achievement> stream;
  final Widget child;

  /// Fired exactly once per badge, as it becomes visible. This is where the
  /// single `achievement_unlocked` product event belongs - see the note beside
  /// that call for why a render is allowed to emit this one.
  final void Function(Achievement)? onShown;

  @override
  State<UnlockToastHost> createState() => _UnlockToastHostState();
}

class _UnlockToastHostState extends State<UnlockToastHost> {
  final _queue = <Achievement>[];
  Achievement? _showing;
  StreamSubscription<Achievement>? _sub;
  Timer? _dismiss;

  static const _kHold = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _sub = widget.stream.listen(_enqueue);
  }

  @override
  void didUpdateWidget(UnlockToastHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stream != widget.stream) {
      _sub?.cancel();
      _sub = widget.stream.listen(_enqueue);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _dismiss?.cancel();
    super.dispose();
  }

  void _enqueue(Achievement achievement) {
    if (_queue.any((a) => a.id == achievement.id) || _showing?.id == achievement.id) return;
    _queue.add(achievement);
    if (_showing == null) _advance();
  }

  void _advance() {
    _dismiss?.cancel();
    if (_queue.isEmpty) {
      if (mounted) setState(() => _showing = null);
      return;
    }
    final next = _queue.removeAt(0);
    if (!mounted) return;
    setState(() => _showing = next);
    widget.onShown?.call(next);
    _dismiss = Timer(_kHold, _advance);
  }

  @override
  Widget build(BuildContext context) {
    final showing = _showing;
    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          // A collapsed overlay in a Positioned still receives tight
          // constraints and would eat clicks, so the empty state is inert.
          child: IgnorePointer(
            ignoring: showing == null,
            child: AnimatedSwitcher(
              duration: PTMotion.functional(context, PTMotion.panel),
              switchInCurve: PTMotion.arrive,
              switchOutCurve: PTMotion.exit,
              transitionBuilder: (child, animation) => SlideTransition(
                position: Tween(begin: const Offset(0, 0.6), end: Offset.zero).animate(animation),
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: showing == null
                  ? const SizedBox(key: ValueKey('none'), width: double.infinity, height: 0)
                  : Padding(
                      key: ValueKey(showing.id),
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                      child: Center(
                        child: UnlockCard(achievement: showing, onTap: _advance),
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class UnlockCard extends StatelessWidget {
  const UnlockCard({super.key, required this.achievement, this.onTap});

  final Achievement achievement;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colour = gradeColor(achievement.grade);
    return ConstrainedBox(
      // Never wider than the window less a 16px gutter each side.
      constraints: BoxConstraints(maxWidth: math.min(420, MediaQuery.sizeOf(context).width - 32)),
      child: Material(
        type: .transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: GlassPanel(
            radius: 20,
            opacity: 0.8,
            baseColor: PTColors.dialogGlassBase,
            borderColor: colour.withValues(alpha: 0.4),
            padding: const EdgeInsets.fromLTRB(18, 16, 20, 16),
            child: Row(
              mainAxisSize: .min,
              spacing: 14,
              children: [
                // Stamped onto the card just after it lands - the badge is
                // the news, so it gets the one arrival beat.
                StampIn(
                  angle: -0.1,
                  delay: const Duration(milliseconds: 160),
                  child: BadgeArt(
                    size: 52,
                    achievementId: achievement.id,
                    fallbackIcon: achievement.icon,
                    fallbackColor: colour,
                  ),
                ),
                Flexible(
                  child: Column(
                    mainAxisSize: .min,
                    crossAxisAlignment: .start,
                    spacing: 2,
                    children: [
                      Text(
                        'BADGE UNLOCKED',
                        style: PTText.finePrint.copyWith(
                          fontSize: 11,
                          color: colour,
                          fontWeight: .w600,
                          letterSpacing: 0.6,
                        ),
                      ),
                      Text(achievement.title, style: PTText.cardHeading.copyWith(fontSize: 16)),
                      Text(
                        achievement.description,
                        style: PTText.caption.copyWith(fontSize: 12),
                        maxLines: 2,
                        overflow: .ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
