import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/player/media_file_types.dart';

void main() {
  group('looksLikeNonMedia (deny-list)', () {
    test('lets every container through, any case, odd ones included', () {
      for (final n in [
        'a.mp4',
        'a.MKV',
        'x.y.mov',
        'a.webm',
        'dnxhd_pcm.mxf',
        'a.rmvb',
        'a.wtv',
        'a.vob',
        'clip.m2ts',
        'a.TS',
      ]) {
        expect(looksLikeNonMedia(n), isFalse, reason: n);
        expect(looksLikeVideoFile(n), isTrue, reason: n);
      }
    });

    test('refuses documents, images, archives, programs and subtitle files', () {
      for (final n in [
        'Elevation.pdf',
        'a.JPG',
        'a.heic',
        'notes.txt',
        'a.mp4.zip',
        'deck.pptx',
        'app.apk',
        'setup.exe',
        'a.srt',
        'a.ass',
        'IMG_1.png',
        '/path/to/report.docx',
      ]) {
        expect(looksLikeNonMedia(n), isTrue, reason: n);
      }
    });

    test('audio files stay allowed - mpv plays them', () {
      for (final n in ['a.mp3', 'a.flac', 'a.m4a', 'a.mka']) {
        expect(looksLikeNonMedia(n), isFalse, reason: n);
      }
    });

    test('a name with no usable extension is left for the player to try', () {
      for (final n in ['movie', '.hidden', 'trailing.', 'video:1234', '']) {
        expect(looksLikeNonMedia(n), isFalse, reason: n);
      }
    });

    test('only the last extension counts', () {
      expect(looksLikeNonMedia('movie.final.mkv'), isFalse);
      expect(looksLikeNonMedia('dir.pdf/movie.mkv'), isFalse);
      expect(looksLikeNonMedia(r'C:\x\movie.avi'), isFalse);
    });
  });

  test('fileExtensionOf / hasKnownVideoExtension', () {
    expect(fileExtensionOf('A.B.MKV'), 'mkv');
    expect(fileExtensionOf('noext'), isNull);
    expect(hasKnownVideoExtension('a.mxf'), isTrue);
    expect(hasKnownVideoExtension('a.unknownfmt'), isFalse);
  });

  group('lists', () {
    test('video and non-media extensions never overlap', () {
      expect(kVideoExtensions.toSet().intersection(kNonMediaExtensions), isEmpty);
    });

    test('every extension is lower case and unique', () {
      expect(kVideoExtensions.toSet().length, kVideoExtensions.length);
      expect(kVideoExtensions.every((e) => e == e.toLowerCase() && !e.contains('.')), isTrue);
      expect(kNonMediaExtensions.every((e) => e == e.toLowerCase()), isTrue);
    });

    test('the plan\'s extension list is complete', () {
      expect(
        kVideoExtensions,
        containsAll([
          ...'mp4 m4v mov mkv mka webm avi wmv asf flv f4v ts m2ts mts m2v mpg mpeg mpe vob dat '
                  '3gp 3g2 ogv ogm divx xvid rm rmvb mxf nut y4m dv wtv evo mod trp tp'
              .split(' '),
        ]),
      );
    });

    test('the picker group carries a field for every platform', () {
      expect(kVideoTypeGroup.extensions, kVideoExtensions);
      expect(kVideoTypeGroup.mimeTypes, kVideoMimeTypes);
      expect(kVideoTypeGroup.uniformTypeIdentifiers, kVideoUtis);
      expect(kVideoTypeGroup.extensions!.every(looksLikeVideoFile), isTrue);
    });

    test('android types include the labels providers really use', () {
      expect(
        kVideoMimeTypes,
        containsAll([
          'video/*',
          'application/x-matroska',
          'application/mxf',
          'application/vnd.rn-realmedia',
          'application/octet-stream',
        ]),
      );
    });

    test('Windows gets Videos plus All files; the all-files group filters nothing', () {
      expect(kVideoPickerGroups, [kVideoTypeGroup, kAllFilesTypeGroup]);
      expect(kAllFilesTypeGroup.allowsAny, isTrue);
    });
  });

  group('iOS UTIs stay in step with Info.plist', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final imported = plist.substring(plist.indexOf('<key>UTImportedTypeDeclarations</key>'));
    final declaredIds = RegExp(r'<key>UTTypeIdentifier</key>\s*<string>([^<]+)</string>')
        .allMatches(imported)
        .map((m) => m.group(1)!)
        .toSet();

    test('every identifier we ask for that is not a system type is declared', () {
      final custom = kVideoUtis.where(
        (u) => u.startsWith('app.synctogether.') || u.startsWith('org.matroska.'),
      );
      expect(declaredIds, containsAll(custom));
    });

    test('every declared type is offered to the picker', () {
      expect(kVideoUtis, containsAll(declaredIds));
    });

    test('extensions with no system UTI are covered by a declaration', () {
      final declaredExts =
          RegExp(r'<key>public.filename-extension</key>\s*<array>((?:\s*<string>[^<]+</string>)+)')
              .allMatches(imported)
              .expand((m) => RegExp(r'<string>([^<]+)</string>').allMatches(m.group(1)!))
              .map((m) => m.group(1)!)
              .toSet();
      expect(
        declaredExts,
        containsAll(
          'mkv mka webm vob divx xvid rm rmvb mxf ogm nut wtv evo y4m mod trp tp dat'.split(' '),
        ),
      );
      expect(kVideoExtensions, containsAll(declaredExts));
    });
  });
}
