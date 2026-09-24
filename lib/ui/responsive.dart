import 'dart:ui' show DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';

import '../platform.dart';

/// Layout classes. Two questions decide it - how much room there is, and what
/// drives input - because width alone put iPads on the mouse-first desktop
/// layout and iPad minis on a stretched phone one.
enum PTLayout { desktop, tablet, portrait, landscape }

/// Pointer-first (mouse/trackpad on the desktop targets) vs touch-first.
enum PTInput { pointer, touch }

/// Pointer windows at or above this width get [PTLayout.desktop].
const kDesktopMinWidth = 840.0;

/// Touch windows whose shortest side reaches this get [PTLayout.tablet]
/// (Material's compact/medium boundary). An iPad in 1/3 split view falls
/// under it and correctly becomes a phone layout.
const kTabletMinShortestSide = 600.0;

/// Below this height a layout is "compact height": phone landscape, and each
/// half of a tabletop-folded phone.
const kCompactHeight = 480.0;

/// Minimum window size for desktop platforms to prevent layout squishing
/// and control overflow.
const kDesktopMinWindowSize = Size(900, 600);

PTInput inputOf(BuildContext context) => isDesktop ? .pointer : .touch;

/// Pure form of [layoutOf], so the classification is testable as a table.
PTLayout classifyLayout(Size size, PTInput input) {
  if (input == .pointer) {
    if (size.width >= kDesktopMinWidth) return .desktop;
  } else if (size.shortestSide >= kTabletMinShortestSide) {
    return .tablet;
  }
  return size.width > size.height ? .landscape : .portrait;
}

PTLayout layoutOf(BuildContext context) =>
    classifyLayout(MediaQuery.sizeOf(context), inputOf(context));

bool isCompactHeight(BuildContext context) => MediaQuery.sizeOf(context).height < kCompactHeight;

/// A fold or hinge that splits the window into two panes.
enum PTFoldAxis { none, vertical, horizontal }

class PTFold {
  const PTFold._(this.axis, this.bounds);

  static const none = PTFold._(.none, Rect.zero);

  /// [vertical]: the hinge runs top-to-bottom (book posture, panes left/right).
  /// [horizontal]: it runs left-to-right (tabletop, panes top/bottom).
  final PTFoldAxis axis;

  /// The hinge's rect in window coordinates; may be zero-width for a fold.
  final Rect bounds;

  bool get isSplit => axis != .none;
}

/// Reads the window's fold. A flat-open fold with no hinge area splits
/// nothing - the display is continuous - so only a half-opened fold or a
/// physical hinge counts.
PTFold foldOf(BuildContext context) {
  for (final f in MediaQuery.displayFeaturesOf(context)) {
    final splits =
        f.type == DisplayFeatureType.hinge ||
        (f.type == DisplayFeatureType.fold && f.state == DisplayFeatureState.postureHalfOpened);
    if (!splits) continue;
    final b = f.bounds;
    return PTFold._(b.height >= b.width ? .vertical : .horizontal, b);
  }
  return PTFold.none;
}

/// Kept as the `MaterialApp.builder` hook (and the tests' wrapper) so the app
/// has one place to install app-wide layout policy.
Widget buildResponsiveWrapper(BuildContext context, Widget? child) =>
    child ?? const SizedBox.shrink();

/// Chooses the per-layout builder. Fallbacks: tablet→desktop→landscape→portrait,
/// desktop→landscape→portrait, landscape→desktop→portrait.
class PTResponsive extends StatelessWidget {
  const PTResponsive({
    super.key,
    required this.portrait,
    this.landscape,
    this.desktop,
    this.tablet,
  });

  final WidgetBuilder portrait;
  final WidgetBuilder? landscape;
  final WidgetBuilder? desktop;
  final WidgetBuilder? tablet;

  @override
  Widget build(BuildContext context) {
    return switch (layoutOf(context)) {
      .desktop => (desktop ?? landscape ?? portrait)(context),
      .tablet => (tablet ?? desktop ?? landscape ?? portrait)(context),
      .landscape => (landscape ?? desktop ?? portrait)(context),
      .portrait => portrait(context),
    };
  }
}
