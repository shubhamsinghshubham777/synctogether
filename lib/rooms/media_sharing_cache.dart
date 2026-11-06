import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:storage_space/storage_space.dart';

class CacheProgress {
  const CacheProgress({
    required this.bytesReceived,
    required this.totalBytes,
    required this.speedBps,
    required this.etaSeconds,
  });

  final int bytesReceived;
  final int totalBytes;
  final double speedBps;
  final int etaSeconds;

  double get fraction => totalBytes > 0 ? (bytesReceived / totalBytes).clamp(0.0, 1.0) : 0.0;
}

class MediaSharingCache {
  MediaSharingCache({Directory? cacheDirectory}) : _cacheDir = cacheDirectory;

  Directory? _cacheDir;

  Future<Directory> get cacheDirectory async {
    if (_cacheDir != null) {
      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
      }
      return _cacheDir!;
    }
    final appDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(appDir.path, 'media_cache'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cacheDir = dir;
    return dir;
  }

  String getCacheFilePath(String r2Key) {
    final hash = sha256.convert(utf8.encode(r2Key)).toString();
    final ext = p.extension(r2Key).toLowerCase();
    final safeExt = ext.isNotEmpty ? ext : '.mp4';
    final dirPath = _cacheDir?.path ?? '';
    return dirPath.isNotEmpty ? p.join(dirPath, '$hash$safeExt') : '$hash$safeExt';
  }

  Future<String> getResolvedCacheFilePath(String r2Key) async {
    final dir = await cacheDirectory;
    final hash = sha256.convert(utf8.encode(r2Key)).toString();
    final ext = p.extension(r2Key).toLowerCase();
    final safeExt = ext.isNotEmpty ? ext : '.mp4';
    return p.join(dir.path, '$hash$safeExt');
  }

  Future<bool> isCached(String r2Key) async {
    final path = _cacheDir != null
        ? getCacheFilePath(r2Key)
        : await getResolvedCacheFilePath(r2Key);
    final file = File(path);
    return file.exists();
  }

  Future<void> evict(String r2Key) async {
    final path = _cacheDir != null
        ? getCacheFilePath(r2Key)
        : await getResolvedCacheFilePath(r2Key);
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<bool> hasEnoughSpace(int requiredBytes) async {
    try {
      final space = await getStorageSpace(
        lowOnSpaceThreshold: 100 * 1024 * 1024,
        fractionDigits: 1,
      );
      return space.free >= requiredBytes + (200 * 1024 * 1024); // 200 MB buffer
    } catch (_) {
      return true; // Fallback if platform check is unavailable
    }
  }

  Future<File> downloadFile({
    required String r2Key,
    required Uri downloadUrl,
    required int totalBytes,
    void Function(CacheProgress progress)? onProgress,
    HttpClient? httpClient,
  }) async {
    final finalPath = await getResolvedCacheFilePath(r2Key);
    final finalFile = File(finalPath);
    if (await finalFile.exists()) {
      onProgress?.call(
        CacheProgress(
          bytesReceived: totalBytes,
          totalBytes: totalBytes,
          speedBps: 0,
          etaSeconds: 0,
        ),
      );
      return finalFile;
    }

    final tempPath = '$finalPath.tmp';
    final tempFile = File(tempPath);

    int existingBytes = 0;
    if (await tempFile.exists()) {
      existingBytes = await tempFile.length();
      if (existingBytes >= totalBytes) {
        await tempFile.rename(finalPath);
        return finalFile;
      }
    }

    final client = httpClient ?? HttpClient();
    final request = await client.getUrl(downloadUrl);
    if (existingBytes > 0) {
      request.headers.add(HttpHeaders.rangeHeader, 'bytes=$existingBytes-');
    }

    final response = await request.close();
    if (response.statusCode != HttpStatus.ok && response.statusCode != HttpStatus.partialContent) {
      throw HttpException('Failed to download media: HTTP ${response.statusCode}');
    }

    final sink = tempFile.openWrite(mode: existingBytes > 0 ? FileMode.append : FileMode.write);
    int receivedBytes = existingBytes;

    final stopwatch = Stopwatch()..start();
    int lastSampleBytes = receivedBytes;
    int lastSampleMs = 0;
    double currentSpeedBps = 0;

    await for (final chunk in response) {
      sink.add(chunk);
      receivedBytes += chunk.length;

      final elapsedMs = stopwatch.elapsedMilliseconds;
      if (elapsedMs - lastSampleMs >= 500) {
        final deltaBytes = receivedBytes - lastSampleBytes;
        final deltaTime = (elapsedMs - lastSampleMs) / 1000.0;
        currentSpeedBps = deltaTime > 0 ? (deltaBytes / deltaTime) : 0;
        lastSampleBytes = receivedBytes;
        lastSampleMs = elapsedMs;

        final remainingBytes = totalBytes - receivedBytes;
        final etaSeconds = currentSpeedBps > 0 ? (remainingBytes / currentSpeedBps).ceil() : 0;

        onProgress?.call(
          CacheProgress(
            bytesReceived: receivedBytes,
            totalBytes: totalBytes,
            speedBps: currentSpeedBps,
            etaSeconds: etaSeconds,
          ),
        );
      }
    }

    await sink.flush();
    await sink.close();

    if (httpClient == null) {
      client.close();
    }

    await tempFile.rename(finalPath);
    onProgress?.call(
      CacheProgress(
        bytesReceived: totalBytes,
        totalBytes: totalBytes,
        speedBps: currentSpeedBps,
        etaSeconds: 0,
      ),
    );

    return finalFile;
  }

  Future<void> cleanOrphanedTempFiles() async {
    final dir = await cacheDirectory;
    if (!await dir.exists()) return;

    final entries = dir.listSync();
    for (final entity in entries) {
      if (entity is File && entity.path.endsWith('.tmp')) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> pruneOldEntries({Duration maxAge = const Duration(days: 7)}) async {
    final dir = await cacheDirectory;
    if (!await dir.exists()) return;

    final cutoff = DateTime.now().subtract(maxAge);
    final entries = dir.listSync();
    for (final entity in entries) {
      if (entity is File && !entity.path.endsWith('.tmp')) {
        try {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoff)) {
            await entity.delete();
          }
        } catch (_) {}
      }
    }
  }

  static const _mapMagic = 0x53544d31; // "STM1"

  static Uint8List _encodeMap(int totalBytes, int chunkSize, Uint8List present) {
    final out = BytesBuilder();
    final header = ByteData(16)
      ..setUint32(0, _mapMagic)
      ..setUint32(4, chunkSize)
      ..setUint64(8, totalBytes);
    out
      ..add(header.buffer.asUint8List())
      ..add(present);
    return out.takeBytes();
  }

  static Uint8List? _decodeMap(Uint8List bytes, int totalBytes, int chunkSize) {
    if (bytes.length < 16) return null;
    final header = ByteData.sublistView(bytes, 0, 16);
    if (header.getUint32(0) != _mapMagic ||
        header.getUint32(4) != chunkSize ||
        header.getUint64(8) != totalBytes) {
      return null;
    }
    final chunks = (totalBytes + chunkSize - 1) ~/ chunkSize;
    if (bytes.length != 16 + chunks) return null;
    return Uint8List.fromList(bytes.sublist(16));
  }

  /// Wipes all cached media and temporary files from the local disk cache
  /// upon account deletion.
  Future<void> clearAll() async {
    final dir = await cacheDirectory;
    if (!await dir.exists()) return;

    final entries = dir.listSync();
    for (final entity in entries) {
      try {
        if (entity is File) {
          await entity.delete();
        } else if (entity is Directory) {
          await entity.delete(recursive: true);
        }
      } catch (_) {}
    }
  }
}

/// Default ceiling for the playback cache, across every film it holds.
const int kStreamCacheCapBytes = 3 * 1024 * 1024 * 1024;

/// One shared film, held on disk as it is streamed: a pre-sized data file plus
/// a one-byte-per-chunk presence map. Chunks are only ever marked present once
/// whole, so a crash or a cancelled fetch leaves a file that is merely
/// incomplete, never wrong.
///
/// The map is conservative by construction: data is written before its chunk
/// is marked, and the map is persisted after, so a stale map can only forget
/// bytes it has - never claim bytes it lacks.
class SparseMediaEntry {
  SparseMediaEntry._(
    this.totalBytes,
    this.chunkSize,
    this._present,
    this._dataFile,
    this._mapFile,
    this._writer,
    this._reader,
  );

  final int totalBytes;
  final int chunkSize;
  final Uint8List _present;
  final File _dataFile;
  final File _mapFile;
  final RandomAccessFile _writer;
  final RandomAccessFile _reader;
  Future<void> _writeLock = Future.value();
  Future<void> _readLock = Future.value();
  bool _dirty = false;
  bool _closed = false;

  int get chunkCount => _present.length;

  /// Bytes in chunk [index] (the last one is short).
  int chunkLength(int index) =>
      index == chunkCount - 1 ? totalBytes - index * chunkSize : chunkSize;

  bool hasChunk(int index) => index >= 0 && index < chunkCount && _present[index] == 1;

  int get cachedBytes {
    var n = 0;
    for (var i = 0; i < chunkCount; i++) {
      if (_present[i] == 1) n += chunkLength(i);
    }
    return n;
  }

  /// Contiguous whole-chunk bytes available from [offset] onwards.
  int contiguousFrom(int offset) {
    if (offset < 0 || offset >= totalBytes) return 0;
    var i = offset ~/ chunkSize;
    if (!hasChunk(i)) return 0;
    var end = (i + 1) * chunkSize;
    while (i + 1 < chunkCount && hasChunk(i + 1)) {
      i++;
      end += chunkSize;
    }
    return (end > totalBytes ? totalBytes : end) - offset;
  }

  /// Runs [op] on the write handle once every earlier write-side operation has
  /// finished. A RandomAccessFile allows exactly one async operation at a time
  /// (a second throws "An async operation is currently pending"), and seek+write
  /// is two of them, so *everything* that touches the handle goes through here.
  Future<T> _onWriter<T>(Future<T> Function() op) {
    final run = _writeLock.then((_) => op());
    _writeLock = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  /// Writes [data] at [offset].
  Future<void> write(int offset, Uint8List data) => _onWriter(() async {
    if (_closed) return;
    await _writer.setPosition(offset);
    await _writer.writeFrom(data);
  });

  Future<Uint8List> read(int offset, int length) {
    final run = _readLock.then((_) async {
      if (_closed) return Uint8List(0);
      await _reader.setPosition(offset);
      return _reader.read(length);
    });
    _readLock = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  /// Marks chunk [index] whole. Call only after every byte of it was written.
  Future<void> markChunk(int index) async {
    if (index < 0 || index >= chunkCount || _present[index] == 1) return;
    await _writeLock; // the chunk's last write has landed
    _present[index] = 1;
    _dirty = true;
  }

  /// Persists the presence map if it changed.
  Future<void> persist() async {
    if (!_dirty || _closed) return;
    _dirty = false;
    try {
      await _onWriter(() => _writer.flush());
      await _mapFile.writeAsBytes(MediaSharingCache._encodeMap(totalBytes, chunkSize, _present));
    } catch (_) {
      _dirty = true;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    await persist();
    _closed = true;
    try {
      await _onWriter(() => _writer.close());
      await _readLock;
      await _reader.close();
    } catch (_) {}
  }

  String get dataPath => _dataFile.path;
}

extension StreamingCache on MediaSharingCache {
  /// Opens (creating if needed) the sparse entry for [key]. A key is anything
  /// stable across re-signed URLs plus the object size, so a replaced file of a
  /// different size can never be served from an old entry.
  Future<SparseMediaEntry> openSparse({
    required String key,
    required int totalBytes,
    int chunkSize = 4 * 1024 * 1024,
  }) async {
    final dir = await cacheDirectory;
    final hash = sha256.convert(utf8.encode('$key|$totalBytes')).toString();
    final dataFile = File(p.join(dir.path, '$hash.part'));
    final mapFile = File(p.join(dir.path, '$hash.map'));
    final chunks = (totalBytes + chunkSize - 1) ~/ chunkSize;
    var present = Uint8List(chunks);
    var reuse = false;
    if (await dataFile.exists() && await mapFile.exists()) {
      final loaded = MediaSharingCache._decodeMap(
        await mapFile.readAsBytes(),
        totalBytes,
        chunkSize,
      );
      if (loaded != null && await dataFile.length() == totalBytes) {
        present = loaded;
        reuse = true;
      }
    }
    if (!reuse) {
      if (await dataFile.exists()) await dataFile.delete();
      if (await mapFile.exists()) await mapFile.delete();
      await dataFile.create(recursive: true);
      final init = await dataFile.open(mode: FileMode.append);
      try {
        await init.truncate(totalBytes);
      } finally {
        await init.close();
      }
    }
    final writer = await dataFile.open(mode: FileMode.append);
    final reader = await dataFile.open();
    // Touch: the LRU order is by last open.
    try {
      await dataFile.setLastModified(DateTime.now());
    } catch (_) {}
    return SparseMediaEntry._(totalBytes, chunkSize, present, dataFile, mapFile, writer, reader);
  }

  /// Evicts least-recently-used streamed films until the cache fits in
  /// [maxBytes]. [keepPath] (the film being watched) is never evicted.
  Future<int> enforceCap({int maxBytes = kStreamCacheCapBytes, String? keepPath}) async {
    final dir = await cacheDirectory;
    final parts = <File>[];
    var total = 0;
    for (final e in dir.listSync()) {
      if (e is File && e.path.endsWith('.part')) {
        parts.add(e);
        total += e.lengthSync();
      }
    }
    if (total <= maxBytes) return 0;
    parts.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
    var freed = 0;
    for (final f in parts) {
      if (total - freed <= maxBytes) break;
      if (f.path == keepPath) continue;
      final size = f.lengthSync();
      try {
        f.deleteSync();
        final map = File('${f.path.substring(0, f.path.length - 5)}.map');
        if (map.existsSync()) map.deleteSync();
        freed += size;
      } catch (_) {}
    }
    return freed;
  }
}
