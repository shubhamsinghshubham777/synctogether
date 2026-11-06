import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:synctogether/diagnostics.dart';

// Retention for the copies "From Photos" leaves on the device.
//
// WHY THEY EXIST. The system photo picker hands over a file that vanishes when
// the callback returns (iOS) or a grant that dies with the process (Android),
// so the native side copies the pick once into `PhotosPicks/<uuid>/<name>` under
// app-private storage (iOS Application Support, Android filesDir) - never tmp or
// caches, which the OS wipes between a leave and a rejoin. Because the OS never
// purges those folders, the policy below is ours.
//
// POLICY (all pure, see [photoExportsToEvict]):
//  * playing file: never evicted.
//  * 7 days since last use: gone, whatever references it (the safety net; a
//    room that sits idle longer than a week falls back to the shared copy with
//    a notice rather than keeping gigabytes forever).
//  * not referenced by any remembered room and idle for a day: gone (an orphan
//    from a pick that never reached a room, or a room that was forgotten).
//  * over 4 GB in total: oldest-last-used goes first until it fits.
// "Last use" is the file's modification time: the native side stamps it at
// export and [PhotoExports.touch] bumps it whenever a room opens the file.
//
// Trade-off vs Library/Caches: Caches survives app termination but the OS may
// purge it under storage pressure, which is exactly the surprise this fixes, so
// iOS uses Application Support (flagged excluded-from-backup) and owns cleanup.
//
// Rooms live for 24 h, are resumable for 24 h more, and a premium room can rest
// idle for 90 days, so 7 days covers every normal rejoin; beyond it the pick is
// deliberately let go.

const kPhotoExportMaxAge = Duration(days: 7);
const kPhotoExportOrphanGrace = Duration(days: 1);
const kPhotoExportMaxBytes = 4 * 1024 * 1024 * 1024;

const _kFolder = 'PhotosPicks';

/// Whether [path] is one of our Photos exports. Durable for the room that
/// picked it, but not for the Recent shelf (see recent_videos.dart).
bool isPhotosExportPath(String path) => path.replaceAll('\\', '/').contains('/$_kFolder/');

/// `PhotosPicks/<uuid>/<name>`: how an export is identified independent of the
/// app container's absolute path, which iOS can move on an update.
String photoExportKey(String path) {
  final parts = path.replaceAll('\\', '/').split('/');
  final i = parts.lastIndexOf(_kFolder);
  return i < 0 ? path : parts.sublist(i).join('/');
}

class PhotoExport {
  const PhotoExport({
    required this.dir,
    required this.filePath,
    required this.bytes,
    required this.lastUsed,
  });

  final String dir;
  final String filePath;
  final int bytes;
  final DateTime lastUsed;
}

/// The exports to delete now. [referenced] and [playing] are file paths.
List<PhotoExport> photoExportsToEvict({
  required List<PhotoExport> exports,
  required DateTime now,
  Set<String> referenced = const {},
  String? playing,
  Duration maxAge = kPhotoExportMaxAge,
  Duration orphanGrace = kPhotoExportOrphanGrace,
  int maxBytes = kPhotoExportMaxBytes,
}) {
  final refKeys = {for (final p in referenced) photoExportKey(p)};
  final playKey = playing == null ? null : photoExportKey(playing);
  final evict = <PhotoExport>[];
  final kept = <PhotoExport>[];
  for (final e in exports) {
    final key = photoExportKey(e.filePath);
    if (key == playKey) {
      kept.add(e);
      continue;
    }
    final idle = now.difference(e.lastUsed);
    if (idle > maxAge || (!refKeys.contains(key) && idle > orphanGrace)) {
      evict.add(e);
    } else {
      kept.add(e);
    }
  }
  var total = kept.fold<int>(0, (sum, e) => sum + e.bytes);
  if (total > maxBytes) {
    final oldestFirst = kept.where((e) => photoExportKey(e.filePath) != playKey).toList()
      ..sort((a, b) => a.lastUsed.compareTo(b.lastUsed));
    for (final e in oldestFirst) {
      if (total <= maxBytes) break;
      evict.add(e);
      total -= e.bytes;
    }
  }
  return evict;
}

class PhotoExports {
  PhotoExports({Future<String?> Function()? directory, DateTime Function()? clock})
    : _directory = directory ?? _nativeDirectory,
      _clock = clock ?? DateTime.now;

  static final instance = PhotoExports();

  static const _channel = MethodChannel('app.synctogether/photo_picker');

  final Future<String?> Function() _directory;
  final DateTime Function() _clock;

  static Future<String?> _nativeDirectory() async {
    if (kIsWeb || !(Platform.isIOS || Platform.isAndroid)) return null;
    try {
      return await _channel.invokeMethod<String>('photoExportsDir');
    } on MissingPluginException {
      return null;
    }
  }

  Future<List<PhotoExport>> _scan() async {
    final root = await _directory();
    if (root == null) return const [];
    final base = Directory(root);
    if (!await base.exists()) return const [];
    final out = <PhotoExport>[];
    await for (final unit in base.list(followLinks: false)) {
      if (unit is! Directory) continue;
      var any = false;
      await for (final f in unit.list(followLinks: false)) {
        if (f is! File) continue;
        any = true;
        final stat = await f.stat();
        out.add(
          PhotoExport(dir: unit.path, filePath: f.path, bytes: stat.size, lastUsed: stat.modified),
        );
      }
      if (!any) out.add(PhotoExport(dir: unit.path, filePath: '', bytes: 0, lastUsed: DateTime(0)));
    }
    return out;
  }

  /// Bytes the exports take now (for a future "storage" row).
  Future<int> totalBytes() async {
    try {
      return (await _scan()).fold<int>(0, (sum, e) => sum + e.bytes);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'measuring Photos exports');
      return 0;
    }
  }

  /// Applies the policy. Cheap enough to run at launch and after each pick:
  /// async file IO only, nothing on the UI thread. [referenced] is every path a
  /// room remembers; [playing] is the open file. Returns the number removed.
  Future<int> sweep({Set<String> referenced = const {}, String? playing}) async {
    try {
      final exports = await _scan();
      final doomed = photoExportsToEvict(
        exports: exports,
        now: _clock(),
        referenced: referenced,
        playing: playing,
      );
      var freed = 0;
      for (final e in doomed) {
        freed += e.bytes;
        await Directory(e.dir).delete(recursive: true);
      }
      if (doomed.isNotEmpty) {
        trace(
          'swept Photos exports',
          category: 'media',
          data: {'removed': doomed.length, 'freed_bytes': freed},
        );
      }
      return doomed.length;
    } catch (e, s) {
      reportNonFatal(e, s, during: 'sweeping Photos exports');
      return 0;
    }
  }

  /// Deletes every export except [playing].
  Future<void> clear({String? playing}) async {
    try {
      for (final e in await _scan()) {
        if (playing != null && photoExportKey(e.filePath) == photoExportKey(playing)) continue;
        await Directory(e.dir).delete(recursive: true);
      }
    } catch (e, s) {
      reportNonFatal(e, s, during: 'clearing Photos exports');
    }
  }

  /// A room opened [path]: it counts as used now. No-op for other files.
  Future<void> touch(String path) async {
    if (!isPhotosExportPath(path)) return;
    try {
      await File(path).setLastModified(_clock());
    } catch (_) {
      // Gone or read-only: the open that follows reports it.
    }
  }
}
