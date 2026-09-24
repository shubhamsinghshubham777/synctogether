import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show HitTestResult;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/ui/pt_theme.dart';
import 'package:synctogether/ui/responsive.dart';

/// One device shape for the layout matrix (`test/layout/`).
class ScreenCase {
  const ScreenCase(
    this.name,
    this.size,
    this.platform, {
    this.padding = EdgeInsets.zero,
    this.keyboard = 0,
    this.features = const [],
  });

  final String name;
  final Size size;
  final TargetPlatform platform;

  /// Safe-area insets (notch, home indicator).
  final EdgeInsets padding;

  /// Soft-keyboard height, applied as `viewInsets.bottom`.
  final double keyboard;
  final List<DisplayFeature> features;

  @override
  String toString() => name;
}

// Realistic system insets. Top is the status bar, bottom the home indicator
// (iOS) or the navigation bar: 24 for Android gesture nav, 48 for 3-button.
const _notchPortrait = EdgeInsets.only(top: 47, bottom: 34);
const _notchLandscape = EdgeInsets.only(left: 47, right: 47, bottom: 21);
const _ipad = EdgeInsets.only(top: 24, bottom: 20);
const _androidGesture = EdgeInsets.only(top: 24, bottom: 24);
const _android3Button = EdgeInsets.only(top: 48, bottom: 48);
// Landscape Android: the cutout sits on the left (rotated clockwise), the
// status bar stays on top and gesture nav along the bottom.
const _androidLandCutout = EdgeInsets.only(left: 32, top: 24, bottom: 24);

final kScreenMatrix = <ScreenCase>[
  const ScreenCase('phone-small', Size(320, 568), .iOS, padding: EdgeInsets.only(top: 20)),
  const ScreenCase('phone-android', Size(360, 800), .android, padding: _androidGesture),
  const ScreenCase('phone-android-3button', Size(412, 915), .android, padding: _android3Button),
  const ScreenCase('phone', Size(390, 844), .iOS, padding: _notchPortrait),
  const ScreenCase('phone-land', Size(844, 390), .iOS, padding: _notchLandscape),
  const ScreenCase('phone-android-land', Size(800, 360), .android, padding: _androidLandCutout),
  const ScreenCase('phone-se-land', Size(667, 375), .iOS),
  const ScreenCase('phone-keyboard', Size(390, 844), .iOS, padding: _notchPortrait, keyboard: 336),
  const ScreenCase(
    'phone-android-keyboard',
    Size(412, 915),
    .android,
    padding: _android3Button,
    keyboard: 320,
  ),
  const ScreenCase(
    'phone-land-keyboard',
    Size(844, 390),
    .android,
    padding: _androidLandCutout,
    keyboard: 200,
  ),
  const ScreenCase('ipad-mini', Size(744, 1133), .iOS, padding: _ipad),
  const ScreenCase('ipad', Size(820, 1180), .iOS, padding: _ipad),
  const ScreenCase('ipad-land', Size(1180, 820), .iOS, padding: _ipad),
  const ScreenCase('ipad-pro-13', Size(1032, 1376), .iOS, padding: _ipad),
  const ScreenCase('ipad-split-third', Size(320, 1024), .iOS, padding: _ipad),
  const ScreenCase('fold-unfolded', Size(882, 1104), .android, padding: _androidGesture),
  const ScreenCase(
    'fold-book',
    Size(1080, 960),
    .android,
    padding: _androidGesture,
    features: [
      DisplayFeature(
        bounds: Rect.fromLTWH(538, 0, 4, 960),
        type: DisplayFeatureType.hinge,
        state: DisplayFeatureState.postureFlat,
      ),
    ],
  ),
  const ScreenCase(
    'fold-tabletop',
    Size(882, 1104),
    .android,
    padding: _androidGesture,
    features: [
      DisplayFeature(
        bounds: Rect.fromLTWH(0, 552, 882, 0),
        type: DisplayFeatureType.fold,
        state: DisplayFeatureState.postureHalfOpened,
      ),
    ],
  ),
  const ScreenCase('fold-cover', Size(344, 882), .android, padding: _androidGesture),
  const ScreenCase('desktop-min', Size(900, 600), .macOS),
  const ScreenCase('desktop', Size(1440, 900), .macOS),
  const ScreenCase('desktop-wide', Size(2560, 1080), .windows),
];

const kTextScales = [1.0, 1.5, 2.0];

/// Pumps [child] as [c] at [textScale], dressed the way `MainApp` dresses it.
/// Returns once the first frames are in; never `pumpAndSettle`s, since loaders
/// and the splash animate forever.
Future<void> pumpAtSize(
  WidgetTester tester,
  Widget child,
  ScreenCase c, {
  double textScale = 1.0,
  bool wrapInApp = true,
}) async {
  debugDefaultTargetPlatformOverride = c.platform;
  tester.view
    ..physicalSize = c.size
    ..devicePixelRatio = 1.0
    // The engine reports `padding` as viewPadding with the keyboard taken
    // out: the home indicator / nav bar sits behind an open keyboard.
    ..padding = FakeViewPadding(
      left: c.padding.left,
      top: c.padding.top,
      right: c.padding.right,
      bottom: (c.padding.bottom - c.keyboard).clamp(0, double.infinity),
    )
    ..viewPadding = FakeViewPadding(
      left: c.padding.left,
      top: c.padding.top,
      right: c.padding.right,
      bottom: c.padding.bottom,
    )
    ..viewInsets = FakeViewPadding(bottom: c.keyboard)
    ..displayFeatures = c.features;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  // Callers outside [screenMatrix] must also null
  // `debugDefaultTargetPlatformOverride` before their body returns: this
  // tearDown runs after the binding's debug-variable invariant check.
  addTearDown(() {
    debugDefaultTargetPlatformOverride = null;
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
  await tester.pumpWidget(
    wrapInApp
        ? MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildPTTheme(),
            builder: buildResponsiveWrapper,
            home: child,
          )
        : child,
  );
  await tester.pump(const Duration(milliseconds: 400));
}

/// Fails the test on any overflow or layout error collected during the pump.
///
void expectNoOverflow(WidgetTester tester) {
  final errors = <Object>[];
  Object? e;
  while ((e = tester.takeException()) != null) {
    errors.add(e!);
  }
  expect(errors, isEmpty, reason: errors.map(_describeError).join('\n---\n'));
}

bool _insetCheckActive = false;

/// Whether the running [screenMatrix] case checks insets (the default; a case
/// opts out with `checkInsets: false`). `finishCase` reads it.
bool get insetCheckActive => _insetCheckActive;

/// The rect content may put controls in: the screen minus `viewPadding`
/// (status bar, notch/cutout, home indicator, nav bar) and minus the keyboard.
Rect safeRectOf(WidgetTester tester) {
  final view = tester.view;
  final dpr = view.devicePixelRatio;
  final size = view.physicalSize / dpr;
  final pad = view.viewPadding;
  final kb = view.viewInsets.bottom / dpr;
  final bottom = (pad.bottom / dpr) > kb ? pad.bottom / dpr : kb;
  return Rect.fromLTRB(
    pad.left / dpr,
    pad.top / dpr,
    size.width - pad.right / dpr,
    size.height - bottom,
  );
}

bool _isInteractive(Widget w) => switch (w) {
  InkResponse(:final onTap, :final onLongPress) => onTap != null || onLongPress != null,
  GestureDetector(:final onTap, :final onLongPress) => onTap != null || onLongPress != null,
  EditableText() => true,
  _ => false,
};

const _eps = 0.5;

/// A surface, not a control: it spans the whole screen (or the whole of a
/// fold pane) along one axis and covers at least a quarter of it - the video,
/// a background, a scrim, a tap-to-toggle layer.
bool _isFullBleed(Rect r, Rect screen, Rect safe) {
  final spansWidth = r.width >= screen.width * 0.9;
  final spansHeight = r.height >= safe.bottom * 0.9;
  return (spansWidth || spansHeight) && r.width * r.height >= screen.width * screen.height * 0.25;
}

bool _within(Rect inner, Rect outer, {bool horizontal = true, bool vertical = true}) =>
    (!horizontal || (inner.left >= outer.left - _eps && inner.right <= outer.right + _eps)) &&
    (!vertical || (inner.top >= outer.top - _eps && inner.bottom <= outer.bottom + _eps));

Rect _rectOf(RenderBox box) =>
    MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);

/// Asserts that nothing a user can touch sits under a system inset.
///
/// Every on-screen, hit-testable interactive widget (`InkWell`/`InkResponse`
/// or `GestureDetector` with a tap/long-press handler - which covers every
/// Material and PT* button - and every `EditableText`) must lie inside
/// [safeRectOf]. Full-bleed surfaces (backgrounds, the video, scrims: anything
/// spanning the screen or a fold pane along one axis and covering a quarter of
/// it) and text-selection handles are exempt.
///
/// Inside a scrollable the check along the scroll axis is replaced by a
/// reachability check: content may scroll under a bar edge-to-edge, but
/// scrolled to each end the first/last control must clear the inset. A focused
/// text field is never exempt: it must be fully visible above the keyboard.
Future<void> expectRespectsInsets(WidgetTester tester) async {
  // Flush post-frame work (focus reveals, ensureVisible) into layout first.
  await tester.pump();
  final safe = safeRectOf(tester);
  final screen = Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);
  final problems = <String>[];

  String describe(Element e) {
    final w = e.widget;
    final texts = find.descendant(
      of: find.byElementPredicate((x) => x == e),
      matching: find.byType(Text),
    );
    final t = texts.evaluate().map((x) => (x.widget as Text).data).whereType<String>().firstOrNull;
    final icons = find.descendant(
      of: find.byElementPredicate((x) => x == e),
      matching: find.byType(Icon),
    );
    final i = icons
        .evaluate()
        .map((x) => (x.widget as Icon).icon?.codePoint.toRadixString(16))
        .firstOrNull;
    final label = t != null ? '"$t"' : (i != null ? 'icon 0x$i' : null);
    final owner = e.debugGetCreatorChain(4);
    return '${w.runtimeType}${label == null ? '' : ' $label'} ($owner)';
  }

  // The render objects are the ones hit-testing sees: an element counts only
  // if some point of it on screen actually reaches it (not behind a modal
  // barrier, not in an IgnorePointer, not offstage).
  bool hitTestable(RenderBox box, Rect r) {
    final visible = r.intersect(screen);
    if (visible.width <= 0 || visible.height <= 0) return false;
    for (final p in [
      visible.center,
      visible.topLeft + const Offset(1, 1),
      visible.bottomRight - const Offset(1, 1),
    ]) {
      final result = HitTestResult();
      WidgetsBinding.instance.hitTestInView(result, p, tester.view.viewId);
      if (result.path.any((entry) => identical(entry.target, box))) return true;
    }
    return false;
  }

  final candidates = find.byWidgetPredicate(_isInteractive, skipOffstage: true).evaluate().toList();
  for (final e in candidates) {
    final ro = e.renderObject;
    if (ro is! RenderBox || !ro.attached || !ro.hasSize) continue;
    final r = _rectOf(ro);
    if (_isFullBleed(r, screen, safe)) continue;
    // Selection handles follow the caret and belong to their field.
    if (e.findAncestorWidgetOfExactType<CompositedTransformFollower>() != null) continue;
    if (!hitTestable(ro, r)) continue;
    final focused = e.widget is EditableText && (e.widget as EditableText).focusNode.hasFocus;
    final scrollable = Scrollable.maybeOf(e);
    final axis = scrollable?.position.axis;
    // Clip to the scroll viewport: a row half scrolled out of its list is
    // judged by the part that is showing.
    final viewport = scrollable == null
        ? null
        : _rectOf(scrollable.context.findRenderObject()! as RenderBox);
    final shown = viewport == null ? r : r.intersect(viewport);
    if (focused) {
      if (!_within(r, safe)) {
        problems.add(
          'focused field not fully visible above keyboard/insets: ${describe(e)} at $r, safe $safe',
        );
      }
      continue;
    }
    final ok = _within(
      shown,
      safe,
      horizontal: axis != Axis.horizontal,
      vertical: axis != Axis.vertical,
    );
    if (!ok) problems.add('${describe(e)} at $shown is outside safe area $safe');
  }

  // Reachability: scrolled to each end, a scrollable's extreme controls clear
  // the insets its viewport reaches under.
  for (final state in tester.stateList<ScrollableState>(find.byType(Scrollable)).toList()) {
    if (!state.mounted) continue;
    final pos = state.position;
    if (!pos.hasContentDimensions || !pos.hasPixels) continue;
    final box = state.context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) continue;
    final vp = _rectOf(box);
    if (!hitTestable(box, vp)) continue;
    final vertical = pos.axis == Axis.vertical;
    final underEnd = vertical ? vp.bottom > safe.bottom + _eps : vp.right > safe.right + _eps;
    final underStart = vertical ? vp.top < safe.top - _eps : vp.left < safe.left - _eps;
    if (!underEnd && !underStart) continue;
    final original = pos.pixels;
    for (final toEnd in [true, false]) {
      if (toEnd ? !underEnd : !underStart) continue;
      pos.jumpTo(toEnd ? pos.maxScrollExtent : pos.minScrollExtent);
      await tester.pump();
      final inside = find
          .descendant(
            of: find.byWidget(state.widget),
            matching: find.byWidgetPredicate(_isInteractive),
          )
          .evaluate()
          .where((e) => Scrollable.maybeOf(e) == state)
          .map((e) => (e, e.renderObject))
          .where((p) => p.$2 is RenderBox && (p.$2! as RenderBox).hasSize)
          .map((p) => (p.$1, _rectOf(p.$2! as RenderBox)))
          .where((p) => p.$2.overlaps(vp))
          .toList();
      if (inside.isEmpty) continue;
      inside.sort(
        (a, b) => vertical ? a.$2.bottom.compareTo(b.$2.bottom) : a.$2.right.compareTo(b.$2.right),
      );
      final (el, rect) = toEnd ? inside.last : inside.first;
      final clear = switch ((vertical, toEnd)) {
        (true, true) => rect.bottom <= safe.bottom + _eps,
        (true, false) => rect.top >= safe.top - _eps,
        (false, true) => rect.right <= safe.right + _eps,
        (false, false) => rect.left >= safe.left - _eps,
      };
      if (!clear) {
        problems.add(
          'scrolled to its ${toEnd ? 'end' : 'start'}, ${describe(el)} at $rect is still under the inset (safe $safe)',
        );
      }
    }
    if (state.mounted) {
      pos.jumpTo(original);
      await tester.pump();
    }
  }

  expect(problems, isEmpty, reason: 'Inset violations:\n${problems.toSet().join('\n')}');
}

final _captured = <FlutterErrorDetails>[];

/// The summary plus the source location of the widget that caused it, so a
/// matrix failure names the file and line to fix without the full tree dump.
String _describeError(Object e) {
  if (e is! FlutterError) return e.toString();
  final details = _captured.where((d) => identical(d.exception, e)).firstOrNull;
  final lines = (details?.toString() ?? e.toStringDeep()).split('\n');
  final where = lines.where((l) => l.contains('file:///') && !l.contains('/test/')).take(2);
  return [e.message.split('\n').first, ...where.map((l) => '  at ${l.trim()}')].join('\n');
}

/// Runs [body] once per matrix case x text scale, as separate named tests.
void screenMatrix(
  String screen,
  Future<void> Function(WidgetTester tester, ScreenCase c, double textScale) body, {
  List<ScreenCase>? cases,
  List<double> textScales = kTextScales,
  bool checkInsets = true,
}) {
  for (final c in cases ?? kScreenMatrix) {
    for (final s in textScales) {
      testWidgets('$screen @ ${c.name} x$s', (tester) async {
        // Reset inside the body: the binding checks foundation debug variables
        // before tearDowns run, so pumpAtSize's addTearDown is too late.
        // Record full error details (the error-causing widget's location lives
        // in the details, not the exception that takeException hands back).
        final original = FlutterError.onError;
        FlutterError.onError = (details) {
          _captured.add(details);
          original?.call(details);
        };
        _insetCheckActive = checkInsets;
        try {
          await body(tester, c, s);
        } finally {
          _insetCheckActive = false;
          FlutterError.onError = original;
          _captured.clear();
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }
}
