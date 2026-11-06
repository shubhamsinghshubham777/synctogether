import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// A tiny object store for proxy tests: serves one deterministic blob with real
/// Range semantics, and can be told to misbehave (expire its signature, fail
/// with 5xx, answer slowly) so the proxy's recovery paths run for real.
class FakeOrigin {
  FakeOrigin._(this.server, this.data);

  final HttpServer server;
  final Uint8List data;

  /// Signature the origin currently accepts (`?t=`); a mismatch is a 403.
  String validToken = 'a';
  int failNext5xx = 0;
  int status404After = -1;
  Duration delayPerResponse = Duration.zero;
  Duration bodyStall = Duration.zero;

  final List<(int, int)> ranges = [];
  int requests = 0;
  int active = 0;
  int maxActive = 0;
  int forbidden = 0;

  static Future<FakeOrigin> start(int size) async {
    final data = Uint8List(size);
    for (var i = 0; i < size; i++) {
      data[i] = (i * 31 + (i >> 8) * 7 + 5) & 0xff;
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final origin = FakeOrigin._(server, data);
    server.listen(origin._handle);
    return origin;
  }

  Uri url([String? token]) =>
      Uri.parse('http://127.0.0.1:${server.port}/obj/film.mp4?t=${token ?? validToken}');

  Future<void> _handle(HttpRequest req) async {
    requests++;
    active++;
    if (active > maxActive) maxActive = active;
    try {
      final res = req.response;
      if (delayPerResponse > Duration.zero) await Future<void>.delayed(delayPerResponse);
      if (req.uri.queryParameters['t'] != validToken) {
        forbidden++;
        res.statusCode = 403;
        await res.close();
        return;
      }
      if (status404After >= 0 && requests > status404After) {
        res.statusCode = 404;
        await res.close();
        return;
      }
      if (failNext5xx > 0) {
        failNext5xx--;
        res.statusCode = 503;
        await res.close();
        return;
      }
      final header = req.headers.value(HttpHeaders.rangeHeader);
      var start = 0;
      var end = data.length - 1;
      var partial = false;
      final m = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(header ?? '');
      if (m != null) {
        partial = true;
        start = int.parse(m.group(1)!);
        if (m.group(2)!.isNotEmpty) end = int.parse(m.group(2)!);
        if (end >= data.length) end = data.length - 1;
        ranges.add((start, end));
      }
      res.statusCode = partial ? 206 : 200;
      if (partial) res.headers.set('content-range', 'bytes $start-$end/${data.length}');
      res.contentLength = end - start + 1;
      var pos = start;
      while (pos <= end) {
        final n = (end - pos + 1) < 64 * 1024 ? (end - pos + 1) : 64 * 1024;
        res.add(Uint8List.sublistView(data, pos, pos + n));
        pos += n;
        await res.flush();
        if (bodyStall > Duration.zero) await Future<void>.delayed(bodyStall);
      }
      await res.close();
    } catch (_) {
      // the proxy aborting a stale fetch lands here
    } finally {
      active--;
    }
  }

  Future<void> close() => server.close(force: true);
}
