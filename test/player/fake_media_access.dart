import 'dart:typed_data';

import 'package:synctogether/player/media_access.dart';

/// In-memory [MediaAccessPlatform] for tests; every call is recorded in [log].
class FakeMediaAccess implements MediaAccessPlatform {
  final log = <String>[];

  // Apple
  bool scopeGranted = true;
  String? bookmarkToCreate = 'BOOKMARK-1';
  ResolvedBookmark? resolved;
  final availability = <LocalAvailability>[]; // consumed in order, last repeats
  LocalAvailability defaultAvailability = LocalAvailability.local;

  // Android
  bool persistable = true;
  ContentStat? stat;
  Uint8List content = Uint8List(0);
  bool seekable = true;

  @override
  Future<bool> startAppleAccess(String fileUrl) async {
    log.add('start');
    return scopeGranted;
  }

  @override
  Future<void> stopAppleAccess(String fileUrl) async => log.add('stop');

  @override
  Future<String?> createBookmark(String fileUrl) async {
    log.add('bookmark');
    return bookmarkToCreate;
  }

  @override
  Future<ResolvedBookmark?> resolveBookmark(String bookmark) async {
    log.add('resolve');
    return resolved;
  }

  @override
  Future<LocalAvailability> ensureLocal(String path) async {
    log.add('ensureLocal');
    return availability.isEmpty ? defaultAvailability : availability.removeAt(0);
  }

  @override
  Future<bool> takePersistableUri(String uri) async {
    log.add('persist');
    return persistable;
  }

  @override
  Future<void> releasePersistedUri(String uri) async => log.add('release:$uri');

  @override
  Future<ContentStat?> statContentUri(String uri) async {
    log.add('stat');
    return stat;
  }

  @override
  Future<Uint8List> readContentRange(String uri, int offset, int length) async {
    log.add('read:$offset+$length');
    if (!seekable) throw const MediaAccessException('not_seekable');
    final end = (offset + length).clamp(0, content.length);
    if (offset >= content.length) return Uint8List(0);
    return Uint8List.sublistView(content, offset, end);
  }
}
