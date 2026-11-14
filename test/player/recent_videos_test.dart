import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/player/local_video.dart';
import 'package:synctogether/player/media_access.dart';
import 'package:synctogether/player/recent_videos.dart';

import 'fake_media_access.dart';

LocalVideo _video(
  String name, {
  VideoReference? ref,
  VideoOrigin origin = VideoOrigin.files,
  bool temporary = false,
  int? size = 100,
}) => LocalVideo(
  name: name,
  mediaUri: '/m/$name',
  path: '/m/$name',
  origin: origin,
  reference: ref ?? PathReference('/m/$name'),
  sizeBytes: size,
  temporary: temporary,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeMediaAccess fake;
  late Directory tmp;
  late DateTime now;
  late SharedPreferences prefs;

  RecentVideos make({int max = kRecentVideosMax, SharedPreferences? p}) => RecentVideos(
    prefs: p ?? prefs,
    access: LocalVideoAccess(platform: fake, isIOS: true, delay: (_) async {}),
    thumbnailDir: () async => Directory('${tmp.path}/thumbs'),
    clock: () => now,
    maxEntries: max,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    fake = FakeMediaAccess();
    tmp = await Directory.systemTemp.createTemp('pt_recents_');
    now = DateTime.utc(2026, 11, 5, 12);
  });

  tearDown(() => tmp.delete(recursive: true));

  test('records newest first, with name, size, duration and source', () async {
    final r = make();
    await r.record(_video('a.mp4'));
    now = now.add(const Duration(minutes: 1));
    await r.record(_video('b.mkv', size: 7), duration: const Duration(minutes: 90));
    final list = await r.list();
    expect(list.map((e) => e.displayName), ['b.mkv', 'a.mp4']);
    expect(list.first.sizeBytes, 7);
    expect(list.first.duration, const Duration(minutes: 90));
    expect(list.first.source, VideoOrigin.files);
  });

  test('survives a relaunch (fresh instance, same prefs)', () async {
    await make().record(_video('a.mp4'), duration: const Duration(seconds: 61));
    final list = await make().list();
    expect(list.single.displayName, 'a.mp4');
    expect(list.single.reference, isA<PathReference>());
    expect(list.single.durationMs, 61000);
  });

  test('re-opening the same file moves it to the top without duplicating', () async {
    final r = make();
    await r.record(_video('a.mp4'), duration: const Duration(minutes: 5));
    now = now.add(const Duration(minutes: 1));
    await r.record(_video('b.mp4'));
    now = now.add(const Duration(minutes: 1));
    await r.record(_video('a.mp4'));
    final list = await r.list();
    expect(list.map((e) => e.displayName), ['a.mp4', 'b.mp4']);
    expect(list.first.durationMs, 300000, reason: 'a known duration is kept');
  });

  test('temporary copies and Photos picks are not recorded', () async {
    final r = make();
    expect(await r.record(_video('cache.mov', temporary: true)), isNull);
    expect(await r.record(_video('p.mov', origin: VideoOrigin.photos)), isNull);
    expect(await r.list(), isEmpty);
  });

  test('is capped, evicting the oldest and their thumbnails', () async {
    final r = make(max: 3);
    for (final n in ['a', 'b', 'c']) {
      final e = await r.record(_video('$n.mp4'));
      await r.saveThumbnail(e!.id, Uint8List.fromList([1, 2, 3]));
      now = now.add(const Duration(minutes: 1));
    }
    final aId = (await r.list()).last.id;
    await r.record(_video('d.mp4'));
    expect((await r.list()).map((e) => e.displayName), ['d.mp4', 'c.mp4', 'b.mp4']);
    expect(await r.thumbnailFile(aId), isNull);
  });

  test('remove and clear', () async {
    final r = make();
    final a = await r.record(_video('a.mp4'));
    await r.record(_video('b.mp4', ref: const ContentUriReference('content://x/1')));
    await r.saveThumbnail(a!.id, Uint8List.fromList([9]));
    await r.remove(a.id);
    expect((await r.list()).single.displayName, 'b.mp4');
    expect(await r.thumbnailFile(a.id), isNull);
    await r.clear();
    expect(await r.list(), isEmpty);
    expect(fake.log, contains('release:content://x/1'), reason: 'android grants are given back');
    expect(await make().list(), isEmpty);
  });

  test('updateDuration only writes real changes', () async {
    final r = make();
    final e = await r.record(_video('a.mp4'));
    var notified = 0;
    r.addListener(() => notified++);
    await r.updateDuration(e!.id, Duration.zero);
    await r.updateDuration('nope', const Duration(minutes: 1));
    expect(notified, 0);
    await r.updateDuration(e.id, const Duration(minutes: 1));
    await r.updateDuration(e.id, const Duration(minutes: 1));
    expect(notified, 1);
    expect((await r.list()).single.durationMs, 60000);
  });

  group('resolve', () {
    test('a present file is ready and bumps to the top', () async {
      final f = File('${tmp.path}/Movie.mkv')..writeAsBytesSync(Uint8List(10));
      final r = make();
      now = now.subtract(const Duration(hours: 1));
      final entry = await r.record(_video('Movie.mkv', ref: PathReference(f.path)));
      await r.record(_video('other.mkv'));
      now = now.add(const Duration(hours: 2));
      final res = await r.resolve(entry!);
      expect(res.isReady, isTrue);
      expect(res.video!.name, 'Movie.mkv');
      expect((await r.list()).first.id, entry.id);
    });

    test('a missing file stays listed and answers unavailable', () async {
      fake.defaultAvailability = LocalAvailability.missing;
      final r = make();
      final entry = await r.record(_video('gone.mkv', ref: PathReference('${tmp.path}/gone.mkv')));
      final res = await r.resolve(entry!);
      expect(res.status, ResolveStatus.unavailable);
      expect(res.reason, UnavailableReason.missing);
      expect(await r.list(), hasLength(1));
    });

    test('a stale bookmark is replaced by the refreshed one', () async {
      final f = File('${tmp.path}/Movie.mkv')..writeAsBytesSync(Uint8List(10));
      fake.resolved = ResolvedBookmark(
        url: 'file://${f.path}',
        path: f.path,
        refreshedBookmark: 'FRESH',
      );
      final r = make();
      final entry = await r.record(
        _video(
          'Movie.mkv',
          ref: const BookmarkReference(bookmark: 'OLD', lastKnownPath: '/old'),
        ),
      );
      final res = await r.resolve(entry!);
      expect(res.isReady, isTrue);
      final stored = (await make().list()).single.reference as BookmarkReference;
      expect(stored.bookmark, 'FRESH');
      expect(stored.lastKnownPath, f.path);
    });

    test('a content uri whose grant lapsed is permissionLost', () async {
      final r = make();
      final entry = await r.record(
        _video('a.mp4', ref: const ContentUriReference('content://x/9')),
      );
      fake.stat = null;
      expect((await r.resolve(entry!)).reason, UnavailableReason.permissionLost);
    });
  });

  test('thumbnails are saved and found, empty bytes ignored', () async {
    final r = make();
    final e = await r.record(_video('a.mp4'));
    expect(await r.thumbnailFile(e!.id), isNull);
    await r.saveThumbnail(e.id, Uint8List(0));
    expect(await r.thumbnailFile(e.id), isNull);
    await r.saveThumbnail(e.id, Uint8List.fromList([1, 2]));
    expect((await r.thumbnailFile(e.id))!.readAsBytesSync(), [1, 2]);
  });

  test('corrupt stored entries are skipped, not fatal', () async {
    SharedPreferences.setMockInitialValues({
      'pt.recent_videos': '[{"id":"x"},{"id":"ok","name":"a.mp4","last_opened":5,"source":"files","ref":{"kind":"path","path":"/a.mp4"}}, 7]',
    });
    final p = await SharedPreferences.getInstance();
    expect((await make(p: p).list()).single.id, 'ok');
    SharedPreferences.setMockInitialValues({'pt.recent_videos': 'not json'});
    expect(await make(p: await SharedPreferences.getInstance()).list(), isEmpty);
  });
}
