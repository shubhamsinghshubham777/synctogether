import 'package:material_ui/material_ui.dart';

import 'pt_motion.dart';
import 'pt_theme.dart';

/// A determinate progress bar whose fill glides to each new value and whose colour
/// eases when the state changes (Beam to warning, to done, to failed), instead of
/// jumping with every update. Every progress bar in the app is this one.
///
/// Costs nothing at rest: the tweens only run while the value or colour is moving.
class PTProgressBar extends StatelessWidget {
  const PTProgressBar({
    super.key,
    required this.value,
    this.color = PTColors.primary,
    this.track = PTColors.aisle,
    this.height = 4,
    this.radius = 2,
  });

  /// 0..1.
  final double value;
  final Color color;
  final Color track;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final duration = PTMotion.functional(context, PTMotion.state);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: color),
        duration: duration,
        curve: PTMotion.enter,
        builder: (context, tint, _) => TweenAnimationBuilder<double>(
          tween: Tween(end: value.clamp(0.0, 1.0)),
          duration: duration,
          curve: PTMotion.enter,
          builder: (context, fraction, _) => LinearProgressIndicator(
            value: fraction,
            minHeight: height,
            backgroundColor: track,
            valueColor: AlwaysStoppedAnimation(tint ?? color),
          ),
        ),
      ),
    );
  }
}
