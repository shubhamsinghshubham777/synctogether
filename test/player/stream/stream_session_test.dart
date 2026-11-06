import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/player/stream/stream_notice.dart';
import 'package:synctogether/player/stream/stream_session.dart';
import 'package:synctogether/player/stream/stream_tuning.dart';
import 'package:synctogether/rooms/media_sharing_cache.dart';
import 'package:synctogether/rooms/media_sharing_service.dart';

import '../../support/fake_origin.dart';

void main() {
  late Directory tmp;
  late FakeOrigin origin;
  final applied = <String, String>{};
  var ahead = Duration.zero;
  var readinessEdges = 0;

  DownloadUrlResult dl() => DownloadUrlResult(
    streamUrl: origin.url(),
    fileName: 'film.mp4',
    fileSize: origin.data.length,
    expiresInSeconds: 3600,
  );

  SharedStreamSession make({bool proxy = true, DateTime Function()? now}) => SharedStreamSession(
    roomId: 'r1',
    fetchUrl: () async => dl(),
    cache: MediaSharingCache(cacheDirectory: tmp),
    device: StreamDeviceClass.desktop,
    setOption: (k, v) async => applied[k] = v,
    mpvCacheBps: () async => null,
    bufferedAhead: () => ahead,
    remaining: () => const Duration(minutes: 90),
    onChanged: () {},
    onReadinessChanged: () => readinessEdges++,
    onProxyFatal: (_) {},
    proxyEnabled: () => proxy,
    now: now,
  );

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('session_test');
    origin = await FakeOrigin.start(64 * 1024 * 8);
    applied.clear();
    ahead = Duration.zero;
    readinessEdges = 0;
  });
  tearDown(() async {
    await origin.close();
    await tmp.delete(recursive: true);
  });

  test('with the proxy on, mpv is pointed at loopback and tuned for a remote stream', () async {
    final s = make();
    final uri = await s.start(dl(), duration: const Duration(minutes: 10));
    expect(uri.host, '127.0.0.1');
    expect(uri.port, isNot(origin.server.port));
    expect(applied['cache-pause-initial'], 'yes');
    expect(applied['stream-lavf-o'], contains('reconnect=1'));
    await s.dispose();
  });

  test('the toggle off, or a proxy that cannot start, falls back to the direct URL', () async {
    final off = make(proxy: false);
    final uri = await off.start(dl());
    expect(uri.port, origin.server.port);
    expect(off.proxy, isNull);
    expect(applied['demuxer-readahead-secs'], isNotNull, reason: 'still tuned');
    await off.dispose();
  });

  test('reset puts the local-file defaults back and closes the proxy', () async {
    final s = make();
    await s.start(dl());
    await s.reset();
    expect(s.proxy, isNull);
    expect(applied['cache-pause-initial'], 'no');
    expect(applied['demuxer-max-bytes'], '${32 * 1024 * 1024}');
    await s.dispose();
  });

  test('reopen reuses the live proxy; fall back drops it for a fresh direct URL', () async {
    final s = make();
    final first = await s.start(dl());
    expect(await s.reopenSource(), first);
    final direct = await s.fallBackToDirect();
    expect(direct.port, origin.server.port);
    expect(s.proxy, isNull);
    await s.dispose();
  });

  test('buffer ahead holds the member at loading until enough is buffered, then releases', () {
    fakeAsync((fa) {
      final start = DateTime(2026);
      final s = make(proxy: false, now: () => start.add(fa.elapsed));
      s.start(dl(), duration: const Duration(minutes: 10));
      fa.flushMicrotasks();
      s.bufferAhead();
      fa.flushMicrotasks();
      expect(s.holdingForBuffer, isTrue);
      expect(s.notice.notice, StreamNotice.bufferingAhead);
      expect(readinessEdges, 1);
      expect(applied['cache-pause-wait'], '$kBufferAheadTargetSecs');

      ahead = const Duration(seconds: 12);
      fa.elapse(const Duration(seconds: 2));
      expect(s.holdingForBuffer, isTrue);
      expect(s.holdProgress, (12, 30));

      ahead = const Duration(seconds: 31);
      fa.elapse(const Duration(seconds: 1));
      expect(s.holdingForBuffer, isFalse);
      expect(s.notice.notice, StreamNotice.none);
      expect(readinessEdges, 2);
      s.dispose();
      fa.flushMicrotasks();
    });
  });

  test('a hold never outlasts the cap, so one slow link cannot hold the room', () {
    fakeAsync((fa) {
      final start = DateTime(2026);
      final s = make(proxy: false, now: () => start.add(fa.elapsed));
      s.start(dl(), duration: const Duration(minutes: 10));
      fa.flushMicrotasks();
      s.bufferAhead();
      fa.elapse(kBufferAheadMaxHold + const Duration(seconds: 2));
      expect(s.holdingForBuffer, isFalse);
      s.dispose();
      fa.flushMicrotasks();
    });
  });

  test('Start anyway releases at once', () {
    fakeAsync((fa) {
      final s = make(proxy: false);
      s.start(dl());
      fa.flushMicrotasks();
      s.bufferAhead();
      s.releaseHold();
      expect(s.holdingForBuffer, isFalse);
      s.dispose();
      fa.flushMicrotasks();
    });
  });
}
