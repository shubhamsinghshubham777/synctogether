// ignore_for_file: prefer_initializing_formals
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/diagnostics.dart';
import 'package:synctogether/player/local_video.dart';

// "Recent" shelf backing store (canvas board 47): the videos this device opened
// before, newest first, reopenable without the picker. Non-UI; the chooser
// builds on this API.
//
// ---- Public API ------------------------------------------------------------
//
//   final recents = RecentVideos.instance;          // a ChangeNotifier
//   await recents.list();                           // List<RecentVideo>, newest first
//   await recents.record(video, duration: d);       // after a successful open; RecentVideo?
//   await recents.updateDuration(id, d);            // once the player knows it
//   final r = await recents.resolve(entry);         // ResolveResult - see local_video.dart
//   await recents.remove(id);   await recents.clear();
//   await recents.thumbnailFile(id);                // File? or null: show the placeholder
//   await recents.saveThumbnail(id, jpegOrPngBytes);// from player.screenshot()
//
// POLICY (decided here, per board 47: "durable files only"):
//  * Files / desktop picks are recorded durably.
//  * A pick that only exists as a temporary copy (Photos export, anything under
//    tmp/caches) is NOT recorded - `record` returns null. A shelf row that can
//    only ever say "unavailable" is more confusing than no row.
//  * An entry whose file later disappears stays listed; `resolve` answers
//    unavailable with friendly copy and the UI offers "Remove" (or re-pick).
//  * `resolve` on success refreshes the stored reference (a stale iOS bookmark)
//    and bumps `lastOpened`, so the row jumps to the top.
//  * Entries are capped at [maxEntries] (30); the oldest go, with their thumbnails.
//  * Logs carry the display name only, never a path or URI.
//
// THUMBNAILS: generating one needs a live `Player` (media_kit screenshot), which
// this service deliberately does not own - that would spin up a second decoder
// per row. Instead the room/chooser, which already has the file open, calls
// `saveThumbnail` once (`player.screenshot()` after the first frame); the shelf
// shows `thumbnailFile` when present and a placeholder otherwise.

const _kRecentsKey = 'pt.recent_videos';
const kRecentVideosMax = 30;

class RecentVideo {
  const RecentVideo({
    required this.id,
    required this.displayName,
    required this.lastOpened,
    required this.source,
    required this.reference,
    this.sizeBytes,
    this.durationMs,
  });

  final String id;

  /// Basename only.
  final String displayName;
  final int? sizeBytes;
  final int? durationMs;
  final DateTime lastOpened;
  final VideoOrigin source;
  final VideoReference reference;

  Duration? get duration => durationMs == null ? null : Duration(milliseconds: durationMs!);

  RecentVideo copyWith({
    int? sizeBytes,
    int? durationMs,
    DateTime? lastOpened,
    VideoReference? reference,
  }) => RecentVideo(
    id: id,
    displayName: displayName,
    lastOpened: lastOpened ?? this.lastOpened,
    source: source,
    reference: reference ?? this.reference,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    durationMs: durationMs ?? this.durationMs,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': displayName,
    'size': sizeBytes,
    'duration_ms': durationMs,
    'last_opened': lastOpened.millisecondsSinceEpoch,
    'source': source.name,
    'ref': reference.toJson(),
  };

  static RecentVideo? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final m = raw.cast<String, Object?>();
    final ref = VideoReference.fromJson(m['ref']);
    final id = m['id'];
    final name = m['name'];
    if (ref == null || id is! String || name is! String) return null;
    return RecentVideo(
      id: id,
      displayName: name,
      sizeBytes: (m['size'] as num?)?.toInt(),
      durationMs: (m['duration_ms'] as num?)?.toInt(),
      lastOpened: DateTime.fromMillisecondsSinceEpoch((m['last_opened'] as num?)?.toInt() ?? 0),
      source: VideoOrigin.values.firstWhere(
        (v) => v.name == m['source'],
        orElse: () => VideoOrigin.files,
      ),
      reference: ref,
    );
  }
}

/// Stable id for a file: de-duplicates a re-pick of the same file.
String recentVideoId(VideoReference ref) =>
    sha1.convert(utf8.encode(ref.identity)).toString().substring(0, 16);

class RecentVideos extends ChangeNotifier {
  RecentVideos({
    SharedPreferences? prefs,
    LocalVideoAccess? access,
    Future<Directory> Function()? thumbnailDir,
    DateTime Function()? clock,
    this.maxEntries = kRecentVideosMax,
  }) : _prefs = prefs,
       _access = access,
       _thumbnailDir = thumbnailDir ?? _defaultThumbnailDir,
       _clock = clock ?? DateTime.now;

  static final instance = RecentVideos();

  final int maxEntries;
  final SharedPreferences? _prefs;
  final LocalVideoAccess? _access;
  final Future<Directory> Function() _thumbnailDir;
  final DateTime Function() _clock;

  List<RecentVideo>? _cache;

  LocalVideoAccess get _video => _access ?? LocalVideoAccess.instance;
  Future<SharedPreferences> get _store async => _prefs ?? await SharedPreferences.getInstance();

  static Future<Directory> _defaultThumbnailDir() async {
    final base = await getApplicationSupportDirectory();
    return Directory(p.join(base.path, 'recent_thumbs'));
  }

  Future<List<RecentVideo>> _read() async {
    final cached = _cache;
    if (cached != null) return cached;
    final out = <RecentVideo>[];
    try {
      final raw = (await _store).getString(_kRecentsKey);
      if (raw != null && raw.isNotEmpty) {
        for (final item in jsonDecode(raw) as List) {
          final e = RecentVideo.fromJson(item);
          if (e != null) out.add(e);
        }
      }
    } catch (e, s) {
      reportNonFatal(e, s, during: 'reading recent videos');
    }
    out.sort((a, b) => b.lastOpened.compareTo(a.lastOpened));
    return _cache = out;
  }

  Future<void> _write(List<RecentVideo> entries) async {
    entries.sort((a, b) => b.lastOpened.compareTo(a.lastOpened));
    if (entries.length > maxEntries) {
      final evicted = entries.sublist(maxEntries);
      entries.removeRange(maxEntries, entries.length);
      for (final e in evicted) {
        await _deleteThumbnail(e.id);
      }
    }
    _cache = entries;
    notifyListeners();
    try {
      await (await _store).setString(
        _kRecentsKey,
        jsonEncode([for (final e in entries) e.toJson()]),
      );
    } catch (e, s) {
      reportNonFatal(e, s, during: 'writing recent videos');
    }
  }

  /// Newest first. A copy: mutate nothing in it.
  Future<List<RecentVideo>> list() async => List.unmodifiable(await _read());

  /// Remember [video] after it opened. Null when it is not worth remembering
  /// (a temporary copy or a Photos pick); see the policy in the file header.
  Future<RecentVideo?> record(LocalVideo video, {Duration? duration}) async {
    if (!video.durable) {
      trace(
        'not remembering a temporary video',
        category: 'media',
        data: {'file': video.name, 'origin': video.origin.name, 'temporary': video.temporary},
      );
      return null;
    }
    final entries = List<RecentVideo>.from(await _read());
    final id = recentVideoId(video.reference);
    final i = entries.indexWhere((e) => e.id == id);
    final now = _clock();
    final entry = i >= 0
        ? entries[i].copyWith(
            lastOpened: now,
            reference: video.reference,
            sizeBytes: video.sizeBytes,
            durationMs: duration?.inMilliseconds,
          )
        : RecentVideo(
            id: id,
            displayName: video.name,
            lastOpened: now,
            source: video.origin,
            reference: video.reference,
            sizeBytes: video.sizeBytes,
            durationMs: duration?.inMilliseconds,
          );
    if (i >= 0) {
      entries[i] = entry;
    } else {
      entries.add(entry);
    }
    await _write(entries);
    return entry;
  }

  Future<void> updateDuration(String id, Duration duration) async {
    if (duration <= Duration.zero) return;
    final entries = List<RecentVideo>.from(await _read());
    final i = entries.indexWhere((e) => e.id == id);
    if (i < 0 || entries[i].durationMs == duration.inMilliseconds) return;
    entries[i] = entries[i].copyWith(durationMs: duration.inMilliseconds);
    await _write(entries);
  }

  Future<void> remove(String id) async {
    final entries = List<RecentVideo>.from(await _read());
    final before = entries.length;
    entries.removeWhere((e) => e.id == id);
    if (entries.length == before) return;
    await _deleteThumbnail(id);
    await _write(entries);
  }

  /// Forgets everything, thumbnails included, and gives Android's persisted
  /// read grants back.
  Future<void> clear() async {
    final entries = await _read();
    for (final e in entries) {
      await _deleteThumbnail(e.id);
      final ref = e.reference;
      if (ref is ContentUriReference) {
        try {
          await _video.platform.releasePersistedUri(ref.uri);
        } catch (_) {}
      }
    }
    await _write([]);
  }

  /// Open an entry again. On success the stored reference and `lastOpened` are
  /// refreshed. The caller owns the returned video's `release()`.
  Future<ResolveResult> resolve(RecentVideo entry) async {
    final result = await _video.reopen(
      entry.reference,
      name: entry.displayName,
      origin: entry.source,
      sizeBytes: entry.sizeBytes,
    );
    final video = result.video;
    if (video != null) {
      final entries = List<RecentVideo>.from(await _read());
      final i = entries.indexWhere((e) => e.id == entry.id);
      if (i >= 0) {
        entries[i] = entries[i].copyWith(
          lastOpened: _clock(),
          reference: video.reference,
          sizeBytes: video.sizeBytes,
        );
        await _write(entries);
      }
    } else {
      trace(
        'recent video unavailable',
        category: 'media',
        data: {'file': entry.displayName, 'reason': result.reason?.name},
      );
    }
    return result;
  }

  // ---- thumbnails -------------------------------------------------------------

  Future<File> _thumbFile(String id) async => File(p.join((await _thumbnailDir()).path, '$id.img'));

  /// The saved still for [id], or null (show the placeholder).
  Future<File?> thumbnailFile(String id) async {
    try {
      final f = await _thumbFile(id);
      return f.existsSync() ? f : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveThumbnail(String id, Uint8List bytes) async {
    if (bytes.isEmpty) return;
    try {
      final f = await _thumbFile(id);
      await f.parent.create(recursive: true);
      await f.writeAsBytes(bytes, flush: true);
      notifyListeners();
    } catch (e, s) {
      reportNonFatal(e, s, during: 'saving a recent video thumbnail');
    }
  }

  Future<void> _deleteThumbnail(String id) async {
    try {
      final f = await _thumbFile(id);
      if (f.existsSync()) await f.delete();
    } catch (_) {}
  }
}
