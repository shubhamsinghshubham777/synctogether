import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:synctogether/diagnostics.dart';

// The thin native seam under local-file access (`LocalVideoAccess`). Everything
// platform-specific about "keep being allowed to read the file the user picked"
// is behind [MediaAccessPlatform], so the logic above it is pure Dart and tests
// drive it with a fake. One method channel, `app.synctogether/media_access`,
// implemented in `ios/Runner/AppDelegate.swift` (MediaAccessChannel) and
// `android/.../MediaAccess.kt`; desktop has no implementation and never calls
// it (`ChannelMediaAccess` answers every call with the "nothing to do" value).
//
// iOS:     security-scoped URLs and bookmarks, iCloud download requests.
// Android: persistable SAF grants, a stat of a content:// URI, and ranged reads
//          of it (the R2 upload path; see `ContentUriUploadSource`).

/// Where an iOS file stands on disk.
enum LocalAvailability {
  /// Bytes are on the device; mpv can open the path.
  local,

  /// iCloud has been asked to download it (or already is); try again shortly.
  downloading,

  /// Neither the file nor an iCloud placeholder for it exists.
  missing,
}

/// A bookmark resolved back to a file. Resolving also STARTS security-scoped
/// access on [url]; the caller owns the matching `stopAppleAccess`.
class ResolvedBookmark {
  const ResolvedBookmark({required this.url, required this.path, this.refreshedBookmark});

  /// `file://` URL (the handle to stop access on).
  final String url;
  final String path;

  /// Set when the system reported the bookmark stale; persist this instead.
  final String? refreshedBookmark;
}

/// What the Android provider says about a content:// URI right now.
class ContentStat {
  const ContentStat({required this.name, this.sizeBytes, this.mimeType});

  /// The provider's display name (`Movie.mkv`), NOT the URI tail (`video:1234`).
  final String name;
  final int? sizeBytes;
  final String? mimeType;
}

abstract interface class MediaAccessPlatform {
  /// iOS: `startAccessingSecurityScopedResource` on a `file://` URL. False is
  /// normal for a URL inside the app container (no scope needed).
  Future<bool> startAppleAccess(String fileUrl);
  Future<void> stopAppleAccess(String fileUrl);

  /// iOS: base64 bookmark data for a picked URL, or null if the system refuses.
  Future<String?> createBookmark(String fileUrl);

  /// iOS: bookmark back to a URL (access already started), or null if the file
  /// moved off the device, was deleted, or the bookmark is no longer valid.
  Future<ResolvedBookmark?> resolveBookmark(String bookmark);

  /// iOS: whether [path] is readable now; requests an iCloud download if it
  /// is evicted (including the legacy `.name.icloud` placeholder).
  Future<LocalAvailability> ensureLocal(String path);

  /// Android: `takePersistableUriPermission` (read). False when the provider
  /// does not offer a persistable grant; the URI still works until the process
  /// dies.
  Future<bool> takePersistableUri(String uri);
  Future<void> releasePersistedUri(String uri);

  /// Android: query the provider. Null means the URI can no longer be read
  /// (grant lost, document deleted, provider gone).
  Future<ContentStat?> statContentUri(String uri);

  /// Android: up to [length] bytes of [uri] starting at [offset] (fewer only at
  /// end of file). Throws [MediaAccessException] with code `not_seekable` for a
  /// provider that serves a pipe.
  Future<Uint8List> readContentRange(String uri, int offset, int length);
}

class MediaAccessException implements Exception {
  const MediaAccessException(this.code, [this.message]);
  final String code;
  final String? message;

  bool get notSeekable => code == 'not_seekable';

  @override
  String toString() => 'MediaAccessException($code${message == null ? '' : ': $message'})';
}

class ChannelMediaAccess implements MediaAccessPlatform {
  ChannelMediaAccess({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('app.synctogether/media_access');

  final MethodChannel _channel;

  static bool get _apple => !kIsWeb && Platform.isIOS;
  static bool get _android => !kIsWeb && Platform.isAndroid;

  Future<T?> _call<T>(String method, Object? args, {required bool supported}) async {
    if (!supported) return null;
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null; // an older native runner: behave as "nothing to do"
    } on PlatformException catch (e, s) {
      if (e.code == 'not_seekable') throw MediaAccessException(e.code, e.message);
      reportNonFatal(e, s, during: 'media access $method');
      return null;
    }
  }

  @override
  Future<bool> startAppleAccess(String fileUrl) async =>
      await _call<bool>('startAccess', {'url': fileUrl}, supported: _apple) ?? false;

  @override
  Future<void> stopAppleAccess(String fileUrl) =>
      _call<void>('stopAccess', {'url': fileUrl}, supported: _apple);

  @override
  Future<String?> createBookmark(String fileUrl) =>
      _call<String>('createBookmark', {'url': fileUrl}, supported: _apple);

  @override
  Future<ResolvedBookmark?> resolveBookmark(String bookmark) async {
    final m = await _call<Map<Object?, Object?>>('resolveBookmark', {
      'bookmark': bookmark,
    }, supported: _apple);
    if (m == null || m['url'] == null || m['path'] == null) return null;
    return ResolvedBookmark(
      url: m['url']! as String,
      path: m['path']! as String,
      refreshedBookmark: m['refreshedBookmark'] as String?,
    );
  }

  @override
  Future<LocalAvailability> ensureLocal(String path) async {
    final r = await _call<String>('ensureLocal', {'path': path}, supported: _apple);
    return switch (r) {
      'downloading' => LocalAvailability.downloading,
      'missing' => LocalAvailability.missing,
      _ => LocalAvailability.local,
    };
  }

  @override
  Future<bool> takePersistableUri(String uri) async =>
      await _call<bool>('takePersistable', {'uri': uri}, supported: _android) ?? false;

  @override
  Future<void> releasePersistedUri(String uri) =>
      _call<void>('releasePersisted', {'uri': uri}, supported: _android);

  @override
  Future<ContentStat?> statContentUri(String uri) async {
    final m = await _call<Map<Object?, Object?>>('stat', {'uri': uri}, supported: _android);
    if (m == null || m['name'] == null) return null;
    return ContentStat(
      name: m['name']! as String,
      sizeBytes: (m['size'] as num?)?.toInt(),
      mimeType: m['mime'] as String?,
    );
  }

  @override
  Future<Uint8List> readContentRange(String uri, int offset, int length) async {
    final r = await _call<Uint8List>('readRange', {
      'uri': uri,
      'offset': offset,
      'length': length,
    }, supported: _android);
    if (r == null) throw const MediaAccessException('unreadable');
    return r;
  }
}
