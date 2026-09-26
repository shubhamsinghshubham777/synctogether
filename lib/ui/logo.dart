import 'package:flutter/material.dart';
import 'package:synctogether/ui/pt_motion.dart';
import 'package:synctogether/ui/pt_theme.dart';

/// The Booth Light brand: a lowercase wordmark whose middle dot is the Beam -
/// the one light in the room. No tile, no gradient.
///
/// On pointer hover the dot warms up (grows and spills light), like a
/// projector lamp coming on. It is an implicit tween, so it costs nothing at
/// rest. The website's `Logo` mirrors it (`website/components/Logo.tsx`).
class PTWordmark extends StatefulWidget {
  const PTWordmark({super.key, this.size = 22});

  final double size;

  @override
  State<PTWordmark> createState() => _PTWordmarkState();
}

class _PTWordmarkState extends State<PTWordmark> {
  bool _warm = false;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: PTFonts.display,
      fontSize: widget.size,
      fontWeight: .w800,
      letterSpacing: -widget.size * 0.035,
      height: 1,
      color: PTColors.fg,
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _warm = true),
      onExit: (_) => setState(() => _warm = false),
      child: Semantics(
        label: 'SyncTogether',
        excludeSemantics: true,
        child: Row(
          mainAxisSize: .min,
          children: [
            Text('sync', style: style),
            TweenAnimationBuilder<double>(
              tween: Tween(end: _warm ? 1 : 0),
              duration: PTMotion.functional(context, PTMotion.state),
              curve: PTMotion.enter,
              builder: (context, t, _) => Transform.scale(
                scale: 1 + 0.25 * t,
                child: Text(
                  '·',
                  style: style.copyWith(
                    color: PTColors.primary,
                    shadows: [
                      Shadow(color: PTColors.primary.withValues(alpha: 0.9 * t), blurRadius: 14),
                    ],
                  ),
                ),
              ),
            ),
            Text('together', style: style),
          ],
        ),
      ),
    );
  }
}

/// The square mark - the wordmark compressed to "s·t" on a Booth tile. Used
/// where a square is required: the app icon (tool/generate_app_icon.py draws
/// the same letters from the same font), the splash, empty video frames.
class PTLogoMark extends StatelessWidget {
  const PTLogoMark({super.key, this.size = 40, this.glyphOpacity = 1});

  final double size;

  /// Lets the splash fade the letters in while the tile springs.
  final double glyphOpacity;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: PTFonts.display,
      fontSize: size * 0.46,
      fontWeight: .w800,
      letterSpacing: -size * 0.02,
      height: 1,
      color: PTColors.fg.withValues(alpha: glyphOpacity),
    );
    return Container(
      width: size,
      height: size,
      alignment: .center,
      decoration: BoxDecoration(
        color: PTColors.canvas,
        borderRadius: BorderRadius.circular(size * 0.24),
        border: Border.all(color: PTColors.rail, width: size / 64),
      ),
      child: Text.rich(
        TextSpan(
          style: style,
          children: [
            const TextSpan(text: 's'),
            TextSpan(
              text: '·',
              style: TextStyle(color: PTColors.primary.withValues(alpha: glyphOpacity)),
            ),
            const TextSpan(text: 't'),
          ],
        ),
      ),
    );
  }
}
