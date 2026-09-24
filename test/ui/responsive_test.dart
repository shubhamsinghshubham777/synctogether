import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/ui/responsive.dart';

void main() {
  test('kDesktopMinWindowSize sits inside the desktop class', () {
    expect(kDesktopMinWindowSize, const Size(900, 600));
    expect(classifyLayout(kDesktopMinWindowSize, .pointer), PTLayout.desktop);
  });

  group('classifyLayout', () {
    const cases = <(String, Size, PTInput, PTLayout)>[
      ('macOS desktop', Size(1440, 900), .pointer, .desktop),
      ('narrow pointer window', Size(700, 900), .pointer, .portrait),
      ('iPhone portrait', Size(390, 844), .touch, .portrait),
      ('iPhone landscape', Size(844, 390), .touch, .landscape),
      ('iPhone SE landscape', Size(667, 375), .touch, .landscape),
      ('iPad mini portrait', Size(744, 1133), .touch, .tablet),
      ('iPad Air portrait', Size(820, 1180), .touch, .tablet),
      ('iPad landscape', Size(1180, 820), .touch, .tablet),
      ('iPad 1/3 split view', Size(320, 1024), .touch, .portrait),
      ('Fold unfolded', Size(882, 1104), .touch, .tablet),
      ('Fold cover screen', Size(344, 882), .touch, .portrait),
    ];
    for (final (name, size, input, expected) in cases) {
      test(name, () => expect(classifyLayout(size, input), expected));
    }
  });
}
