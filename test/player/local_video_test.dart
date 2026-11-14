import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/player/local_video.dart';
import 'package:synctogether/player/media_access.dart';
import 'package:synctogether/rooms/upload_source.dart';

import 'fake_media_access.dart';

void main() {
  late FakeMediaAccess fake;
  late Directory tmp;
  late File movie;

  setUp(() async {
    fake = FakeMediaAccess();
    tmp = await Directory.systemTemp.createTemp('pt_local_video_');
    movie = File('${tmp.path}/Movie (2005).mkv')..writeAsBytesSync(Uint8List(2048));
  });

  tearDown(() => tmp.delete(recursive: true));

  LocalVideoAccess access({bool ios = false, bool desktop = false}) =>
      LocalVideoAccess(platform: fake, isIOS: ios, isDesktop: desktop, delay: (_) async {});

  group('displayNameFor', () {
    test('prefers the picker name over the SAF tail', () {
      expect(
        displayNameFor(pickerName: 'Movie.mkv', uri: 'content://x/document/video%3A1234'),
        'Movie.mkv',
      );
    });
    test('falls back to the path basename, then the decoded uri tail', () {
      expect(displayNameFor(path: '/a/b/Movie.mkv'), 'Movie.mkv');
      expect(displayNameFor(path: r'C:\a\Movie.mkv'), 'Movie.mkv');
      expect(displayNameFor(uri: 'file:///a/Movie%20(2005).mkv'), 'Movie (2005).mkv');
      expect(displayNameFor(uri: 'file:///a/100%.mkv'), '100%.mkv');
    });
  });

  test('isTemporaryPath', () {
    expect(isTemporaryPath('/private/var/mobile/tmp/x.mp4'), isTrue);
    expect(isTemporaryPath('/data/user/0/app/cache/x.mp4'), isTrue);
    expect(isTemporaryPath('/Users/me/Movies/x.mp4'), isFalse);
  });

  test('references round-trip through json and reject junk', () {
    for (final r in <VideoReference>[
      const PathReference('/a/b.mp4'),
      const BookmarkReference(bookmark: 'AAA=', lastKnownPath: '/a/b.mp4'),
      const ContentUriReference('content://x/1'),
    ]) {
      final back = VideoReference.fromJson(r.toJson());
      expect(back?.toJson(), r.toJson());
      expect(back?.identity, r.identity);
    }
    expect(VideoReference.fromJson({'kind': 'nope'}), isNull);
    expect(VideoReference.fromJson({'kind': 'path', 'path': ''}), isNull);
    expect(VideoReference.fromJson('x'), isNull);
  });

  group('desktop', () {
    test('adopts a path, keeping the real file name', () async {
      final r = await access(desktop: true)
          .adoptPick(pickerName: 'Movie (2005).mkv', path: movie.path);
      expect(r.isReady, isTrue);
      final v = r.video!;
      expect(v.name, 'Movie (2005).mkv');
      expect(v.mediaUri, movie.path);
      expect(v.sizeBytes, 2048);
      expect(v.origin, VideoOrigin.desktop);
      // The fixture sits in the runner's temp dir, which is /tmp/ on Linux and
      // so counts as temporary there; durability follows the path rule.
      expect(v.durable, !isTemporaryPath(movie.path));
      expect(v.reference, isA<PathReference>());
      expect(v.uploadSource(), isA<FileUploadSource>());
      expect(fake.log, isEmpty, reason: 'no native calls on desktop');
    });

    test('a vanished file is unavailable with friendly copy', () async {
      final r = await access(desktop: true).adoptPick(path: '${tmp.path}/gone.mp4');
      expect(r.status, ResolveStatus.unavailable);
      expect(r.reason, UnavailableReason.missing);
      expect(r.message, kFileMissingMessage);
      expect(r.video, isNull);
    });

    test('reopen of a path', () async {
      final ok = await access(desktop: true).reopen(PathReference(movie.path), name: 'Movie.mkv');
      expect(ok.isReady, isTrue);
      final gone = await access(desktop: true)
          .reopen(PathReference('${tmp.path}/x.mkv'), name: 'x');
      expect(gone.reason, UnavailableReason.missing);
    });
  });

  group('android content uri', () {
    const uri = 'content://com.android.providers.media.documents/document/video%3A1234';
    setUp(() {
      fake.stat = const ContentStat(
        name: 'Movie.mkv',
        sizeBytes: 5000,
        mimeType: 'video/x-matroska',
      );
    });

    test('takes a persistable grant and names the file by display name', () async {
      final r = await access().adoptPick(pickerName: 'Movie.mkv', uri: uri);
      final v = r.video!;
      expect(fake.log, ['persist', 'stat']);
      expect(v.name, 'Movie.mkv');
      expect(v.mediaUri, uri);
      expect(v.path, isNull);
      expect(v.file, isNull);
      expect(v.isContentUri, isTrue);
      expect(v.sizeBytes, 5000);
      expect(v.reference, isA<ContentUriReference>());
      expect(v.uploadSource(), isA<ContentUriUploadSource>());
      expect(v.uploadSource().name, 'Movie.mkv');
      expect(v.uploadSource().contentType, 'video/x-matroska');
    });

    test('still adopts when no persistable grant is offered', () async {
      fake.persistable = false;
      expect((await access().adoptPick(pickerName: 'a.mp4', uri: uri)).isReady, isTrue);
    });

    test('an unreadable document is unavailable, not a throw', () async {
      fake.stat = null;
      final r = await access().adoptPick(pickerName: 'a.mp4', uri: uri);
      expect(r.reason, UnavailableReason.unreadable);
      expect(r.message, kFileUnreadableMessage);
    });

    test('reopen proves access by querying the provider', () async {
      final ok = await access().reopen(const ContentUriReference(uri), name: 'Movie.mkv');
      expect(ok.isReady, isTrue);
      fake.stat = null;
      final lost = await access().reopen(const ContentUriReference(uri), name: 'Movie.mkv');
      expect(lost.reason, UnavailableReason.permissionLost);
    });

    test('upload source streams the file in chunks through the channel', () async {
      fake.content = Uint8List.fromList(List.generate(5000, (i) => i % 251));
      final video = (await access().adoptPick(pickerName: 'Movie.mkv', uri: uri)).video!;
      final src = ContentUriUploadSource(
        uri: uri,
        name: video.name,
        platform: fake,
        knownSize: video.sizeBytes,
        chunkBytes: 2000,
      );
      expect(await src.length(), 5000);
      fake.log.clear();
      final got = <int>[for (final c in await src.openRead(1000, 4500).toList()) ...c];
      expect(got, fake.content.sublist(1000, 4500));
      expect(fake.log, ['read:1000+2000', 'read:3000+1500']);
    });
  });

  group('ios', () {
    test('starts scope, bookmarks and holds access until release', () async {
      final r = await access(ios: true)
          .adoptPick(pickerName: 'Movie (2005).mkv', path: movie.path, uri: 'file://${movie.path}');
      final v = r.video!;
      expect(fake.log, ['start', 'ensureLocal', 'bookmark']);
      expect(v.reference, isA<BookmarkReference>());
      expect((v.reference as BookmarkReference).bookmark, 'BOOKMARK-1');
      await v.release();
      await v.release();
      expect(fake.log.where((e) => e == 'stop'), hasLength(1), reason: 'release is idempotent');
    });

    test('a url that needs no scope is not stopped', () async {
      fake.scopeGranted = false;
      final v = (await access(
        ios: true,
      ).adoptPick(path: movie.path, uri: 'file://${movie.path}')).video!;
      await v.release();
      expect(fake.log, isNot(contains('stop')));
    });

    test('no bookmark falls back to a path reference', () async {
      fake.bookmarkToCreate = null;
      final v = (await access(ios: true).adoptPick(path: movie.path)).video!;
      expect(v.reference, isA<PathReference>());
    });

    test('an iCloud-evicted file reports downloading, then ready', () async {
      fake.availability.addAll([LocalAvailability.downloading, LocalAvailability.downloading]);
      fake.defaultAvailability = LocalAvailability.local;
      final pending = await access(ios: true)
          .adoptPick(path: movie.path, uri: 'file://${movie.path}');
      expect(pending.status, ResolveStatus.downloading);
      final done = await access(ios: true).waitForDownload(pending);
      expect(done.isReady, isTrue);
    });

    test('a download that never lands times out and releases the scope', () async {
      fake.defaultAvailability = LocalAvailability.downloading;
      final a = access(ios: true);
      final pending = await a.adoptPick(path: movie.path, uri: 'file://${movie.path}');
      final r = await a.waitForDownload(
        pending,
        timeout: const Duration(seconds: 3),
        interval: const Duration(seconds: 1),
      );
      expect(r.reason, UnavailableReason.downloadTimedOut);
      expect(r.message, kFileDownloadTimedOutMessage);
      expect(fake.log, contains('stop'));
    });

    test(
      'a file that is gone after the scope opened is unavailable and scope is stopped',
      () async {
        fake.defaultAvailability = LocalAvailability.missing;
        final r = await access(ios: true).adoptPick(path: movie.path, uri: 'file://${movie.path}');
        expect(r.reason, UnavailableReason.missing);
        expect(fake.log, contains('stop'));
      },
    );

    test('reopen resolves a bookmark, refreshes a stale one and holds scope', () async {
      fake.resolved = ResolvedBookmark(
        url: 'file://${movie.path}',
        path: movie.path,
        refreshedBookmark: 'BOOKMARK-2',
      );
      final r = await access(ios: true).reopen(
        BookmarkReference(bookmark: 'BOOKMARK-1', lastKnownPath: '/old/place.mkv'),
        name: 'Movie.mkv',
      );
      final ref = r.video!.reference as BookmarkReference;
      expect(ref.bookmark, 'BOOKMARK-2');
      expect(ref.lastKnownPath, movie.path);
      expect(fake.log, ['resolve', 'ensureLocal']);
      await r.video!.release();
      expect(fake.log.last, 'stop');
    });

    test('an invalid bookmark means the access was lost', () async {
      fake.resolved = null;
      final r = await access(ios: true).reopen(
        const BookmarkReference(bookmark: 'x', lastKnownPath: '/p.mkv'),
        name: 'p',
      );
      expect(r.reason, UnavailableReason.permissionLost);
      expect(r.message, kFileAccessLostMessage);
    });

    test('a bookmark whose file was deleted is missing and scope is stopped', () async {
      fake.resolved = ResolvedBookmark(url: 'file:///x', path: '/x');
      fake.defaultAvailability = LocalAvailability.missing;
      final r = await access(ios: true).reopen(
        const BookmarkReference(bookmark: 'x', lastKnownPath: '/x'),
        name: 'x',
      );
      expect(r.reason, UnavailableReason.missing);
      expect(fake.log, contains('stop'));
    });
  });

  test('a temporary copy is not durable', () async {
    final cache = Directory('${tmp.path}/tmp')..createSync();
    final f = File('${cache.path}/photo.mov')..writeAsBytesSync([1, 2, 3]);
    final v = (await access(desktop: true).adoptPick(path: f.path)).video!;
    expect(v.temporary, isTrue);
    expect(v.durable, isFalse);
  });
}
