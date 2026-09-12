import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/ui/responsive.dart';

void main() {
  group('Desktop Window & Responsive Constraints', () {
    test('kDesktopMinWindowSize satisfies desktop breakpoint requirements', () {
      expect(kDesktopMinWindowSize.width, greaterThanOrEqualTo(840.0));
      expect(kDesktopMinWindowSize.width, 900.0);
      expect(kDesktopMinWindowSize.height, 600.0);
    });

    test('desktop breakpoint activates at or above 840px', () {
      const size = kDesktopMinWindowSize;
      expect(size.width >= 840, isTrue);
    });
  });
}
