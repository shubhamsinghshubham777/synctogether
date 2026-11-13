import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A text field with no placeholder is easy to miss in this design system, so
/// every `TextField(` in lib/ must carry a `hintText`. (`PTTextField.hint` is
/// a required parameter, so the compiler covers that one.)
void main() {
  test('every TextField declares a hintText', () {
    final offenders = <String>[];
    // Matches `TextField(` but not `PTTextField(` / `CupertinoTextField(`.
    final start = RegExp(r'(?<![A-Za-z])TextField\(');
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      final path = f.path.replaceAll(r'\', '/');
      if (!path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      for (final m in start.allMatches(src)) {
        var depth = 0;
        var end = m.end - 1;
        for (; end < src.length; end++) {
          if (src[end] == '(') depth++;
          if (src[end] == ')' && --depth == 0) break;
        }
        final body = src.substring(m.start, end);
        // The code input's real field is invisible; its boxes carry the placeholder.
        if (path.endsWith('ui/inputs.dart') && body.contains('PTCodeInput.length')) continue;
        if (!body.contains('hintText') && !body.contains('_fieldDecoration(')) {
          offenders.add('$path:${src.substring(0, m.start).split('\n').length}');
        }
      }
    }
    expect(offenders, isEmpty, reason: 'Add a hintText to:\n${offenders.join('\n')}');
  });
}
