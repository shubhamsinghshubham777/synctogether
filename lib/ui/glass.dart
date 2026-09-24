import 'dart:ui';

import 'package:flutter/material.dart';

import 'pt_motion.dart';
import 'pt_theme.dart';

/// Glass recipe: bg rgba(22,18,38,.5–.6) · blur(28–32) saturate(160%) ·
/// border 1px white @ .13 · radius 20–28 · shadow 0 20 56 @ .5.
/// Never stack glass on glass more than two deep.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.radius = 22,
    this.opacity = 0.55,
    this.blur = 28,
    this.baseColor,
    this.borderColor,
    this.padding,
    this.shadow = true,
    this.clipBehavior = Clip.antiAlias,
  });

  /// Dialog-grade glass (denser, over a scrim).
  const GlassPanel.dialog({
    super.key,
    required this.child,
    this.radius = 24,
    this.opacity = 0.78,
    this.blur = 32,
    this.baseColor = PTColors.dialogGlassBase,
    this.borderColor,
    this.padding,
    this.shadow = true,
    this.clipBehavior = Clip.antiAlias,
  });

  final Widget child;
  final double radius;
  final double opacity;
  final double blur;
  final Color? baseColor;
  final Color? borderColor;
  final EdgeInsetsGeometry? padding;
  final bool shadow;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: shadow
            ? [BoxShadow(color: PTColors.black(0.5), blurRadius: 56, offset: const Offset(0, 20))]
            : null,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        clipBehavior: clipBehavior,
        child: BackdropFilter(
          filter: ImageFilter.compose(
            outer: ImageFilter.blur(sigmaX: blur / 2, sigmaY: blur / 2),
            inner: const ColorFilter.matrix(_saturation160),
          ),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: (baseColor ?? PTColors.glassBase).withValues(alpha: opacity),
              borderRadius: borderRadius,
              border: Border.all(color: borderColor ?? PTColors.white(0.13)),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

// saturate(160%) as a color matrix (Rec. 709 luma weights).
const _saturation160 = <double>[
  0.8726, 0.4290, 0.0983, 0, 0, //
  0.1274, 1.1741, 0.0983, 0, 0, //
  0.1274, 0.4290, 1.4434, 0, 0, //
  0, 0, 0, 1, 0,
];

class GlassPill extends StatelessWidget {
  const GlassPill({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
    this.onTap,
    this.opacity = 0.55,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final pill = GlassPanel(
      radius: 999,
      opacity: opacity,
      blur: 24,
      padding: padding,
      child: child,
    );
    if (onTap == null) return pill;
    // Scale, never fade: PTPressable animates a Transform, which leaves the
    // pill's BackdropFilter sampling a real backdrop.
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: PTPressable(onTap: onTap, child: pill),
    );
  }
}

/// Ambient violet glow blobs behind empty screens (Login, Lobby, Profile).
/// Never used in the room - nothing ambient may move near playing video.
///
/// Static atmospheric rendering allows Flutter to cache the backdrop raster
/// layer once, dropping idle CPU from ~33% to ~0% and avoiding continuous
/// multi-pass BackdropFilter re-blurring.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: PTColors.screenBg),
      child: Stack(
        fit: .expand,
        clipBehavior: Clip.hardEdge,
        children: [
          const Positioned(
            top: -180,
            left: -120,
            child: _GlowBlob(size: 640, color: PTColors.glowDeep, blur: 110),
          ),
          const Positioned(
            bottom: -220,
            right: -100,
            child: _GlowBlob(size: 720, color: PTColors.glowEnd, blur: 120),
          ),
          const Positioned(
            top: 270,
            right: 300,
            child: _GlowBlob(size: 280, color: PTColors.glowIndigo, blur: 90),
          ),
          child,
        ],
      ),
    );
  }
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.size, required this.color, required this.blur});

  final double size;
  final Color color;
  final double blur;

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: blur / 2, sigmaY: blur / 2),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: .circle, color: color),
      ),
    );
  }
}

/// Shows a dialog with the standard dark scrim + blur, glass shell provided by
/// [GlassPanel.dialog]. All redesigned dialogs go through this.
///
/// The shell owns fitting the dialog to the screen, so call sites only pick a
/// [width]:
/// - a 16px gutter on every side (plus safe area), so [width] is a cap, never
///   a demand - a 430 dialog on a 320 phone is 288 wide;
/// - the height stops at the keyboard, and follows it as it animates;
/// - the body scrolls by default. Pass `scrollable: false` for a body that
///   manages its own scrolling with a `Flexible`/`Expanded` child - those need
///   a bounded height, which a scroll view cannot give them;
/// - the default horizontal padding (and any explicit padding over 20) drops
///   to 20 below 400 logical pixels of screen width;
/// - `sheetOnCompact: true` presents it as a bottom sheet under 480 width, for
///   long forms that read better thumb-side on a phone.
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  double width = 430,
  EdgeInsetsGeometry? padding,
  bool scrollable = true,
  bool sheetOnCompact = false,
}) {
  bool isSheet(BuildContext context) =>
      sheetOnCompact && MediaQuery.sizeOf(context).width < kGlassSheetBreakpoint;

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: 'dialog',
    barrierColor: PTColors.barrier,
    transitionDuration: PTMotion.panel,
    pageBuilder: (context, _, _) {
      final mq = MediaQuery.of(context);
      final sheet = isSheet(context);
      final inset = glassDialogInsets(mq);
      final bodyPadding = glassDialogPadding(padding, mq.size.width);
      return AnimatedPadding(
        duration: PTMotion.functional(context, PTMotion.state),
        curve: PTMotion.enter,
        padding: inset,
        child: MediaQuery.removeViewInsets(
          context: context,
          removeBottom: true,
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            removeBottom: true,
            removeLeft: true,
            removeRight: true,
            child: Align(
              alignment: sheet ? .bottomCenter : .center,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: sheet ? double.infinity : width),
                child: Material(
                  type: .transparency,
                  child: GlassPanel.dialog(
                    padding: scrollable ? null : bodyPadding,
                    child: scrollable
                        ? SingleChildScrollView(padding: bodyPadding, child: builder(context))
                        : builder(context),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: PTMotion.enter,
        reverseCurve: PTMotion.exit,
      );
      // Scale for a centred dialog, slide for a sheet. The fade is on the
      // route (scrim + panel together), not on the glass, which keeps the
      // panel's BackdropFilter sampling a real backdrop once it lands.
      final Widget moved = isSheet(context)
          ? SlideTransition(
              position: Tween(begin: const Offset(0, 0.12), end: Offset.zero).animate(curved),
              child: child,
            )
          : ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(curved), child: child);
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6 * animation.value, sigmaY: 6 * animation.value),
        child: FadeTransition(opacity: curved, child: moved),
      );
    },
  );
}

/// Below this width a `sheetOnCompact` dialog presents as a bottom sheet.
const double kGlassSheetBreakpoint = 480;

/// Below this width dialog padding tightens to [_compactHorizontalPadding].
const double kGlassCompactPaddingBreakpoint = 400;
const double _compactHorizontalPadding = 20;
const double _gutter = 16;

/// Space kept clear around a glass dialog: a 16px gutter inside the safe area,
/// and above the keyboard when it is up (the keyboard covers the bottom safe
/// area, so the two are not added).
@visibleForTesting
EdgeInsets glassDialogInsets(MediaQueryData mq) {
  final bottom = mq.viewInsets.bottom > mq.viewPadding.bottom
      ? mq.viewInsets.bottom
      : mq.viewPadding.bottom;
  return EdgeInsets.fromLTRB(
    mq.viewPadding.left + _gutter,
    mq.viewPadding.top + _gutter,
    mq.viewPadding.right + _gutter,
    bottom + _gutter,
  );
}

/// The dialog body's padding at [screenWidth]: the caller's (or the 32/30
/// default), with horizontal padding capped at 20 on narrow screens.
@visibleForTesting
EdgeInsets glassDialogPadding(EdgeInsetsGeometry? padding, double screenWidth) {
  final base = (padding ?? const EdgeInsets.symmetric(horizontal: 32, vertical: 30)).resolve(
    TextDirection.ltr,
  );
  if (screenWidth >= kGlassCompactPaddingBreakpoint) return base;
  return base.copyWith(
    left: base.left > _compactHorizontalPadding ? _compactHorizontalPadding : base.left,
    right: base.right > _compactHorizontalPadding ? _compactHorizontalPadding : base.right,
  );
}
