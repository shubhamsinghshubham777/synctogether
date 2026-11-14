import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/ui/booth_icons.g.dart';

/// An icon's line box must be exactly its size. Flutter rounds a font's ascent and its
/// descent up to whole pixels; the generated font once declared an ascent of exactly one
/// em (float noise tipped it to the next pixel) and a bounding box that started above
/// the baseline (read as a descent), so a 14px icon came out in a 15px box and every
/// icon rode about a pixel high next to its label. `tool/generate_booth_icons.py` keeps
/// the ascent one unit under the em and the bounding-box bottom on the baseline.
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

  for (final size in [12.0, 14.0, 16.0, 18.0, 19.0, 20.0, 22.0, 24.0, 28.0, 48.0]) {
    test('a $size px icon has a $size px line box, with nothing below the baseline', () {
      final painter = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(BoothIcons.clock.codePoint),
          style: TextStyle(fontFamily: 'BoothIcons', fontSize: size),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final line = painter.computeLineMetrics().single;
      expect(painter.height, size, reason: 'a taller box centres the glyph too high');
      expect(line.descent, 0, reason: 'the font declares no descent');
      painter.dispose();
    });
  }
}
