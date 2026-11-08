import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:synctogether/diagnostics.dart';
import 'package:synctogether/player/local_video.dart';
import 'package:synctogether/player/photo_exports.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kStoreKey = 'pt.local_media_by_room';
const _kUploadSessionKey = 'pt.upload_sessions_by_room';
const kLocalMediaTtl = Duration(days: 35);
const _kMaxEntries = 64;

class UploadSession {
  const UploadSession({
    required this.roomId,
    required this.uploadId,
    required this.r2Key,
    required this.filePath,
    required this.fileSize,
    required this.partSizeBytes,
    required this.totalParts,
    this.completedParts = const {},
  });

  final String roomId;
  final String uploadId;
  final String r2Key;
  final String filePath;
  final int fileSize;
  final int partSizeBytes;
  final int totalParts;
  final Map<int, String> completedParts; // partNumber -> etag

  UploadSession copyWith({Map<int, String>? completedParts}) {
    return UploadSession(
      roomId: roomId,
      uploadId: uploadId,
      r2Key: r2Key,
      filePath: filePath,
      fileSize: fileSize,
      partSizeBytes: partSizeBytes,
      totalParts: totalParts,
      completedParts: completedParts ?? this.completedParts,
    );
  }

  factory UploadSession.fromJson(Map<String, dynamic> json) => UploadSession(
    roomId: json['room_id'] as String,
    uploadId: json['upload_id'] as String,
    r2Key: json['r2_key'] as String,
    filePath: json['file_path'] as String,
    fileSize: (json['file_size'] as num).toInt(),
    partSizeBytes: (json['part_size_bytes'] as num).toInt(),
    totalParts: (json['total_parts'] as num).toInt(),
    completedParts:
        (json['completed_parts'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(int.parse(k), v as String),
        ) ??
        const {},
  );

  Map<String, Object?> toJson() => {
    'room_id': roomId,
    'upload_id': uploadId,
    'r2_key': r2Key,
    'file_path': filePath,
    'file_size': fileSize,
    'part_size_bytes': partSizeBytes,
    'total_parts': totalParts,
    'completed_parts': completedParts.map((k, v) => MapEntry(k.toString(), v)),
  };
}

/// What this device remembers for a room: the video's display name plus how to
/// open it again. [path] is what `Media()` is opened with - a filesystem path,
/// or the `content://` URI on Android (kept in this field so existing call
/// sites keep working). [reference] is the richer, durable handle (iOS bookmark,
/// persisted SAF URI); null on entries written before it existed.
class LocalMediaEntry {
  const LocalMediaEntry({
    required this.name,
    required this.path,
    required this.touchedAt,
    this.reference,
  });

  final String name;
  final String path;
  final DateTime touchedAt;
  final VideoReference? reference;

  factory LocalMediaEntry.fromJson(Map<String, dynamic> json) => LocalMediaEntry(
    name: json['name'] as String,
    path: json['path'] as String,
    touchedAt: DateTime.fromMillisecondsSinceEpoch((json['touched_at'] as num?)?.toInt() ?? 0),
    reference: VideoReference.fromJson(json['ref']),
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'path': path,
    'touched_at': touchedAt.millisecondsSinceEpoch,
    if (reference != null) 'ref': reference!.toJson(),
  };

  /// Synchronous best guess for the auto-reopen decision. A `content://` URI
  /// cannot be probed synchronously, so it is optimistically true: the real
  /// answer comes from [reopen], and a failed open falls into the existing
  /// "couldn't open that file" path.
  bool get fileStillExists {
    if (reference is ContentUriReference) return true;
    // A Photos export is ours and lives in the app container, whose absolute
    // path iOS can move on an update; the bookmark still resolves, so let
    // `reopen` decide rather than call it gone on a stale path.
    if (reference is BookmarkReference && isPhotosExportPath(path)) return true;
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Open the remembered file with the access it needs (security scope, SAF
  /// grant). Prefer this over `File(path)` on mobile. The caller owns
  /// `result.video.release()`.
  Future<ResolveResult> reopen({LocalVideoAccess? access}) =>
      (access ?? LocalVideoAccess.instance).reopen(reference ?? PathReference(path), name: name);
}

class LocalMediaStore {
  // ignore: prefer_initializing_formals
  LocalMediaStore({SharedPreferences? prefs}) : _prefs = prefs;
  LocalMediaStore._() : _prefs = null;
  static final instance = LocalMediaStore._();

  final SharedPreferences? _prefs;
  Future<SharedPreferences> get _asyncPrefs async =>
      _prefs ?? await SharedPreferences.getInstance();

  Map<String, LocalMediaEntry>? _cache;

  /// Forgets what was read from preferences, so a test that changes the stored
  /// entries starts from them rather than from an earlier test's.
  @visibleForTesting
  void resetCacheForTesting() => _cache = null;
  Map<String, UploadSession>? _uploadSessionCache;

  Future<Map<String, LocalMediaEntry>> _read() async {
    final cached = _cache;
    if (cached != null) return cached;
    final entries = <String, LocalMediaEntry>{};
    try {
      final raw = (await _asyncPrefs).getString(_kStoreKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          entries[entry.key] = LocalMediaEntry.fromJson(
            (entry.value as Map).cast<String, dynamic>(),
          );
        }
      }
    } catch (e, s) {
      reportNonFatal(e, s, during: 'reading the local media map');
    }
    _cache = entries;
    return entries;
  }

  Future<void> _write(Map<String, LocalMediaEntry> entries) async {
    _cache = entries;
    try {
      final encoded = jsonEncode({
        for (final entry in entries.entries) entry.key: entry.value.toJson(),
      });
      await (await _asyncPrefs).setString(_kStoreKey, encoded);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'writing the local media map');
    }
  }

  Future<Map<String, UploadSession>> _readSessions() async {
    final cached = _uploadSessionCache;
    if (cached != null) return cached;
    final entries = <String, UploadSession>{};
    try {
      final raw = (await _asyncPrefs).getString(_kUploadSessionKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          entries[entry.key] = UploadSession.fromJson((entry.value as Map).cast<String, dynamic>());
        }
      }
    } catch (e, s) {
      reportNonFatal(e, s, during: 'reading upload sessions');
    }
    _uploadSessionCache = entries;
    return entries;
  }

  Future<void> _writeSessions(Map<String, UploadSession> entries) async {
    _uploadSessionCache = entries;
    try {
      final encoded = jsonEncode({
        for (final entry in entries.entries) entry.key: entry.value.toJson(),
      });
      await (await _asyncPrefs).setString(_kUploadSessionKey, encoded);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'writing upload sessions');
    }
  }

  Future<UploadSession?> loadUploadSession(String roomId) async => (await _readSessions())[roomId];

  Future<void> saveUploadSession({required String roomId, required UploadSession session}) async {
    final entries = Map<String, UploadSession>.from(await _readSessions());
    entries[roomId] = session;
    await _writeSessions(entries);
  }

  Future<void> clearUploadSession(String roomId) async {
    final entries = Map<String, UploadSession>.from(await _readSessions());
    if (entries.remove(roomId) == null) return;
    await _writeSessions(entries);
  }

  /// Clears all stored upload sessions from preferences upon sign-out.
  Future<void> clearAllUploadSessions() async {
    _uploadSessionCache = {};
    try {
      await (await _asyncPrefs).remove(_kUploadSessionKey);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'clearing upload sessions');
    }
  }

  /// Wipes all stored local media entries and upload sessions upon account deletion.
  Future<void> clearAll() async {
    _cache = {};
    _uploadSessionCache = {};
    try {
      final prefs = await _asyncPrefs;
      await prefs.remove(_kStoreKey);
      await prefs.remove(_kUploadSessionKey);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'clearing local media store');
    }
  }

  /// Every path a room still remembers (for the Photos-export sweep).
  Future<Set<String>> rememberedPaths() async => {
    for (final e in (await _read()).values)
      if (e.path.isNotEmpty) e.path,
  };

  Future<LocalMediaEntry?> lookup(String roomId) async => (await _read())[roomId];

  Future<void> record({
    required String roomId,
    required String name,
    required String? path,
    VideoReference? reference,
    DateTime? now,
  }) async {
    // A content:// pick has no path: it is remembered through its reference.
    final openPath = (path == null || path.isEmpty) ? reference?.mediaUri : path;
    if (openPath == null || openPath.isEmpty) return;
    final entries = Map<String, LocalMediaEntry>.from(await _read());
    entries[roomId] = LocalMediaEntry(
      name: name,
      path: openPath,
      touchedAt: now ?? DateTime.now(),
      reference: reference,
    );
    await _write(_capped(entries));
  }

  Future<void> forget(String roomId) async {
    final entries = Map<String, LocalMediaEntry>.from(await _read());
    if (entries.remove(roomId) == null) return;
    await _write(entries);
  }

  Future<void> prune({required Set<String> keepRoomIds, DateTime? now}) async {
    final clock = now ?? DateTime.now();
    final entries = await _read();
    final kept = <String, LocalMediaEntry>{
      for (final entry in entries.entries)
        if (keepRoomIds.contains(entry.key) &&
            clock.difference(entry.value.touchedAt) <= kLocalMediaTtl)
          entry.key: entry.value,
    };
    if (kept.length == entries.length) return;
    await _write(kept);
  }

  Map<String, LocalMediaEntry> _capped(Map<String, LocalMediaEntry> entries) {
    if (entries.length <= _kMaxEntries) return entries;
    final ordered = entries.entries.toList()
      ..sort((a, b) => b.value.touchedAt.compareTo(a.value.touchedAt));
    return {for (final entry in ordered.take(_kMaxEntries)) entry.key: entry.value};
  }
}
