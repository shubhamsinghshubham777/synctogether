/// A short, independent measurement of what the viewer's link can carry.
///
/// Run only after stalls *and* a throughput shortfall, to answer one question
/// before anyone is told anything: is it their connection, or is it us? Several
/// ranged reads of the same object, spread across it, run in parallel for a few
/// seconds; the sum of their bytes over the time they were receiving is the
/// capacity. Nothing here is written to the cache or played, and the only host
/// it talks to is the one already serving the film.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:synctogether/diagnostics.dart';

/// Returns bits per second, or null when the probe could not measure (too
/// short, no connection). [alsoBytes] reports other traffic on the same link
/// (the proxy's own fetches, still running) so it is counted, not mistaken for
/// spare capacity.
Future<double?> measureLinkBps({
  required Uri url,
  required int totalBytes,
  int connections = 4,
  Duration window = const Duration(seconds: 4),
  int maxBytesPerConnection = 8 * 1024 * 1024,
  int Function()? alsoBytes,
  HttpClient Function()? clientFactory,
}) async {
  if (totalBytes <= 0) return null;
  final client = (clientFactory ?? HttpClient.new)()
    ..autoUncompress = false
    ..connectionTimeout = const Duration(seconds: 5);
  var received = 0;
  final alsoStart = alsoBytes?.call() ?? 0;
  DateTime? firstByte;
  DateTime? lastByte;
  final deadline = DateTime.now().add(window);
  try {
    final span = math.max(1, totalBytes ~/ (connections + 1));
    await Future.wait([
      for (var i = 0; i < connections; i++)
        () async {
          final from = math.min(totalBytes - 1, span * (i + 1));
          final to = math.min(totalBytes - 1, from + maxBytesPerConnection - 1);
          try {
            final req = await client.getUrl(url);
            req.headers
              ..set(HttpHeaders.rangeHeader, 'bytes=$from-$to')
              ..set(HttpHeaders.acceptEncodingHeader, 'identity');
            final res = await req.close();
            if (res.statusCode != HttpStatus.partialContent && res.statusCode != HttpStatus.ok) {
              await res.drain<void>().catchError((Object _) {});
              return;
            }
            await for (final data in res) {
              final now = DateTime.now();
              firstByte ??= now;
              lastByte = now;
              received += data.length;
              if (now.isAfter(deadline)) {
                req.abort();
                break;
              }
            }
          } catch (_) {
            // One connection failing just narrows the sample.
          }
        }(),
    ]).timeout(window + const Duration(seconds: 4), onTimeout: () => const []);
  } finally {
    client.close(force: true);
  }
  final first = firstByte;
  final last = lastByte;
  if (first == null || last == null) return null;
  final secs = last.difference(first).inMilliseconds / 1000;
  if (secs < 1) return null;
  final extra = (alsoBytes?.call() ?? 0) - alsoStart;
  final bps = (received + math.max(0, extra)) * 8 / secs;
  trace(
    'link probe finished',
    category: 'network',
    data: {'mbps': (bps / 1e6).round(), 'seconds': secs.round(), 'connections': connections},
  );
  return bps;
}
