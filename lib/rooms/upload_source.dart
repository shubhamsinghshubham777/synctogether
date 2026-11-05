import 'dart:io';
import 'dart:typed_data';

import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:synctogether/player/media_access.dart';

// Where the bytes of a media-sharing upload come from. `MediaSharingService`
// reads ranges of the video through this instead of a `dart:io` `File`, because
// an Android pick is a `content://` URI with no path.
//
// DECISION (Android uploads): ranged reads of the ContentResolver file
// descriptor over the `app.synctogether/media_access` channel, 4 MiB per call,
// streamed into the part's PUT. Rejected alternatives:
//   - /proc/self/fd/<n> as a Dart `File`: re-opening a provider-backed fd by
//     path depends on SELinux and on the provider's fd being a regular file;
//     it works on some devices and EACCES on others, and the fd's lifetime has
//     to be tied to the upload. Not dependable.
//   - copying the file into the cache first: needs free space equal to the file
//     (multi-GB) and a copy's worth of time before the first byte leaves.
// Cost of the chosen path: one binder round trip and one 4 MiB buffer copy per
// chunk (about 3 per 10 MB part), well under the network cost of the part. Peak
// memory is one chunk. A provider that serves a pipe (some cloud providers)
// cannot be ranged: the first read throws `MediaAccessException('not_seekable')`
// and the upload fails with a clear cause; the honest answer there is "copy the
// video to the device first".

abstract interface class UploadSource {
  /// Basename shown to the room and sent as the object's file name.
  String get name;

  /// What a persisted `UploadSession.filePath` records: a path or a content URI.
  String get reference;

  /// `Content-Type` for the R2 object.
  String get contentType;

  Future<int> length();

  /// Bytes `[start, end)`, in order.
  Stream<List<int>> openRead(int start, int end);
}

class FileUploadSource implements UploadSource {
  FileUploadSource(this.file);

  final File file;

  @override
  String get name => p.basename(file.path);

  @override
  String get reference => file.path;

  @override
  String get contentType => lookupMimeType(file.path) ?? 'video/mp4';

  @override
  Future<int> length() => file.length();

  @override
  Stream<List<int>> openRead(int start, int end) => file.openRead(start, end);
}

class ContentUriUploadSource implements UploadSource {
  ContentUriUploadSource({
    required this.uri,
    required this.name,
    required this.platform,
    this.knownSize,
    this.mimeType,
    this.chunkBytes = 4 * 1024 * 1024,
  });

  final String uri;
  @override
  final String name;
  final int? knownSize;
  final int chunkBytes;
  final MediaAccessPlatform platform;
  final String? mimeType;

  @override
  String get reference => uri;

  @override
  String get contentType {
    final m = mimeType;
    if (m != null && m.startsWith('video/')) return m;
    return lookupMimeType(name) ?? 'video/mp4';
  }

  @override
  Future<int> length() async {
    final known = knownSize;
    if (known != null) return known;
    final stat = await platform.statContentUri(uri);
    if (stat?.sizeBytes == null) throw const MediaAccessException('unreadable', 'size unknown');
    return stat!.sizeBytes!;
  }

  @override
  Stream<List<int>> openRead(int start, int end) async* {
    var offset = start;
    while (offset < end) {
      final want = end - offset < chunkBytes ? end - offset : chunkBytes;
      final Uint8List chunk = await platform.readContentRange(uri, offset, want);
      if (chunk.isEmpty) {
        throw const MediaAccessException('unreadable', 'file ended early');
      }
      yield chunk;
      offset += chunk.length;
    }
  }
}
