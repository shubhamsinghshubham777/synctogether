import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/rooms/media_sharing_cache.dart';

void main() {
  late Directory tmp;
  late MediaSharingCache cache;
  const chunk = 1024;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sparse_test');
    cache = MediaSharingCache(cacheDirectory: tmp);
  });
  tearDown(() => tmp.delete(recursive: true));

  Uint8List bytes(int n, int v) => Uint8List.fromList(List.filled(n, v));

  test('chunks are present only once marked, and the last one is short', () async {
    final e = await cache.openSparse(key: 'k', totalBytes: chunk * 3 + 100, chunkSize: chunk);
    expect(e.chunkCount, 4);
    expect(e.chunkLength(3), 100);
    expect(e.hasChunk(0), isFalse);
    await e.write(0, bytes(chunk, 7));
    expect(e.hasChunk(0), isFalse, reason: 'written is not whole until marked');
    await e.markChunk(0);
    expect(e.hasChunk(0), isTrue);
    expect(await e.read(10, 5), bytes(5, 7));
    expect(e.cachedBytes, chunk);
    await e.close();
  });

  test('contiguousFrom counts whole chunks across a run and stops at a hole', () async {
    final e = await cache.openSparse(key: 'k', totalBytes: chunk * 5, chunkSize: chunk);
    for (final i in [1, 2, 4]) {
      await e.write(i * chunk, bytes(chunk, i));
      await e.markChunk(i);
    }
    expect(e.contiguousFrom(chunk + 10), chunk * 2 - 10);
    expect(e.contiguousFrom(0), 0);
    expect(e.contiguousFrom(4 * chunk), chunk);
    await e.close();
  });

  test('the map survives a reopen; a different size does not reuse it', () async {
    var e = await cache.openSparse(key: 'k', totalBytes: chunk * 4, chunkSize: chunk);
    await e.write(chunk, bytes(chunk, 9));
    await e.markChunk(1);
    await e.close();

    e = await cache.openSparse(key: 'k', totalBytes: chunk * 4, chunkSize: chunk);
    expect(e.hasChunk(1), isTrue);
    expect(await e.read(chunk, 4), bytes(4, 9));
    await e.close();

    e = await cache.openSparse(key: 'k', totalBytes: chunk * 4 + 1, chunkSize: chunk);
    expect(e.cachedBytes, 0);
    await e.close();
  });

  test('a corrupt or truncated map is treated as empty, never trusted', () async {
    var e = await cache.openSparse(key: 'k', totalBytes: chunk * 2, chunkSize: chunk);
    await e.write(0, bytes(chunk, 1));
    await e.markChunk(0);
    await e.close();
    final map = tmp.listSync().whereType<File>().firstWhere((f) => f.path.endsWith('.map'));
    await map.writeAsBytes([1, 2, 3]);
    e = await cache.openSparse(key: 'k', totalBytes: chunk * 2, chunkSize: chunk);
    expect(e.cachedBytes, 0);
    await e.close();
  });

  test('concurrent writes at different offsets do not interleave', () async {
    final e = await cache.openSparse(key: 'k', totalBytes: chunk * 8, chunkSize: chunk);
    await Future.wait([for (var i = 0; i < 8; i++) e.write(i * chunk, bytes(chunk, i + 1))]);
    for (var i = 0; i < 8; i++) {
      expect(await e.read(i * chunk, chunk), bytes(chunk, i + 1));
    }
    await e.close();
  });

  test('enforceCap evicts least recently used films, never the one being watched', () async {
    Future<String> film(String key, int ageMinutes) async {
      final e = await cache.openSparse(key: key, totalBytes: chunk * 4, chunkSize: chunk);
      final path = e.dataPath;
      await e.close();
      await File(path).setLastModified(DateTime.now().subtract(Duration(minutes: ageMinutes)));
      return path;
    }

    final old = await film('old', 300);
    final mid = await film('mid', 200);
    final keep = await film('keep', 400); // oldest, but in use
    final freed = await cache.enforceCap(maxBytes: chunk * 8, keepPath: keep);
    expect(freed, chunk * 4);
    expect(File(old).existsSync(), isFalse);
    expect(File(mid).existsSync(), isTrue);
    expect(File(keep).existsSync(), isTrue);
    expect(File(old.replaceAll('.part', '.map')).existsSync(), isFalse);
  });

  test('clearAll (account deletion) wipes streamed films too', () async {
    final e = await cache.openSparse(key: 'k', totalBytes: chunk * 2, chunkSize: chunk);
    await e.close();
    await cache.clearAll();
    expect(tmp.listSync(), isEmpty);
  });
}
