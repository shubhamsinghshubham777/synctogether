import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/player/media_access.dart';
import 'package:synctogether/rooms/upload_source.dart';

import '../player/fake_media_access.dart';

void main() {
  test('FileUploadSource reads ranges and reports the basename', () async {
    final dir = await Directory.systemTemp.createTemp('pt_src_');
    addTearDown(() => dir.delete(recursive: true));
    final f = File('${dir.path}/clip.mkv')..writeAsBytesSync(List.generate(100, (i) => i));
    final s = FileUploadSource(f);
    expect(s.name, 'clip.mkv');
    expect(s.reference, f.path);
    expect(s.contentType, 'video/x-matroska');
    expect(await s.length(), 100);
    expect([
      for (final c in await s.openRead(10, 20).toList()) ...c,
    ], List.generate(10, (i) => 10 + i));
  });

  group('ContentUriUploadSource', () {
    test('contentType trusts a video/* provider type, else the name, else mp4', () {
      ContentUriUploadSource make(String name, String? mime) => ContentUriUploadSource(
        uri: 'content://x',
        name: name,
        platform: FakeMediaAccess(),
        mimeType: mime,
      );
      expect(make('a.bin', 'video/webm').contentType, 'video/webm');
      expect(make('a.mkv', 'application/octet-stream').contentType, 'video/x-matroska');
      expect(make('noext', null).contentType, 'video/mp4');
    });

    test('length asks the provider when the size is unknown', () async {
      final fake = FakeMediaAccess()..stat = const ContentStat(name: 'a', sizeBytes: 42);
      final s = ContentUriUploadSource(uri: 'content://x', name: 'a.mp4', platform: fake);
      expect(await s.length(), 42);
      fake.stat = null;
      await expectLater(s.length(), throwsA(isA<MediaAccessException>()));
    });

    test('a provider that cannot seek fails loudly with its cause', () async {
      final fake = FakeMediaAccess()
        ..content = Uint8List(10)
        ..seekable = false;
      final s = ContentUriUploadSource(uri: 'content://x', name: 'a.mp4', platform: fake);
      await expectLater(
        s.openRead(0, 10).toList(),
        throwsA(isA<MediaAccessException>().having((e) => e.notSeekable, 'notSeekable', isTrue)),
      );
    });

    test('a file that ends early is an error, not a silent short part', () async {
      final fake = FakeMediaAccess()..content = Uint8List(10);
      final s = ContentUriUploadSource(uri: 'content://x', name: 'a.mp4', platform: fake);
      await expectLater(s.openRead(0, 20).toList(), throwsA(isA<MediaAccessException>()));
    });
  });
}
