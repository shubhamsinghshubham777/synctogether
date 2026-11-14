import 'package:flutter/widgets.dart';

import 'pt_theme.dart';

/// The dim behind the coach mark, with a hole where the lit button is.
///
/// One cheap fill (no blur, no filter, no layer): the window rectangle and the
/// hole drawn together even-odd, so the button shows through untouched. It
/// repaints from [fade] alone, so a fade costs no rebuilds.
///
/// Taps: a tap on the dimmed part is [onTap]; a tap in the hole is not ours at
/// all - the painter reports "not hit" there, so the bug button underneath gets
/// the tap. The scrim carries no semantics (it is decoration, the card is the
/// content).
class CoachScrim extends StatelessWidget {
  const CoachScrim({super.key, required this.fade, required this.hole, required this.onTap});

  final Animation<double> fade;

  /// The lit area, in this widget's own coordinates (the window's).
  final RRect hole;
  final VoidCallback onTap;

  /// How dark the dim is at full fade.
  static const dim = 0.58;

  /// How far the hole stands off the ring, so the ring is lit, not shadowed.
  static const holeGap = 2.0;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: GestureDetector(
          onTap: onTap,
          child: CustomPaint(
            size: Size.infinite,
            painter: CoachScrimPainter(fade: fade, hole: hole),
          ),
        ),
      ),
    );
  }
}

class CoachScrimPainter extends CustomPainter {
  CoachScrimPainter({required this.fade, required this.hole}) : super(repaint: fade);

  final Animation<double> fade;
  final RRect hole;

  /// The dim's opacity right now (0 to [CoachScrim.dim]).
  double get opacity => CoachScrim.dim * fade.value.clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final a = opacity;
    if (a <= 0) return;
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRRect(hole),
      Paint()..color = PTColors.scrimBase.withValues(alpha: a),
    );
  }

  @override
  bool? hitTest(Offset position) => !hole.contains(position);

  @override
  bool shouldRepaint(CoachScrimPainter old) => old.hole != hole || old.fade != fade;
}
