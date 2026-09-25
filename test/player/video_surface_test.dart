import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/player/video_surface.dart';

void main() {
  group('renderSurfaceSize', () {
    test('a 720p file on a Retina window renders at the window, not the file', () {
      final s = renderSurfaceSize(const Size(1440, 810), const Size(1280, 720), 2);
      expect(s, (width: 2880, height: 1620));
    });

    test('letterboxes like BoxFit.contain', () {
      // 2.39:1 film in a 16:10 box: width-bound.
      final s = renderSurfaceSize(const Size(1600, 1000), const Size(1920, 804), 1)!;
      expect(s.width, 1600);
      expect(s.height, 670);
    });

    test('caps at 4K with the aspect kept', () {
      final s = renderSurfaceSize(const Size(2560, 1440), const Size(1920, 1080), 2);
      expect(s, (width: 3840, height: 2160));
    });

    test('portrait video caps on its long side too', () {
      final s = renderSurfaceSize(const Size(1500, 3000), const Size(1080, 1920), 2)!;
      expect(s.height, lessThanOrEqualTo(kMaxSurfaceLongSide));
      expect(s.width, lessThanOrEqualTo(kMaxSurfaceShortSide));
    });

    test('rounds to even sizes', () {
      final s = renderSurfaceSize(const Size(333, 333), const Size(1280, 720), 1)!;
      expect(s.width.isEven && s.height.isEven, isTrue);
    });

    test('unknown sizes give nothing to ask for', () {
      expect(renderSurfaceSize(Size.zero, const Size(1280, 720), 2), isNull);
      expect(renderSurfaceSize(const Size(100, 100), Size.zero, 2), isNull);
      expect(renderSurfaceSize(const Size(double.infinity, 100), const Size(16, 9), 1), isNull);
    });
  });
}
