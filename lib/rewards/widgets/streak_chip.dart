import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../ui/glass.dart';
import '../../ui/pt_theme.dart';
import '../rewards_logic.dart';
import '../rewards_models.dart';

/// The lobby's streak affordance, sitting beside the premium and quota chips.
///
/// It renders a *state*, never a nag: the ring fills as today's qualifying
/// minutes accrue, the flame lights once the day counts, and nothing here ever
/// summons the user. A streak that chases you is the reason streak features
/// have the reputation they do - so there is no notification, and the only
/// place this can be seen is inside an app the user already chose to open.
class StreakChip extends StatelessWidget {
  const StreakChip({
    super.key,
    required this.streak,
    this.onTap,
    this.compact = false,
    this.atRisk = false,
    this.locked = false,
  });

  final StreakState streak;
  final VoidCallback? onTap;
  final bool compact;
  final bool atRisk;

  /// Guests. Shown rather than hidden, because a guest cannot discover a reason
  /// to sign in from a chip that is not there - but dimmed and inert-looking, so
  /// it reads as an offer rather than as something broken. Tapping it opens the
  /// board, which is where the sign-in card lives.
  final bool locked;

  @override
  Widget build(BuildContext context) {
    if (locked) return _locked(context);
    final lit = streak.current > 0;
    final progress = streakDayProgress(streak);
    final colour = !lit
        ? PTColors.white(0.55)
        : atRisk
        ? PTColors.warning
        : PTColors.streak;

    return GlassPill(
      onTap: onTap,
      padding: EdgeInsets.symmetric(horizontal: compact ? 9 : 12, vertical: 7),
      child: Row(
        mainAxisSize: .min,
        spacing: 7,
        children: [
          SizedBox.square(
            dimension: 18,
            child: Stack(
              alignment: .center,
              children: [
                if (streak.qualifiedToday)
                  Icon(Symbols.local_fire_department_rounded, size: 17, fill: 1, color: colour)
                else ...[
                  // Determinate, so this is the documented exception to the
                  // PTLoader rule rather than a stray spinner - it reports how
                  // much of today's qualifying time is done, not that something
                  // is pending. Same reasoning as PTBanner's dismiss ring.
                  CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 2,
                    backgroundColor: PTColors.white(0.12),
                    valueColor: AlwaysStoppedAnimation(colour),
                  ),
                  Icon(Symbols.local_fire_department_rounded, size: 10, fill: 1, color: colour),
                ],
              ],
            ),
          ),
          Text(
            lit
                ? (compact ? '${streak.current}' : '${streak.current} day streak')
                : (compact ? 'Start' : 'Start a streak'),
            style: PTText.body.copyWith(
              fontSize: 13,
              fontWeight: .w600,
              color: lit ? PTColors.white(0.9) : PTColors.white(0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _locked(BuildContext context) {
    return Opacity(
      opacity: 0.62,
      child: GlassPill(
        onTap: onTap,
        padding: EdgeInsets.symmetric(horizontal: compact ? 9 : 12, vertical: 7),
        child: Row(
          mainAxisSize: .min,
          spacing: 7,
          children: [
            Icon(
              Symbols.local_fire_department_rounded,
              size: 17,
              fill: 1,
              color: PTColors.white(0.45),
            ),
            Text(
              compact ? 'Streaks' : 'Sign in for streaks',
              style: PTText.body.copyWith(
                fontSize: 13,
                fontWeight: .w600,
                color: PTColors.white(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
