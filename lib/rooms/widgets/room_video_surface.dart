import 'package:flutter/material.dart';
import 'package:synctogether/ui/booth_icons.g.dart';
import 'package:synctogether/ui/pt_motion.dart';
import 'package:synctogether/ui/pt_theme.dart';

/// Wraps video for touch layouts: double-tapping left/right skips backward/forward.
class RoomSkipZones extends StatelessWidget {
  const RoomSkipZones({
    required this.child,
    required this.onTap,
    required this.onSkip,
    required this.onToggleFullscreen,
    required this.isDesktop,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final ValueChanged<Duration> onSkip;
  final VoidCallback onToggleFullscreen;
  final bool isDesktop;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        TapDownDetails? down;
        return GestureDetector(
          behavior: .opaque,
          onTap: onTap,
          onDoubleTapDown: (d) => down = d,
          onDoubleTap: () {
            final dx = down?.localPosition.dx ?? width / 2;
            if (dx < width / 3) {
              onSkip(const Duration(seconds: -10));
            } else if (dx > width * 2 / 3) {
              onSkip(const Duration(seconds: 10));
            } else if (isDesktop) {
              onToggleFullscreen();
            }
          },
          child: child,
        );
      },
    );
  }
}

/// Circular badge that flashes on screen when a 10-second skip occurs.
class RoomSkipFlashBadge extends StatelessWidget {
  const RoomSkipFlashBadge({required this.backward, this.animationKey, super.key});

  final bool backward;
  final Object? animationKey;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(animationKey),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 650),
      curve: Curves.linear,
      builder: (_, t, child) => Opacity(
        opacity: 1 - Curves.easeIn.transform(t),
        child: Transform.scale(
          scale: 0.85 + 0.15 * PTMotion.enter.transform((t * 4).clamp(0.0, 1.0)),
          child: child,
        ),
      ),
      child: Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(color: PTColors.black(0.42), shape: .circle),
        child: Column(
          mainAxisAlignment: .center,
          spacing: 2,
          children: [
            Icon(backward ? BoothIcons.replay : BoothIcons.forward, size: 32, color: Colors.white),
            Text('10s', style: PTText.mono.copyWith(fontSize: 12, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}
