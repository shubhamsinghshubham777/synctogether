import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Colours come from `PTColors` (lib/ui/pt_theme.dart), never from literals
/// scattered through screens - a literal is how the palette drifts.
void main() {
  test('no Color(0x…) or Material swatch literals outside pt_theme.dart', () {
    final literal = RegExp(
      r'Color\(0x[0-9A-Fa-f]{6,8}\)|\bColors\.(?!white\b|black\b|transparent\b)[a-z]+',
    );
    // Brand marks whose colours are fixed by their owner's guidelines.
    const brandConsts = {'_googleRed', '_googleBlue', '_googleYellow', '_googleGreen'};
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.endsWith('ui/pt_theme.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (!literal.hasMatch(line)) continue;
        if (brandConsts.any((c) => line.contains('const $c ='))) continue;
        offenders.add('${f.path}:${i + 1}: ${line.trim()}');
      }
    }
    expect(offenders, isEmpty, reason: 'Add a PTColors token instead:\n${offenders.join('\n')}');
  });
}
