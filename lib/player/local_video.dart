// ignore_for_file: prefer_initializing_formals
import 'dart:io';

import 'package:fast_file_picker/fast_file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:synctogether/diagnostics.dart';
import 'package:synctogether/player/media_access.dart';
import 'package:synctogether/player/media_file_types.dart';
import 'package:synctogether/player/photo_exports.dart';
import 'package:synctogether/rooms/upload_source.dart';

// Local-video ACCESS: turning whatever a picker (or a stored reference) gives us
// into one handle the rest of the app can play, upload and remember, on every
// platform. This is the non-UI API the chooser and room screens build on.
//
// ---- Public API (one import: this file) ------------------------------------
//
//   final access = LocalVideoAccess.instance;
//
//   // 1. After a pick (FastFilePicker.pickFile(acceptedTypeGroups: [kVideoTypeGroup])):
//   final r = await access.adopt(picked);              // ResolveResult
//   if (r.video == null) -> show r.message (friendly copy, nothing to release)
//   // r.status == downloading (iCloud): await access.waitForDownload(r) first.
//   final video = r.video!;
//   Media(video.mediaUri)                              // path, file:// or content://
//   video.name                                         // real display name; the gate's identity
//   video.uploadSource()                               // for MediaSharingService (works for URIs)
//   video.file                                         // File? - null for a content:// URI
//   video.reference                                    // persist this (VideoReference)
//   // ...when the file is replaced / the room is left / app disposes it:
//   await video.release();                             // stops iOS security-scoped access
//
//   // 2. Reopen something remembered (Recents, per-room memory):
//   final r = await access.reopen(reference, name: 'Movie.mkv');
//   // Same ResolveResult; `video.reference` may be a REFRESHED reference (a stale
//   // iOS bookmark) - persist it again.
//
// Rules the implementation keeps (so callers need not):
//  * `name` is always the display name, never the URI tail (`video:1234`) and
//    never a full path - safe for the readiness gate and for logs.
//  * Android: the pick is persisted with takePersistableUriPermission the
//    moment it is adopted; `reopen` proves access by actually querying the
//    provider, not by trusting the grant list.
//  * iOS: access is started on pick and HELD until `release()`; a bookmark is
//    created so the file can be reopened after relaunch; an iCloud-evicted file
//    is asked to download.
//  * Desktop: paths as before. (macOS Store sandbox bookmarks are not done yet:
//    after relaunch such a path may be unreadable and resolves as unavailable.)
//  * Nothing here throws for an expected outcome; failures become
//    `ResolveResult.unavailable` with friendly copy and a `trace`.

/// Where a pick came from.
enum VideoOrigin {
  /// Files app / document picker / SAF / any filesystem the user browsed.
  files,

  /// The photo library. Such picks exist only as a temporary copy, so they are
  /// never remembered (see `RecentVideos.record`).
  photos,

  /// A desktop file dialog.
  desktop,
}

/// How to get at a file again. The persisted, device-scoped half of a pick.
sealed class VideoReference {
  const VideoReference();

  /// What `Media()` is opened with when this reference resolves with no help.
  String get mediaUri;

  /// Stable identity of the underlying file (for de-duplicating Recents). Never
  /// logged: it contains a path or URI.
  String get identity;

  Map<String, Object?> toJson();

  static VideoReference? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final m = raw.cast<String, Object?>();
    switch (m['kind']) {
      case 'path':
        final path = m['path'];
        return path is String && path.isNotEmpty ? PathReference(path) : null;
      case 'bookmark':
        final b = m['bookmark'];
        final path = m['path'];
        return b is String && b.isNotEmpty && path is String
            ? BookmarkReference(bookmark: b, lastKnownPath: path)
            : null;
      case 'content':
        final uri = m['uri'];
        return uri is String && uri.isNotEmpty ? ContentUriReference(uri) : null;
    }
    return null;
  }
}

/// A plain filesystem path (desktop, Android cache files, iOS files inside the
/// app's own container).
final class PathReference extends VideoReference {
  const PathReference(this.path);
  final String path;

  @override
  String get mediaUri => path;
  @override
  String get identity => 'path:$path';
  @override
  Map<String, Object?> toJson() => {'kind': 'path', 'path': path};
}

/// An iOS security-scoped bookmark (base64) plus the path it last resolved to,
/// which is what the legacy per-room store and the UI fall back on.
final class BookmarkReference extends VideoReference {
  const BookmarkReference({required this.bookmark, required this.lastKnownPath});
  final String bookmark;
  final String lastKnownPath;

  @override
  String get mediaUri => lastKnownPath;
  @override
  String get identity => 'path:$lastKnownPath';
  @override
  Map<String, Object?> toJson() => {
    'kind': 'bookmark',
    'bookmark': bookmark,
    'path': lastKnownPath,
  };
}

/// An Android `content://` document URI with a persisted read grant.
final class ContentUriReference extends VideoReference {
  const ContentUriReference(this.uri);
  final String uri;

  @override
  String get mediaUri => uri;
  @override
  String get identity => 'content:$uri';
  @override
  Map<String, Object?> toJson() => {'kind': 'content', 'uri': uri};
}

enum ResolveStatus {
  /// Playable now.
  ready,

  /// iCloud is fetching the file; call `waitForDownload`.
  downloading,

  /// Cannot be opened; `ResolveResult.message` says why in friendly copy.
  unavailable,
}

enum UnavailableReason {
  /// The file is gone or moved.
  missing,

  /// The grant lapsed (Android permission revoked, iOS bookmark invalid).
  permissionLost,

  /// Present but the provider will not serve it (offline cloud provider...).
  unreadable,

  /// iCloud did not finish downloading in time.
  downloadTimedOut,
}

const kFileMissingMessage = "Hmm, we can't find that video any more. Pick it again to keep going.";
const kFileAccessLostMessage =
    'Hmm, this device no longer lets us open that video. Pick it again to give access back.';
const kFileUnreadableMessage =
    "Hmm, that video won't open right now. If it lives in the cloud, check you're online and try again.";
const kFileDownloadTimedOutMessage =
    "Hmm, that video is still downloading from iCloud. Give it a minute and try again.";

class ResolveResult {
  const ResolveResult.ready(LocalVideo this.video)
    : status = ResolveStatus.ready,
      reason = null,
      message = null;
  const ResolveResult.downloading(LocalVideo this.video)
    : status = ResolveStatus.downloading,
      reason = null,
      message = 'Downloading from iCloud...';
  const ResolveResult.unavailable(UnavailableReason this.reason, this.message)
    : status = ResolveStatus.unavailable,
      video = null;

  final ResolveStatus status;

  /// Non-null for [ResolveStatus.ready] and [ResolveStatus.downloading].
  final LocalVideo? video;
  final UnavailableReason? reason;

  /// Friendly copy for the UI; null when ready.
  final String? message;

  bool get isReady => status == ResolveStatus.ready;
}

/// A picked or reopened local video, ready to play. Holds platform access (iOS
/// security scope) until [release].
class LocalVideo {
  LocalVideo({
    required this.name,
    required this.mediaUri,
    required this.origin,
    required this.reference,
    this.path,
    this.contentUri,
    this.sizeBytes,
    this.mimeType,
    this.temporary = false,
    String? scopedUrl,
    MediaAccessPlatform? platform,
  }) : _scopedUrl = scopedUrl,
       _platform = platform;

  /// Display name, basename only. Also the readiness gate's identity.
  final String name;

  /// Open this with `Media()`: a filesystem path, `file://` URL or `content://` URI.
  final String mediaUri;

  /// A real filesystem path when there is one (null for Android `content://`).
  final String? path;

  /// The Android document URI, when that is what this is.
  final String? contentUri;

  final int? sizeBytes;
  final String? mimeType;
  final VideoOrigin origin;

  /// What to persist to find this file again (possibly refreshed on reopen).
  final VideoReference reference;

  /// A copy in tmp/caches (a Photos export, a share-sheet copy): it will not be
  /// there after the OS cleans up, so it is not worth remembering.
  final bool temporary;

  final String? _scopedUrl;
  final MediaAccessPlatform? _platform;
  bool _released = false;

  bool get isContentUri => contentUri != null;

  /// Whether remembering this in Recents is worthwhile.
  /// A Photos export is kept days, not forever, so it never joins Recent even
  /// when a room reopens it (which loses the `photos` origin).
  bool get durable =>
      !temporary && origin != VideoOrigin.photos && !(path != null && isPhotosExportPath(path!));

  /// The file on disk, or null for a content:// URI.
  File? get file => path == null ? null : File(path!);

  /// The source to hand to `MediaSharingService` (`source:` parameter).
  UploadSource uploadSource() {
    final uri = contentUri;
    if (uri != null) {
      return ContentUriUploadSource(
        uri: uri,
        name: name,
        platform: _platform ?? ChannelMediaAccess(),
        knownSize: sizeBytes,
        mimeType: mimeType,
      );
    }
    return FileUploadSource(File(path ?? mediaUri));
  }

  /// Stops iOS security-scoped access. Idempotent; a no-op elsewhere.
  Future<void> release() async {
    final url = _scopedUrl;
    if (_released || url == null) return;
    _released = true;
    try {
      await _platform?.stopAppleAccess(url);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'releasing local video access');
    }
  }
}

/// A name that is fit to show and to compare across devices: the picker's own
/// display name when it has one, else the decoded last segment of the path or
/// URI. Never the raw `video:1234` tail of a SAF URI when a name is known.
String displayNameFor({String? pickerName, String? path, String? uri}) {
  final given = pickerName?.trim();
  if (given != null && given.isNotEmpty) return given;
  String lastOf(String s) => s.split(RegExp(r'[/\\]')).last;
  if (path != null && path.isNotEmpty) return lastOf(path);
  final raw = lastOf(uri ?? '');
  try {
    return Uri.decodeComponent(raw);
  } catch (_) {
    return raw; // a stray '%' that is not an escape sequence
  }
}

/// Whether [path] sits in a location the OS may wipe (tmp / caches).
@visibleForTesting
bool isTemporaryPath(String path) {
  final p = path.replaceAll('\\', '/');
  return p.contains('/tmp/') ||
      p.contains('/Library/Caches/') ||
      p.contains('/cache/') ||
      p.contains('/Caches/');
}

typedef AsyncDelay = Future<void> Function(Duration);

class LocalVideoAccess {
  LocalVideoAccess({MediaAccessPlatform? platform, bool? isIOS, bool? isDesktop, AsyncDelay? delay})
    : platform = platform ?? ChannelMediaAccess(),
      _ios = isIOS ?? (!kIsWeb && Platform.isIOS),
      _desktop =
          isDesktop ?? (!kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux)),
      _delay = delay ?? Future<void>.delayed;

  static final instance = LocalVideoAccess();

  final MediaAccessPlatform platform;
  final bool _ios;
  final bool _desktop;
  final AsyncDelay _delay;

  /// Adopt a fresh pick. See the file header.
  Future<ResolveResult> adopt(FastFilePickerPath picked, {VideoOrigin? origin}) =>
      adoptPick(pickerName: picked.name, path: picked.path, uri: picked.uri, origin: origin);

  /// [adopt] over plain values (what tests and non-FastFilePicker callers use).
  Future<ResolveResult> adoptPick({
    String? pickerName,
    String? path,
    String? uri,
    VideoOrigin? origin,
  }) async {
    final kind = origin ?? (_desktop ? VideoOrigin.desktop : VideoOrigin.files);
    final name = displayNameFor(pickerName: pickerName, path: path, uri: uri);

    if (uri != null && uri.startsWith('content://')) {
      return _adoptContent(uri: uri, fallbackName: name, origin: kind);
    }
    if (path == null) {
      // A bare non-content URI (an http(s) or file: string): hand it to mpv.
      if (uri == null) {
        return const ResolveResult.unavailable(UnavailableReason.missing, kFileMissingMessage);
      }
      return ResolveResult.ready(
        LocalVideo(name: name, mediaUri: uri, origin: kind, reference: PathReference(uri)),
      );
    }
    if (_ios) return _adoptApple(path: path, uri: uri, name: name, origin: kind);

    final exists = _exists(path);
    if (!exists) {
      trace('picked file is not readable', category: 'media', data: {'file': name});
      return const ResolveResult.unavailable(UnavailableReason.missing, kFileMissingMessage);
    }
    return ResolveResult.ready(
      LocalVideo(
        name: name,
        mediaUri: path,
        path: path,
        origin: kind,
        reference: PathReference(path),
        sizeBytes: _sizeOf(path),
        temporary: isTemporaryPath(path),
        platform: platform,
      ),
    );
  }

  /// Open a remembered file again. Never throws for an expected outcome.
  Future<ResolveResult> reopen(
    VideoReference ref, {
    required String name,
    VideoOrigin origin = VideoOrigin.files,
    int? sizeBytes,
  }) async {
    try {
      switch (ref) {
        case ContentUriReference():
          return await _statThen(ref.uri, name, origin);
        case BookmarkReference():
          return await _reopenBookmark(ref, name: name, origin: origin);
        case PathReference():
          return await _reopenPath(ref, name: name, origin: origin, sizeBytes: sizeBytes);
      }
    } catch (e, s) {
      reportNonFatal(e, s, during: 'reopening a remembered local video');
      return const ResolveResult.unavailable(UnavailableReason.unreadable, kFileUnreadableMessage);
    }
  }

  /// Poll an iCloud download started by [adopt]/[reopen] until the bytes land.
  /// Returns the ready result, or unavailable on timeout or if it vanishes.
  /// Holds no access of its own: on failure the video's scope is released.
  Future<ResolveResult> waitForDownload(
    ResolveResult pending, {
    Duration timeout = const Duration(minutes: 2),
    Duration interval = const Duration(seconds: 1),
  }) async {
    final video = pending.video;
    if (pending.status != ResolveStatus.downloading || video == null) return pending;
    final path = video.path;
    if (path == null) return ResolveResult.ready(video);
    var waited = Duration.zero;
    while (true) {
      final a = await platform.ensureLocal(path);
      if (a == LocalAvailability.local) {
        trace('icloud download finished', category: 'media', data: {'file': video.name});
        return ResolveResult.ready(video);
      }
      if (a == LocalAvailability.missing || waited >= timeout) {
        await video.release();
        trace(
          'icloud download gave up',
          category: 'media',
          data: {'file': video.name, 'missing': a == LocalAvailability.missing},
        );
        return a == LocalAvailability.missing
            ? const ResolveResult.unavailable(UnavailableReason.missing, kFileMissingMessage)
            : const ResolveResult.unavailable(
                UnavailableReason.downloadTimedOut,
                kFileDownloadTimedOutMessage,
              );
      }
      await _delay(interval);
      waited += interval;
    }
  }

  // ---- Android ------------------------------------------------------------

  Future<ResolveResult> _adoptContent({
    required String uri,
    required String fallbackName,
    required VideoOrigin origin,
  }) async {
    final persisted = await platform.takePersistableUri(uri);
    final stat = await platform.statContentUri(uri);
    if (stat == null) {
      trace('picked content uri is unreadable', category: 'media', data: {'persisted': persisted});
      return const ResolveResult.unavailable(UnavailableReason.unreadable, kFileUnreadableMessage);
    }
    trace(
      'content uri adopted',
      category: 'media',
      data: {'file': stat.name, 'persisted': persisted, 'bytes': stat.sizeBytes},
    );
    return ResolveResult.ready(_contentVideo(uri, stat, origin, fallbackName));
  }

  Future<ResolveResult> _statThen(String uri, String name, VideoOrigin origin) async {
    final stat = await platform.statContentUri(uri);
    if (stat == null) {
      trace('remembered content uri no longer readable', category: 'media', data: {'file': name});
      return const ResolveResult.unavailable(
        UnavailableReason.permissionLost,
        kFileAccessLostMessage,
      );
    }
    return ResolveResult.ready(_contentVideo(uri, stat, origin, name));
  }

  LocalVideo _contentVideo(String uri, ContentStat stat, VideoOrigin origin, String fallbackName) =>
      LocalVideo(
        name: stat.name.isNotEmpty ? stat.name : fallbackName,
        mediaUri: uri,
        contentUri: uri,
        sizeBytes: stat.sizeBytes,
        mimeType: stat.mimeType,
        origin: origin,
        reference: ContentUriReference(uri),
        platform: platform,
      );

  // ---- iOS ----------------------------------------------------------------

  Future<ResolveResult> _adoptApple({
    required String path,
    required String? uri,
    required String name,
    required VideoOrigin origin,
  }) async {
    final url = uri ?? Uri.file(path).toString();
    final scoped = await platform.startAppleAccess(url);
    final availability = await platform.ensureLocal(path);
    if (availability == LocalAvailability.missing) {
      if (scoped) await platform.stopAppleAccess(url);
      trace(
        'picked file missing after scope start',
        category: 'media',
        data: {'file': name, 'scoped': scoped},
      );
      return const ResolveResult.unavailable(UnavailableReason.missing, kFileMissingMessage);
    }
    final bookmark = await platform.createBookmark(url);
    final video = LocalVideo(
      name: name,
      mediaUri: path,
      path: path,
      origin: origin,
      reference: bookmark != null
          ? BookmarkReference(bookmark: bookmark, lastKnownPath: path)
          : PathReference(path),
      sizeBytes: _sizeOf(path),
      temporary: isTemporaryPath(path),
      scopedUrl: scoped ? url : null,
      platform: platform,
    );
    trace(
      'apple file adopted',
      category: 'media',
      data: {
        'file': name,
        'scoped': scoped,
        'bookmarked': bookmark != null,
        'downloading': availability == LocalAvailability.downloading,
      },
    );
    return availability == LocalAvailability.downloading
        ? ResolveResult.downloading(video)
        : ResolveResult.ready(video);
  }

  Future<ResolveResult> _reopenBookmark(
    BookmarkReference ref, {
    required String name,
    required VideoOrigin origin,
  }) async {
    final resolved = await platform.resolveBookmark(ref.bookmark);
    if (resolved == null) {
      trace('bookmark did not resolve', category: 'media', data: {'file': name});
      return const ResolveResult.unavailable(
        UnavailableReason.permissionLost,
        kFileAccessLostMessage,
      );
    }
    final availability = await platform.ensureLocal(resolved.path);
    if (availability == LocalAvailability.missing) {
      await platform.stopAppleAccess(resolved.url);
      return const ResolveResult.unavailable(UnavailableReason.missing, kFileMissingMessage);
    }
    final refreshed = resolved.refreshedBookmark;
    final video = LocalVideo(
      name: name,
      mediaUri: resolved.path,
      path: resolved.path,
      origin: origin,
      reference: BookmarkReference(
        bookmark: refreshed ?? ref.bookmark,
        lastKnownPath: resolved.path,
      ),
      sizeBytes: _sizeOf(resolved.path),
      scopedUrl: resolved.url,
      platform: platform,
    );
    trace(
      'bookmark resolved',
      category: 'media',
      data: {
        'file': name,
        'stale': refreshed != null,
        'downloading': availability == LocalAvailability.downloading,
      },
    );
    return availability == LocalAvailability.downloading
        ? ResolveResult.downloading(video)
        : ResolveResult.ready(video);
  }

  // ---- plain paths ----------------------------------------------------------

  Future<ResolveResult> _reopenPath(
    PathReference ref, {
    required String name,
    required VideoOrigin origin,
    int? sizeBytes,
  }) async {
    var availability = _exists(ref.path) ? LocalAvailability.local : LocalAvailability.missing;
    if (availability == LocalAvailability.missing && _ios) {
      availability = await platform.ensureLocal(ref.path); // an evicted iCloud placeholder
    }
    if (availability == LocalAvailability.missing) {
      trace('remembered path is gone', category: 'media', data: {'file': name});
      return const ResolveResult.unavailable(UnavailableReason.missing, kFileMissingMessage);
    }
    final video = LocalVideo(
      name: name,
      mediaUri: ref.path,
      path: ref.path,
      origin: origin,
      reference: ref,
      sizeBytes: _sizeOf(ref.path) ?? sizeBytes,
      platform: platform,
    );
    return availability == LocalAvailability.downloading
        ? ResolveResult.downloading(video)
        : ResolveResult.ready(video);
  }

  static bool _exists(String path) {
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  static int? _sizeOf(String path) {
    try {
      return File(path).lengthSync();
    } catch (_) {
      return null;
    }
  }
}

/// Whether a pick should be refused before the player is asked to open it.
/// Thin pairing of [looksLikeNonMedia] with the trace the call sites repeat.
bool refuseNonMedia(String name) {
  if (!looksLikeNonMedia(name)) return false;
  trace('picked file is not a video', category: 'media', data: {'file': name});
  return true;
}
