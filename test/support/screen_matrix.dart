import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/foundation.dart';
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

const _notchPortrait = EdgeInsets.only(top: 47, bottom: 34);
const _notchLandscape = EdgeInsets.only(left: 47, right: 47, bottom: 21);

final kScreenMatrix = <ScreenCase>[
  const ScreenCase('phone-small', Size(320, 568), .iOS),
  const ScreenCase('phone-android', Size(360, 800), .android, padding: EdgeInsets.only(top: 24)),
  const ScreenCase('phone', Size(390, 844), .iOS, padding: _notchPortrait),
  const ScreenCase('phone-land', Size(844, 390), .iOS, padding: _notchLandscape),
  const ScreenCase('phone-se-land', Size(667, 375), .iOS),
  const ScreenCase('phone-keyboard', Size(390, 844), .iOS, padding: _notchPortrait, keyboard: 336),
  const ScreenCase('phone-land-keyboard', Size(844, 390), .android, keyboard: 200),
  const ScreenCase(
    'ipad-mini',
    Size(744, 1133),
    .iOS,
    padding: EdgeInsets.only(top: 24, bottom: 20),
  ),
  const ScreenCase('ipad', Size(820, 1180), .iOS, padding: EdgeInsets.only(top: 24, bottom: 20)),
  const ScreenCase(
    'ipad-land',
    Size(1180, 820),
    .iOS,
    padding: EdgeInsets.only(top: 24, bottom: 20),
  ),
  const ScreenCase(
    'ipad-pro-13',
    Size(1032, 1376),
    .iOS,
    padding: EdgeInsets.only(top: 24, bottom: 20),
  ),
  const ScreenCase('ipad-split-third', Size(320, 1024), .iOS),
  const ScreenCase('fold-unfolded', Size(882, 1104), .android),
  const ScreenCase(
    'fold-book',
    Size(1080, 960),
    .android,
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
    features: [
      DisplayFeature(
        bounds: Rect.fromLTWH(0, 552, 882, 0),
        type: DisplayFeatureType.fold,
        state: DisplayFeatureState.postureHalfOpened,
      ),
    ],
  ),
  const ScreenCase('fold-cover', Size(344, 882), .android),
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
    ..padding = FakeViewPadding(
      left: c.padding.left,
      top: c.padding.top,
      right: c.padding.right,
      bottom: c.padding.bottom,
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
void expectNoOverflow(WidgetTester tester) {
  final errors = <Object>[];
  Object? e;
  while ((e = tester.takeException()) != null) {
    errors.add(e!);
  }
  expect(errors, isEmpty, reason: errors.join('\n---\n'));
}

/// Runs [body] once per matrix case x text scale, as separate named tests.
void screenMatrix(
  String screen,
  Future<void> Function(WidgetTester tester, ScreenCase c, double textScale) body, {
  List<ScreenCase>? cases,
  List<double> textScales = kTextScales,
}) {
  for (final c in cases ?? kScreenMatrix) {
    for (final s in textScales) {
      testWidgets('$screen @ ${c.name} x$s', (tester) => body(tester, c, s));
    }
  }
}
