import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/av/camera_facing.dart';

void main() {
  test('facingMode wins over the label', () {
    expect(shouldMirrorCamera(facingMode: 'user', label: 'Back Camera'), isTrue);
    expect(shouldMirrorCamera(facingMode: 'environment', label: 'Front Camera'), isFalse);
  });

  test('falls back to the label when facingMode is missing', () {
    for (final l in ['Back Camera', 'Back Dual Wide Camera', 'Back Ultra Wide Camera']) {
      expect(shouldMirrorCamera(label: l), isFalse, reason: l);
    }
    expect(shouldMirrorCamera(label: 'camera2 0, facing back, Orientation 90'), isFalse);
    expect(shouldMirrorCamera(label: 'Front Camera'), isTrue);
    expect(shouldMirrorCamera(label: 'camera2 1, facing front, Orientation 270'), isTrue);
  });

  test('desktop webcams default to mirrored', () {
    expect(shouldMirrorCamera(label: 'FaceTime HD Camera'), isTrue);
    expect(shouldMirrorCamera(), isTrue);
  });
}
