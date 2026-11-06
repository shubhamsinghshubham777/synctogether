import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/player/video_color_path.dart';

void main() {
  group('isHighBitDepthFormat', () {
    test('recognises mpv names above 8 bits', () {
      for (final f in [
        'p010',
        'yuv420p10',
        'yuv420p10le',
        'yuv422p12',
        'gbrp16',
        'p016',
        'yuv444p10',
      ]) {
        expect(isHighBitDepthFormat(f), isTrue, reason: f);
      }
    });
    test('leaves 8-bit and hardware surfaces alone', () {
      for (final f in ['nv12', 'yuv420p', 'yuvj420p', 'videotoolbox', 'bgra', '', null]) {
        expect(isHighBitDepthFormat(f), isFalse, reason: '$f');
      }
    });
  });

  group('planVideoPath', () {
    test('iPhone HLG camera clip (zero-copy, p010 behind videotoolbox) takes the copy path', () {
      final plan = planVideoPath(
        isIOS: true,
        pixelformat: 'videotoolbox',
        hwPixelformat: 'p010',
        gamma: 'hlg',
        primaries: 'bt.2020',
      );
      expect(plan.hwdec, 'videotoolbox-copy');
      expect(plan.vf, 'format=nv12');
      expect(plan.isStandard, isFalse);
    });

    test('10-bit SDR and PQ both take the copy path', () {
      expect(
        planVideoPath(isIOS: true, pixelformat: 'yuv420p10', gamma: 'bt.1886').hwdec,
        'videotoolbox-copy',
      );
      expect(planVideoPath(isIOS: true, pixelformat: 'nv12', gamma: 'pq').reason, 'hdr-transfer');
    });

    test('8-bit SDR keeps zero-copy', () {
      final plan = planVideoPath(
        isIOS: true,
        pixelformat: 'videotoolbox',
        hwPixelformat: 'nv12',
        gamma: 'bt.1886',
        primaries: 'bt.709',
      );
      expect(plan.isStandard, isTrue);
      expect(plan.hwdec, 'auto');
      expect(plan.vf, isEmpty);
    });

    test('other platforms are never changed', () {
      expect(planVideoPath(isIOS: false, pixelformat: 'p010', gamma: 'hlg').isStandard, isTrue);
    });
  });
}
