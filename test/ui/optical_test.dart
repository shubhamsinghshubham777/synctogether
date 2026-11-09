import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/ui/booth_icons.g.dart';
import 'package:synctogether/ui/optical.dart';
import 'package:synctogether/ui/pt_theme.dart';

/// Rendered, not computed: an icon beside text must sit on the text's cap-height centre,
/// at every system text size. Both are rasterised with the bundled fonts at the density
/// of a retina Mac, and the vertical centre of each one's ink is compared. The bound is
/// one logical pixel because at 2x each ink edge only resolves to half a pixel; before
/// the icon font's line box was fixed (see booth_icons_metrics_test.dart) the icons sat
/// a steady pixel and a half too high, which this would have caught.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final manifest = json.decode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final e in manifest.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(e['family'] as String);
      for (final f in (e['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(f['asset'] as String));
      }
      await loader.load();
    }
  });

  const dpr = 2.0;

  /// Top and bottom of the bright pixels inside [r], in logical pixels.
  (double, double) ink(ui.Image img, ByteData data, Rect r) {
    var top = 1 << 30;
    var bottom = -1;
    for (var y = (r.top * dpr).floor(); y < (r.bottom * dpr).ceil(); y++) {
      for (var x = (r.left * dpr).floor(); x < (r.right * dpr).ceil(); x++) {
        if (data.getUint8((y * img.width + x) * 4) > 110 && y < top) top = y;
        if (data.getUint8((y * img.width + x) * 4) > 110 && y > bottom) bottom = y;
      }
    }
    return (top / dpr, (bottom + 1) / dpr);
  }

  /// How far the icon's ink centre sits below the text's, in logical pixels.
  Future<double> drift(
    WidgetTester tester, {
    required TextStyle style,
    required double iconSize,
    required double textScale,
    required bool corrected,
    String text = 'MON 9 NOV 10:00 PM',
  }) async {
    tester.view
      ..physicalSize = const Size(500 * dpr, 120 * dpr)
      ..devicePixelRatio = dpr;
    final boundary = GlobalKey(), iconKey = GlobalKey(), textKey = GlobalKey();
    final white = style.copyWith(color: Colors.white);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: RepaintBoundary(
            key: boundary,
            child: ColoredBox(
              color: Colors.black,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 20,
                  children: [
                    SizedBox(
                      key: iconKey,
                      child: corrected
                          ? PTOpticalIcon(
                              BoothIcons.clock,
                              beside: style,
                              size: iconSize,
                              color: Colors.white,
                            )
                          : Icon(BoothIcons.clock, size: iconSize, color: Colors.white),
                    ),
                    Text(text, key: textKey, style: white),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = (await tester.runAsync(() => render.toImage(pixelRatio: dpr)))!;
    final data = (await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    ))!;
    Rect rect(GlobalKey k) {
      final b = k.currentContext!.findRenderObject()! as RenderBox;
      return b.localToGlobal(Offset.zero) & b.size;
    }

    final i = ink(image, data, rect(iconKey));
    final t = ink(image, data, rect(textKey));
    addTearDown(tester.view.reset);
    return (i.$1 + i.$2) / 2 - (t.$1 + t.$2) / 2;
  }

  for (final scale in [0.85, 1.0, 1.3, 1.5, 2.0, 2.5]) {
    testWidgets('an icon beside mono text stays on its centre at ${scale}x text size', (
      tester,
    ) async {
      final style = PTText.mono.copyWith(fontSize: 15);
      final d = await drift(tester, style: style, iconSize: 18, textScale: scale, corrected: true);
      expect(d.abs(), lessThanOrEqualTo(1.0), reason: 'drifted $d px');
    });

    testWidgets('an icon beside button text stays on its centre at ${scale}x text size', (
      tester,
    ) async {
      final d = await drift(
        tester,
        style: PTText.buttonLabel,
        iconSize: 19,
        textScale: scale,
        corrected: true,
      );
      expect(d.abs(), lessThanOrEqualTo(1.0), reason: 'drifted $d px');
    });
  }
}
