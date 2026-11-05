import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/player/media_file_types.dart';

void main() {
  group('looksLikeVideoFile', () {
    test('accepts the containers the player handles, any case', () {
      for (final n in ['a.mp4', 'a.MKV', 'x.y.mov', 'a.webm', 'a.m4v', 'a.avi', 'a.ts']) {
        expect(looksLikeVideoFile(n), isTrue, reason: n);
      }
    });

    test('rejects documents, images and audio', () {
      for (final n in ['Elevation.pdf', 'a.jpg', 'a.mp3', 'notes.txt', 'a.mp4.zip']) {
        expect(looksLikeVideoFile(n), isFalse, reason: n);
      }
    });

    test('lets a name with no usable extension through for the player to try', () {
      for (final n in ['movie', '.hidden', 'trailing.']) {
        expect(looksLikeVideoFile(n), isTrue, reason: n);
      }
    });
  });

  test('the picker group carries a field for every platform', () {
    expect(kVideoTypeGroup.extensions, containsAll(['mp4', 'mkv', 'mov', 'webm']));
    expect(kVideoTypeGroup.mimeTypes, ['video/*']);
    expect(
      kVideoTypeGroup.uniformTypeIdentifiers,
      containsAll(['public.movie', 'org.matroska.mkv', 'org.matroska.webm']),
    );
    expect(kVideoTypeGroup.extensions!.every(looksLikeVideoFile), isTrue);
  });
}
