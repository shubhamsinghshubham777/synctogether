import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/player/stream/stream_proxy.dart';
import 'package:synctogether/rooms/media_sharing_cache.dart';

import '../../support/fake_origin.dart';

const _chunk = 64 * 1024;
const _fast = StreamProxyConfig(
  chunkSize: _chunk,
  baseBackoff: Duration(milliseconds: 20),
  maxBackoff: Duration(milliseconds: 80),
  adaptEvery: Duration(milliseconds: 200),
);

Future<(int, Map<String, String>, Uint8List)> _get(
  Uri url, {
  String? range,
  String method = 'GET',
}) async {
  final client = HttpClient();
  try {
    final req = await client.openUrl(method, url);
    if (range != null) req.headers.set('range', range);
    final res = await req.close();
    final bytes = BytesBuilder();
    await for (final c in res) {
      bytes.add(c);
    }
    final headers = <String, String>{};
    res.headers.forEach((k, v) => headers[k] = v.join(','));
    return (res.statusCode, headers, bytes.takeBytes());
  } finally {
    client.close(force: true);
  }
}

void main() {
  late Directory tmp;
  late MediaSharingCache cache;
  late FakeOrigin origin;
  StreamProxy? proxy;
  var resigns = 0;

  Future<StreamProxy> boot({
    int size = _chunk * 24 + 1234,
    StreamProxyConfig config = _fast,
    void Function(String)? onFatal,
    int? totalOverride,
  }) async {
    origin = await FakeOrigin.start(size);
    resigns = 0;
    final p = await StreamProxy.start(
      originUrl: origin.url(),
      totalBytes: totalOverride ?? size,
      cacheKey: 'room-1',
      resign: () async {
        resigns++;
        return origin.url();
      },
      cache: cache,
      fileName: 'Film.MKV',
      config: config,
      bitrateBps: 8 * _chunk * 4,
      onFatal: onFatal,
    );
    proxy = p;
    return p!;
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('proxy_test');
    cache = MediaSharingCache(cacheDirectory: tmp);
  });

  tearDown(() async {
    await proxy?.close();
    proxy = null;
    await origin.close();
    await tmp.delete(recursive: true);
  });

  test('a plain GET returns the whole object with the right length and bytes', () async {
    final p = await boot();
    final (code, headers, body) = await _get(p.localUrl);
    expect(code, 200);
    expect(headers['content-length'], '${origin.data.length}');
    expect(headers['accept-ranges'], 'bytes');
    expect(body, origin.data);
  });

  test('the local URL keeps a safe extension and hides the origin', () async {
    final p = await boot();
    expect(p.localUrl.host, '127.0.0.1');
    expect(p.localUrl.path, endsWith('/video.mkv'));
    expect(p.localUrl.toString(), isNot(contains('obj/film')));
  });

  test('ranges answer 206 with Content-Range, open-ended and suffix included', () async {
    final p = await boot();
    final total = origin.data.length;
    var (code, headers, body) = await _get(p.localUrl, range: 'bytes=1000-70000');
    expect(code, 206);
    expect(headers['content-range'], 'bytes 1000-70000/$total');
    expect(body, origin.data.sublist(1000, 70001));

    (code, headers, body) = await _get(p.localUrl, range: 'bytes=${total - 500}-');
    expect(code, 206);
    expect(body, origin.data.sublist(total - 500));

    (code, headers, body) = await _get(p.localUrl, range: 'bytes=-300');
    expect(code, 206);
    expect(headers['content-range'], 'bytes ${total - 300}-${total - 1}/$total');
    expect(body, origin.data.sublist(total - 300));
  });

  test('a range past the end is 416 with the size, and an end past it is clamped', () async {
    final p = await boot();
    final total = origin.data.length;
    var (code, headers, body) = await _get(p.localUrl, range: 'bytes=$total-');
    expect(code, 416);
    expect(headers['content-range'], 'bytes */$total');
    expect(body, isEmpty);

    (code, headers, body) = await _get(p.localUrl, range: 'bytes=${total - 10}-${total + 5000}');
    expect(code, 206);
    expect(headers['content-range'], 'bytes ${total - 10}-${total - 1}/$total');
    expect(body.length, 10);
  });

  test('HEAD reports the size and sends no body', () async {
    final p = await boot();
    final (code, headers, body) = await _get(p.localUrl, method: 'HEAD');
    expect(code, 200);
    expect(headers['content-length'], '${origin.data.length}');
    expect(body, isEmpty);
    expect(origin.requests, 0, reason: 'a HEAD must not touch the origin');
  });

  test('a wrong path token is refused and never reaches the origin', () async {
    final p = await boot();
    final bad = p.localUrl.replace(pathSegments: ['nope', 'video.mkv']);
    final (code, _, _) = await _get(bad);
    expect(code, 404);
    expect(origin.requests, 0);
  });

  test('chunks come from several parallel connections and still arrive in order', () async {
    final p = await boot(size: _chunk * 40);
    origin.delayPerResponse = const Duration(milliseconds: 60);
    final (code, _, body) = await _get(p.localUrl);
    expect(code, 200);
    expect(body, origin.data);
    expect(origin.maxActive, greaterThan(1), reason: 'prefetch should fan out');
    expect(origin.maxActive, lessThanOrEqualTo(_fast.maxParallelism + 2));
  });

  test('a rewatch is served from disk without touching the origin', () async {
    final p = await boot(size: _chunk * 8);
    await _get(p.localUrl);
    final before = origin.requests;
    final (_, _, body) = await _get(p.localUrl, range: 'bytes=${_chunk * 2}-${_chunk * 5}');
    expect(body, origin.data.sublist(_chunk * 2, _chunk * 5 + 1));
    expect(origin.requests, before);
    expect(p.stats.cacheHitBytes, greaterThan(0));
  });

  test('a new proxy over the same key reuses what the last one cached', () async {
    var p = await boot(size: _chunk * 8);
    await _get(p.localUrl);
    await p.close();
    final before = origin.requests;
    p = (await StreamProxy.start(
      originUrl: origin.url(),
      totalBytes: origin.data.length,
      cacheKey: 'room-1',
      resign: () async => origin.url(),
      cache: cache,
      config: _fast,
    ))!;
    proxy = p;
    final (_, _, body) = await _get(p.localUrl, range: 'bytes=0-100000');
    expect(body, origin.data.sublist(0, 100001));
    expect(origin.requests, before);
  });

  test('a seek abandons the old region instead of fetching it', () async {
    final p = await boot(
      size: _chunk * 80,
      config: const StreamProxyConfig(
        chunkSize: _chunk,
        aheadSecs: 2,
        adaptEvery: Duration(milliseconds: 200),
      ),
    );
    origin.bodyStall = const Duration(milliseconds: 15);
    // Read a little from the start, then walk away (what mpv does on a seek).
    final client = HttpClient();
    final req = await client.getUrl(p.localUrl);
    req.headers.set('range', 'bytes=0-');
    final res = await req.close();
    var got = 0;
    await for (final c in res) {
      got += c.length;
      if (got > _chunk) break;
    }
    client.close(force: true);
    final (_, _, body) = await _get(
      p.localUrl,
      range: 'bytes=${_chunk * 60}-${_chunk * 60 + 4999}',
    );
    expect(body, origin.data.sublist(_chunk * 60, _chunk * 60 + 5000));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final starts = origin.ranges.map((r) => r.$1 ~/ _chunk).toSet();
    expect(
      starts.where((i) => i >= 20 && i < 55),
      isEmpty,
      reason: 'nothing between the old and new playhead should be fetched',
    );
    expect(origin.ranges.length, lessThan(40), reason: 'bounded prefetch, not the whole film');
  });

  test('an expired signature is re-signed inside the proxy and playback continues', () async {
    final p = await boot(size: _chunk * 16);
    origin.validToken = 'b'; // the URL the proxy holds ("a") is now a 403
    final (code, _, body) = await _get(p.localUrl);
    expect(code, 200);
    expect(body, origin.data);
    expect(resigns, inInclusiveRange(1, 2));
    expect(origin.forbidden, greaterThanOrEqualTo(1));
  });

  test('5xx answers are retried with backoff', () async {
    final p = await boot(size: _chunk * 6);
    origin.failNext5xx = 3;
    final (code, _, body) = await _get(p.localUrl);
    expect(code, 200);
    expect(body, origin.data);
    expect(p.stats.errors, greaterThanOrEqualTo(1));
  });

  test('a vanished object ends the response and reports fatal after repeated failures', () async {
    final reasons = <String>[];
    final p = await boot(size: _chunk * 10, onFatal: reasons.add);
    origin.status404After = 0;
    var failed = false;
    try {
      final (_, _, body) = await _get(p.localUrl);
      failed = body.length < origin.data.length;
    } catch (_) {
      failed = true;
    }
    expect(failed, isTrue, reason: 'the client must see a broken body, not silence');
    // Re-request a few times: three chunk failures in a row tell the room to
    // stop using the proxy.
    for (var i = 0; i < 4 && reasons.isEmpty; i++) {
      try {
        await _get(p.localUrl, range: 'bytes=${_chunk * (i + 1)}-${_chunk * (i + 1) + 10}');
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(reasons, isNotEmpty);
  });

  test('start returns null when the size is unknown and the origin is unreachable', () async {
    origin = await FakeOrigin.start(10);
    final dead = Uri.parse('http://127.0.0.1:1/obj/film.mp4?t=a');
    final p = await StreamProxy.start(
      originUrl: dead,
      totalBytes: 0,
      cacheKey: 'x',
      resign: () async => dead,
      cache: cache,
    );
    expect(p, isNull);
  });

  test('an unknown size is learned from a one-byte probe', () async {
    final p = await boot(size: _chunk * 3, totalOverride: 0);
    expect(p.totalBytes, _chunk * 3);
    final (_, headers, _) = await _get(p.localUrl, method: 'HEAD');
    expect(headers['content-length'], '${_chunk * 3}');
  });

  test('close stops the server', () async {
    final p = await boot(size: _chunk * 2);
    final url = p.localUrl;
    await p.close();
    proxy = null;
    await expectLater(_get(url), throwsA(isA<SocketException>()));
  });

  group('parseRangeHeader', () {
    test('forms', () {
      expect(parseRangeHeader(null, 100), isA<FullRange>());
      expect(parseRangeHeader('bytes=0-', 100), isA<PartialRange>());
      expect(parseRangeHeader('garbage', 100), isA<FullRange>());
      expect(parseRangeHeader('bytes=0-1,5-9', 100), isA<FullRange>());
      expect(parseRangeHeader('bytes=100-', 100), isA<UnsatisfiableRange>());
      expect(parseRangeHeader('bytes=-0', 100), isA<UnsatisfiableRange>());
      expect(parseRangeHeader('bytes=9-3', 100), isA<FullRange>());
      final r = parseRangeHeader('bytes=-500', 100) as PartialRange;
      expect((r.start, r.end), (0, 99));
    });
  });

  group('ParallelismController', () {
    final t0 = DateTime(2026);
    test('grows while saturated and paying off, then settles', () {
      final c = ParallelismController(min: 2, max: 8, initial: 4);
      expect(c.update(bps: 20e6, errors: 0, saturated: true, now: t0), 5);
      expect(c.update(bps: 30e6, errors: 0, saturated: true, now: t0), 6);
      // 6 bought only 3%: back to 5 and stop growing for a while.
      expect(c.update(bps: 31e6, errors: 0, saturated: true, now: t0), 5);
      expect(c.update(bps: 31e6, errors: 0, saturated: true, now: t0), 5);
    });
    test('does not grow when idle slots, or when already comfortable', () {
      final c = ParallelismController(min: 2, max: 8, initial: 4);
      expect(c.update(bps: 5e6, errors: 0, saturated: false, now: t0), 4);
      expect(c.update(bps: 100e6, errors: 0, saturated: true, now: t0, requiredBps: 20000000), 4);
    });
    test('steps down on errors, never below min or above max', () {
      final c = ParallelismController(min: 2, max: 5, initial: 3);
      expect(c.update(bps: 1e6, errors: 2, saturated: true, now: t0), 2);
      expect(c.update(bps: 1e6, errors: 2, saturated: true, now: t0), 2);
      final d = ParallelismController(min: 2, max: 5, initial: 5);
      expect(d.update(bps: 1e6, errors: 0, saturated: true, now: t0), 5);
    });
  });
}
