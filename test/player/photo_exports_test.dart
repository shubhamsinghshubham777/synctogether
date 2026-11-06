import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/player/local_video.dart';
import 'package:synctogether/player/photo_exports.dart';

final _now = DateTime.utc(2026, 11, 6, 12);
const _gb = 1024 * 1024 * 1024;

PhotoExport _e(String id, {int bytes = 1, Duration idle = Duration.zero}) => PhotoExport(
  dir: '/app/PhotosPicks/$id',
  filePath: '/app/PhotosPicks/$id/$id.mov',
  bytes: bytes,
  lastUsed: _now.subtract(idle),
);

List<String> _evicted(
  List<PhotoExport> exports, {
  Set<String> referenced = const {},
  String? playing,
  int maxBytes = kPhotoExportMaxBytes,
}) => [
  for (final e in photoExportsToEvict(
    exports: exports,
    now: _now,
    referenced: referenced,
    playing: playing,
    maxBytes: maxBytes,
  ))
    e.dir.split('/').last,
];

void main() {
  group('photoExportsToEvict', () {
    test('keeps a referenced export used within the age cap', () {
      final a = _e('a', idle: const Duration(days: 3));
      expect(_evicted([a], referenced: {a.filePath}), isEmpty);
    });

    test('the age cap beats being referenced', () {
      final a = _e('a', idle: const Duration(days: 8));
      expect(_evicted([a], referenced: {a.filePath}), ['a']);
    });

    test('an unreferenced export gets a day of grace, then goes', () {
      expect(_evicted([_e('fresh', idle: const Duration(hours: 5))]), isEmpty);
      expect(_evicted([_e('old', idle: const Duration(days: 2))]), ['old']);
    });

    test('a referenced path matches across a moved app container', () {
      final a = _e('a', idle: const Duration(days: 3));
      expect(_evicted([a], referenced: {'/other-container/PhotosPicks/a/a.mov'}), isEmpty);
    });

    test('never evicts the playing file, even over every cap', () {
      final a = _e('a', bytes: 9 * _gb, idle: const Duration(days: 30));
      expect(_evicted([a], playing: a.filePath), isEmpty);
    });

    test('the size cap evicts oldest-last-used first until it fits', () {
      final x = [
        _e('newest', bytes: 2 * _gb, idle: const Duration(hours: 1)),
        _e('oldest', bytes: 2 * _gb, idle: const Duration(hours: 5)),
        _e('middle', bytes: 2 * _gb, idle: const Duration(hours: 3)),
      ];
      expect(_evicted(x, referenced: {for (final e in x) e.filePath}), ['oldest']);
    });

    test('the size cap skips the playing file and takes the next oldest', () {
      final x = [
        _e('playing', bytes: 3 * _gb, idle: const Duration(hours: 9)),
        _e('other', bytes: 3 * _gb, idle: const Duration(hours: 2)),
      ];
      expect(_evicted(x, referenced: {for (final e in x) e.filePath}, playing: x[0].filePath), [
        'other',
      ]);
    });

    test('a touch (newer last-used) moves an export out of the size cap line', () {
      final a = _e('a', bytes: 3 * _gb, idle: const Duration(hours: 9));
      final b = _e('b', bytes: 3 * _gb, idle: const Duration(hours: 5));
      final bumped = PhotoExport(dir: a.dir, filePath: a.filePath, bytes: a.bytes, lastUsed: _now);
      final refs = {a.filePath, b.filePath};
      expect(_evicted([a, b], referenced: refs), ['a']);
      expect(_evicted([bumped, b], referenced: refs), ['b']);
    });
  });

  group('paths', () {
    test('isPhotosExportPath', () {
      expect(
        isPhotosExportPath('/var/mobile/Library/Application Support/PhotosPicks/u/a.mov'),
        isTrue,
      );
      expect(isPhotosExportPath('/Users/me/Movies/a.mov'), isFalse);
    });

    test('exports are not temporary, and never durable for Recent', () {
      const p =
          '/var/mobile/Containers/Data/Application/X/Library/Application Support/PhotosPicks/u/a.mov';
      expect(isTemporaryPath(p), isFalse);
      expect(
        LocalVideo(
          name: 'a.mov',
          mediaUri: p,
          path: p,
          origin: VideoOrigin.files,
          reference: PathReference(p),
        ).durable,
        isFalse,
      );
    });
  });

  group('PhotoExports on disk', () {
    late Directory parent;
    late Directory root;
    setUp(() {
      parent = Directory.systemTemp.createTempSync('photo_exports');
      root = Directory('${parent.path}/PhotosPicks')..createSync();
    });
    tearDown(() => parent.deleteSync(recursive: true));

    File make(String id, {int bytes = 10, Duration idle = Duration.zero}) {
      final dir = Directory('${root.path}/$id')..createSync();
      final f = File('${dir.path}/$id.mov')..writeAsBytesSync(List.filled(bytes, 1));
      f.setLastModifiedSync(DateTime.now().subtract(idle));
      return f;
    }

    PhotoExports svc() => PhotoExports(directory: () async => root.path);

    test('sweep removes the aged one, keeps the referenced fresh one', () async {
      final keep = make('keep', bytes: 7);
      make('old', idle: const Duration(days: 9));
      expect(await svc().sweep(referenced: {keep.path}), 1);
      expect(Directory('${root.path}/old').existsSync(), isFalse);
      expect(keep.existsSync(), isTrue);
      expect(await svc().totalBytes(), 7);
    });

    test('touch bumps last-used; clear spares the playing file', () async {
      final f = make('a', idle: const Duration(days: 6));
      final g = make('b');
      final before = f.lastModifiedSync();
      await svc().touch(f.path);
      expect(f.lastModifiedSync().isAfter(before), isTrue);
      await svc().clear(playing: g.path);
      expect(f.existsSync(), isFalse);
      expect(g.existsSync(), isTrue);
    });
  });
}
