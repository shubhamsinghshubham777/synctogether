import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';

import '../platform.dart';
import 'pt_theme.dart';

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
PTFold foldOf(BuildContext context) => foldFromFeatures(MediaQuery.displayFeaturesOf(context));

/// Pure form of [foldOf], so the rule is testable as a table.
PTFold foldFromFeatures(List<DisplayFeature> features) {
  for (final f in features) {
    final splits =
        f.type == DisplayFeatureType.hinge ||
        (f.type == DisplayFeatureType.fold && f.state == DisplayFeatureState.postureHalfOpened);
    if (!splits) continue;
    final b = f.bounds;
    return PTFold._(b.height >= b.width ? .vertical : .horizontal, b);
  }
  return PTFold.none;
}

/// A tabletop's lower pane has to be at least this tall to host a one-column
/// screen; a fold set very low leaves the larger pane to do it instead.
const kMinLowerPaneHeight = 240.0;

/// The panes of a window of [size] under [fold]: the whole window when nothing
/// splits it, else two rects in reading order (left/right, top/bottom) with the
/// hinge rect itself left out. Pure, so it is testable as a table.
List<Rect> panesOf(Size size, PTFold fold) {
  final whole = Offset.zero & size;
  if (!fold.isSplit) return [whole];
  final b = fold.bounds;
  if (fold.axis == .vertical) {
    final start = b.left.clamp(0.0, size.width);
    final end = b.right.clamp(start, size.width);
    return [
      Rect.fromLTRB(0, 0, start, size.height),
      Rect.fromLTRB(end, 0, size.width, size.height),
    ];
  }
  final start = b.top.clamp(0.0, size.height);
  final end = b.bottom.clamp(start, size.height);
  return [Rect.fromLTRB(0, 0, size.width, start), Rect.fromLTRB(0, end, size.width, size.height)];
}

/// The pane a one-column screen or a dialog lives in. [anchor] (window
/// coordinates, e.g. the button a dialog opened from) picks the pane that holds
/// it; without one the rule is: the larger pane, the first when they match; and
/// in a tabletop the lower one - the half on the table, within reach - unless
/// the fold sits so low that it is under [kMinLowerPaneHeight].
Rect primaryPaneOf(Size size, PTFold fold, {Offset? anchor}) {
  final panes = panesOf(size, fold);
  if (panes.length == 1) return panes.single;
  if (anchor != null) {
    for (final p in panes) {
      if (p.contains(anchor)) return p;
    }
  }
  if (fold.axis == .horizontal && panes.last.height >= kMinLowerPaneHeight) return panes.last;
  final a = panes.first.width * panes.first.height;
  final b = panes.last.width * panes.last.height;
  return b > a + 1 ? panes.last : panes.first;
}

/// Lays [child] out in [rect] (window coordinates) as if that were the whole
/// window: its `MediaQuery` carries the pane's size, the insets that really
/// reach the pane and no display features, so `layoutOf`, `SafeArea` and every
/// size-driven choice inside answers for the pane and not for the window.
/// Must sit where it is given the whole window to fill. The same widgets wrap
/// [child] for a whole-window rect, so changing [rect] never remounts it.
class PTPane extends StatelessWidget {
  const PTPane({super.key, required this.rect, required this.child});

  final Rect rect;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final window = mq.size;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        rect.left,
        rect.top,
        window.width - rect.right,
        window.height - rect.bottom,
      ),
      child: _PaneOrigin(
        origin: rect.topLeft,
        child: MediaQuery(
          data: mq.removeDisplayFeatures(rect).copyWith(size: rect.size),
          child: child,
        ),
      ),
    );
  }

  /// Where the nearest enclosing pane starts in window coordinates (zero
  /// outside any pane). A widget that positions itself from a window-space rect
  /// - a popover anchored to a button's `localToGlobal` - subtracts this.
  static Offset originOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PaneOrigin>()?.origin ?? Offset.zero;
}

class _PaneOrigin extends InheritedWidget {
  const _PaneOrigin({required this.origin, required super.child});

  final Offset origin;

  @override
  bool updateShouldNotify(_PaneOrigin old) => old.origin != origin;
}

/// Keeps a one-column screen off the hinge: it takes [primaryPaneOf] and the
/// rest of the window is plain canvas. The wrapper chain is the same whether
/// or not a fold splits the window, so a fold opening or closing resizes the
/// screen instead of remounting it (half-typed fields survive).
class PTHingeSafe extends StatelessWidget {
  const PTHingeSafe({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final pane = primaryPaneOf(MediaQuery.sizeOf(context), foldOf(context));
    return ColoredBox(
      color: PTColors.canvas,
      child: PTPane(rect: pane, child: child),
    );
  }
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
