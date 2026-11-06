/// A loopback HTTP range proxy between mpv and the shared-media object store.
///
/// mpv opens `http://127.0.0.1:<port>/<token>/<name>` instead of the presigned
/// URL. The proxy answers its Range requests from a sparse on-disk cache and
/// fills the holes by fetching the object in chunks over several parallel
/// connections, so throughput is no longer capped at one TCP connection's
/// window over its round trip, a seek or a rewatch is a disk read, and an
/// expired presigned URL is re-signed here without mpv ever noticing.
///
/// **Delivery only.** Every byte mpv receives is a byte the origin stored; the
/// proxy never inspects, converts or reorders a file. The one thing it adds is
/// *when* the bytes arrive.
///
/// Bounded by construction: chunks stream straight to disk (nothing is held
/// beyond a socket buffer), reads go out in 256 KiB slices behind
/// `HttpResponse.flush` backpressure, prefetch is a window ahead of the
/// readers' positions, and a fetch no reader's window covers any more - the
/// bytes before a seek - is aborted rather than finished.
// ignore_for_file: prefer_initializing_formals
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:synctogether/diagnostics.dart';
import 'package:synctogether/rooms/media_sharing_cache.dart';

/// Returns a freshly signed URL for the same object.
typedef OriginSigner = Future<Uri> Function();

const int kDefaultChunkBytes = 8 * 1024 * 1024;
const int kMinChunkBytes = 4 * 1024 * 1024;
const int kMaxChunkBytes = 32 * 1024 * 1024;
const int kDefaultMaxParallel = 4;
const int kMaxParallelCeiling = 8;

/// Adjacent prefetch chunks fetched in one request. Cost at scale is request
/// count, so steady-state prefetch rides two chunks per request; the chunk the
/// playhead is waiting on is always its own request so the first byte is not
/// held up behind its neighbour.
const int kMaxFetchSpan = 2;

/// Builds a proxy config from the server's optional `chunkBytes` / `maxParallel`
/// hints. Missing or nonsense values keep today's defaults; out-of-range ones
/// are clamped (4-32 MiB, 1-8 connections).
StreamProxyConfig streamConfigFromHints({int? chunkBytes, int? maxParallel, Duration? urlTtl}) {
  final chunk = (chunkBytes == null || chunkBytes <= 0)
      ? kDefaultChunkBytes
      : (chunkBytes.clamp(kMinChunkBytes, kMaxChunkBytes) / kMinChunkBytes).round() *
            kMinChunkBytes; // multiples of 4 MiB: the edge Worker's cache chunk
  final maxP = (maxParallel == null || maxParallel <= 0)
      ? kDefaultMaxParallel
      : maxParallel.clamp(1, kMaxParallelCeiling);
  return StreamProxyConfig(
    chunkSize: chunk,
    maxParallelism: maxP,
    initialParallelism: math.min(kDefaultMaxParallel, maxP),
    minParallelism: math.min(2, maxP),
    urlTtl: urlTtl,
  );
}

class StreamProxyConfig {
  const StreamProxyConfig({
    this.chunkSize = kDefaultChunkBytes,
    this.initialParallelism = 4,
    this.minParallelism = 2,
    this.maxParallelism = kDefaultMaxParallel,
    this.aheadSecs = 60,
    this.maxAheadBytes = 192 * 1024 * 1024,
    this.maxAttempts = 6,
    this.baseBackoff = const Duration(milliseconds: 500),
    this.maxBackoff = const Duration(seconds: 8),
    this.urlTtl,
    this.connectTimeout = const Duration(seconds: 10),
    this.adaptEvery = const Duration(seconds: 3),
  });

  final int chunkSize;
  final int initialParallelism;
  final int minParallelism;
  final int maxParallelism;

  /// Seconds of media prefetched ahead of the reader (when the bitrate is known).
  final int aheadSecs;
  final int maxAheadBytes;
  final int maxAttempts;
  final Duration baseBackoff;
  final Duration maxBackoff;

  /// How long a signed URL lives. The proxy re-signs at 90% of it so no request
  /// ever carries a URL about to lapse. Null: re-sign only on 401/403.
  final Duration? urlTtl;
  final Duration connectTimeout;
  final Duration adaptEvery;

  StreamProxyConfig copyWith({int? maxParallelism, int? initialParallelism}) => StreamProxyConfig(
    chunkSize: chunkSize,
    initialParallelism: initialParallelism ?? this.initialParallelism,
    minParallelism: minParallelism,
    maxParallelism: maxParallelism ?? this.maxParallelism,
    aheadSecs: aheadSecs,
    maxAheadBytes: maxAheadBytes,
    maxAttempts: maxAttempts,
    baseBackoff: baseBackoff,
    maxBackoff: maxBackoff,
    urlTtl: urlTtl,
    connectTimeout: connectTimeout,
    adaptEvery: adaptEvery,
  );
}

/// Counters the health monitor samples. Cumulative, so a reader differences two
/// samples; `busyMicros` is how long at least one origin fetch was in flight, so
/// `originBytes / busyMicros` is the origin's throughput *while it was being
/// asked* rather than an average diluted by idle time (the buffer was full).
class StreamProxyStats {
  const StreamProxyStats({
    required this.originBytes,
    required this.servedBytes,
    required this.cacheHitBytes,
    required this.busyMicros,
    required this.activeFetches,
    required this.parallelism,
    required this.errors,
    required this.cachedBytes,
    required this.readerPosition,
    required this.cachedAhead,
  });

  final int originBytes;
  final int servedBytes;
  final int cacheHitBytes;
  final int busyMicros;
  final int activeFetches;
  final int parallelism;
  final int errors;
  final int cachedBytes;

  /// Byte offset the newest reader is at, or null when none is connected.
  final int? readerPosition;

  /// Whole-chunk bytes already on disk from [readerPosition] onwards.
  final int cachedAhead;
}

// ---------------------------------------------------------------------------
// Pure helpers
// ---------------------------------------------------------------------------

sealed class RangeRequest {
  const RangeRequest();
}

/// No (usable) Range header: the whole object, 200.
class FullRange extends RangeRequest {
  const FullRange();
}

/// An inclusive byte range, clamped to the object, 206.
class PartialRange extends RangeRequest {
  const PartialRange(this.start, this.end);
  final int start;
  final int end;
  int get length => end - start + 1;
}

/// A well-formed range that lies outside the object, 416.
class UnsatisfiableRange extends RangeRequest {
  const UnsatisfiableRange();
}

/// Reads a single-range `Range: bytes=` header against an object of [total]
/// bytes. A malformed header, or several ranges (which mpv never sends and which
/// would need multipart replies), is ignored per RFC 9110: the whole object.
RangeRequest parseRangeHeader(String? header, int total) {
  if (header == null || total <= 0) return const FullRange();
  final m = RegExp(r'^\s*bytes\s*=\s*(\d*)\s*-\s*(\d*)\s*$').firstMatch(header);
  if (m == null) return const FullRange();
  final a = m.group(1)!;
  final b = m.group(2)!;
  if (a.isEmpty && b.isEmpty) return const FullRange();
  if (a.isEmpty) {
    // Suffix: the last n bytes.
    final n = int.tryParse(b);
    if (n == null) return const FullRange();
    if (n == 0) return const UnsatisfiableRange();
    return PartialRange(math.max(0, total - n), total - 1);
  }
  final start = int.tryParse(a);
  if (start == null) return const FullRange();
  if (start >= total) return const UnsatisfiableRange();
  if (b.isEmpty) return PartialRange(start, total - 1);
  final end = int.tryParse(b);
  if (end == null || end < start) return const FullRange();
  return PartialRange(start, math.min(end, total - 1));
}

/// Total object size out of a `Content-Range: bytes a-b/total` header.
int? totalFromContentRange(String? header) {
  if (header == null) return null;
  final m = RegExp(r'/(\d+)\s*$').firstMatch(header);
  return m == null ? null : int.tryParse(m.group(1)!);
}

/// Grows the number of parallel origin connections while it keeps paying off,
/// and backs off when it stops or the origin starts failing.
///
/// Each step it sees the origin throughput of the last window. Growth is only
/// attempted when every slot was busy (otherwise more slots would sit idle),
/// is abandoned if the previous increase bought less than 12%, and stops once
/// throughput is comfortably past what playback needs - more connections would
/// be spending the origin's capacity for nothing.
class ParallelismController {
  ParallelismController({
    required this.min,
    required this.max,
    required int initial,
    this.growCooldown = const Duration(seconds: 30),
    this.comfortFactor = 2.5,
  }) : current = initial.clamp(min, max);

  final int min;
  int max;
  final Duration growCooldown;
  final double comfortFactor;
  int current;

  int _previous = 0;
  double _previousBps = 0;
  DateTime? _frozenUntil;

  int update({
    required double bps,
    required int errors,
    required bool saturated,
    required DateTime now,
    int? requiredBps,
  }) {
    if (errors > 0) {
      _previous = current;
      _previousBps = bps;
      current = math.max(min, current - 1);
      _frozenUntil = now.add(growCooldown);
      return current;
    }
    if (!saturated) {
      _previous = current;
      _previousBps = bps;
      return current;
    }
    final frozen = _frozenUntil != null && now.isBefore(_frozenUntil!);
    if (_previous != 0 && current > _previous && bps < _previousBps * 1.12) {
      // The last increase did not help: the pipe, not the slot count, is the limit.
      current = _previous;
      _frozenUntil = now.add(growCooldown);
      _previousBps = bps;
      return current;
    }
    _previous = current;
    _previousBps = bps;
    final comfortable = requiredBps != null && bps >= requiredBps * comfortFactor;
    if (!frozen && !comfortable && current < max) current++;
    return current;
  }
}

// ---------------------------------------------------------------------------
// The proxy
// ---------------------------------------------------------------------------

class _Fetch {
  _Fetch(this.index, this.start, this.length, this.count);

  final int index;
  final int start;
  final int length;
  final int count; // chunks this one request covers
  int marked = 0; // of them already whole on disk
  int written = 0;
  bool done = false;
  bool aborted = false;
  Object? error;
  HttpClientRequest? request;
  final List<(int, Completer<void>)> _waiters = [];

  bool covers(int i) => i >= index && i < index + count;

  bool get live => !done && error == null && !aborted;

  /// Completes once [needed] bytes of this chunk are on disk (or it ended).
  Future<void> waitFor(int needed) {
    if (error != null) return Future.error(error!);
    if (done || written >= needed) return Future.value();
    final c = Completer<void>();
    _waiters.add((needed, c));
    return c.future;
  }

  void progress() {
    for (final w in _waiters.toList()) {
      if (done || written >= w.$1) {
        _waiters.remove(w);
        if (!w.$2.isCompleted) w.$2.complete();
      }
    }
  }

  void fail(Object e) {
    error ??= e;
    for (final w in _waiters) {
      if (!w.$2.isCompleted) w.$2.completeError(e);
    }
    _waiters.clear();
  }
}

class _Reader {
  _Reader(this.start, this.end) : pos = start;
  final int start;
  final int end;
  int pos;
  final int serial = _serialCounter++;
  final Completer<void> gone = Completer<void>();
  bool get cancelled => gone.isCompleted;
  static int _serialCounter = 0;
}

class _ChunkGone implements Exception {
  _ChunkGone(this.why);
  final String why;
  @override
  String toString() => 'chunk unavailable: $why';
}

class StreamProxy {
  StreamProxy._({
    required HttpServer server,
    required this.totalBytes,
    required SparseMediaEntry entry,
    required Uri origin,
    required OriginSigner resign,
    required HttpClient client,
    required this.config,
    required this.token,
    required this.fileName,
    required this.contentType,
    required this.onFatal,
    int? bitrateBps,
    DateTime Function()? now,
  }) : _server = server,
       _entry = entry,
       _origin = origin,
       _resign = resign,
       _client = client,
       _bitrateBps = bitrateBps,
       _now = now ?? DateTime.now,
       _controller = ParallelismController(
         min: config.minParallelism,
         max: config.maxParallelism,
         initial: config.initialParallelism,
       ) {
    _originIssued = _now();
  }

  /// Starts a proxy, or returns null when it cannot (no socket, no disk, origin
  /// unreachable) - the caller then plays the direct URL, exactly as before.
  static Future<StreamProxy?> start({
    required Uri originUrl,
    required int totalBytes,
    required String cacheKey,
    required OriginSigner resign,
    required MediaSharingCache cache,
    String fileName = 'video.mp4',
    StreamProxyConfig config = const StreamProxyConfig(),
    int? bitrateBps,
    void Function(String reason)? onFatal,
    HttpClient Function()? clientFactory,
    DateTime Function()? now,
  }) async {
    HttpServer? server;
    SparseMediaEntry? entry;
    HttpClient? client;
    try {
      client = (clientFactory ?? HttpClient.new)()
        ..autoUncompress = false
        ..connectionTimeout = config.connectTimeout
        ..idleTimeout = const Duration(seconds: 20)
        ..maxConnectionsPerHost = config.maxParallelism * 2;

      var total = totalBytes;
      if (total <= 0) {
        total = await _probeTotal(client, originUrl) ?? 0;
        if (total <= 0) {
          trace('stream proxy not started: object size unknown', category: 'media');
          client.close(force: true);
          return null;
        }
      }
      entry = await cache.openSparse(
        key: _stableKey(originUrl),
        totalBytes: total,
        chunkSize: config.chunkSize,
      );
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final token = _randomToken();
      final proxy = StreamProxy._(
        server: server,
        totalBytes: total,
        entry: entry,
        origin: originUrl,
        resign: resign,
        client: client,
        config: config,
        token: token,
        fileName: _safeName(fileName),
        contentType: _contentTypeFor(fileName),
        onFatal: onFatal,
        bitrateBps: bitrateBps,
        now: now,
      );
      proxy._listen();
      unawaited(cache.enforceCap(keepPath: entry.dataPath));
      trace(
        'stream proxy started',
        category: 'media',
        data: {
          'total_bytes': total,
          'cached_bytes': entry.cachedBytes,
          'chunk_bytes': config.chunkSize,
          'parallelism': config.initialParallelism,
        },
      );
      return proxy;
    } catch (e, s) {
      reportNonFatal(e, s, during: 'starting the stream proxy');
      await server?.close(force: true);
      await entry?.close();
      client?.close(force: true);
      return null;
    }
  }

  final int totalBytes;
  final StreamProxyConfig config;
  final String token;
  final String fileName;
  final String contentType;
  final void Function(String reason)? onFatal;

  final HttpServer _server;
  final SparseMediaEntry _entry;
  final OriginSigner _resign;
  final HttpClient _client;
  final DateTime Function() _now;
  final ParallelismController _controller;

  Uri _origin;
  late DateTime _originIssued;
  Future<void>? _resigning;
  int? _bitrateBps;
  bool _closed = false;
  bool _boosted = false;

  final Map<int, _Fetch> _fetches = {};
  final Map<int, DateTime> _coolDown = {};
  final List<_Reader> _readers = [];
  Timer? _adaptTimer;
  int _consecutiveFatal = 0;
  bool _reportedFailure = false;

  int _originBytes = 0;
  int _servedBytes = 0;
  int _cacheHitBytes = 0;
  int _errors = 0;
  int _windowErrors = 0;
  final Stopwatch _busy = Stopwatch();
  int _lastAdaptBytes = 0;
  int _lastAdaptBusy = 0;

  /// The URL mpv should open.
  Uri get localUrl => Uri(
    scheme: 'http',
    host: InternetAddress.loopbackIPv4.address,
    port: _server.port,
    pathSegments: [token, fileName],
  );

  /// The object's current signed URL, for a caller (the link probe) that needs
  /// to read it independently. Never log it: it carries a credential.
  Uri get originUrl => _origin;

  /// Re-signs now if the URL is near expiry, then returns it.
  Future<Uri> freshOriginUrl() async {
    await _ensureFresh();
    return _origin;
  }

  int get parallelism => _controller.current;

  bool get boosted => _boosted;

  StreamProxyStats get stats {
    final primary = _primary();
    return StreamProxyStats(
      originBytes: _originBytes,
      servedBytes: _servedBytes,
      cacheHitBytes: _cacheHitBytes,
      busyMicros: _busy.elapsedMicroseconds,
      activeFetches: _fetches.values.where((f) => f.live).length,
      parallelism: _controller.current,
      errors: _errors,
      cachedBytes: _entry.cachedBytes,
      readerPosition: primary?.pos,
      cachedAhead: primary == null ? 0 : _entry.contiguousFrom(primary.pos),
    );
  }

  /// Sets the file's average bitrate once it is known (it needs the duration,
  /// which arrives after the proxy is up).
  void setBitrate(int? bps) {
    _bitrateBps = bps;
  }

  /// "Buffer ahead" and the silent escalation both land here: a deeper prefetch
  /// window and room for more connections. Idempotent.
  void boost() {
    if (_boosted || _closed) return;
    _boosted = true;
    // Never past the server's `maxParallel`: that is the cost ceiling.
    _controller.current = math.min(_controller.max, _controller.current + 2);
    trace(
      'stream proxy boosted',
      category: 'media',
      data: {'parallelism': _controller.current, 'ahead_chunks': _aheadChunks},
    );
    _pump();
  }

  // ---- server ---------------------------------------------------------------

  void _listen() {
    _server.listen(
      (req) => unawaited(_handle(req)),
      onError: (Object e, StackTrace s) => _reportOnce(e, s, 'the stream proxy server'),
    );
    _adaptTimer = Timer.periodic(config.adaptEvery, (_) => _adapt());
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      // Only this app's player may read: the path carries a per-run secret, and
      // a Host other than loopback is a DNS-rebinding attempt from a web page.
      final host = req.headers.host;
      final segs = req.uri.pathSegments;
      if ((host != '127.0.0.1' && host != 'localhost') ||
          segs.isEmpty ||
          segs.first != token ||
          (req.method != 'GET' && req.method != 'HEAD')) {
        res.statusCode = host == '127.0.0.1' || host == 'localhost' ? 404 : 403;
        await res.close();
        return;
      }
      final range = parseRangeHeader(req.headers.value(HttpHeaders.rangeHeader), totalBytes);
      res.headers
        ..set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..set(HttpHeaders.contentTypeHeader, contentType)
        ..set(HttpHeaders.cacheControlHeader, 'no-store');
      switch (range) {
        case UnsatisfiableRange():
          res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          res.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$totalBytes');
          res.contentLength = 0;
          await res.close();
          return;
        case FullRange():
          res.statusCode = HttpStatus.ok;
          res.contentLength = totalBytes;
          if (req.method == 'HEAD') {
            await res.close();
            return;
          }
          await _stream(res, _Reader(0, totalBytes - 1));
        case PartialRange(:final start, :final end, :final length):
          res.statusCode = HttpStatus.partialContent;
          res.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$totalBytes');
          res.contentLength = length;
          if (req.method == 'HEAD') {
            await res.close();
            return;
          }
          await _stream(res, _Reader(start, end));
      }
    } catch (e, s) {
      // The client leaving mid-body (a seek closes the old connection) is the
      // normal way a request ends here. Anything else is ours to report.
      if (!_isClientGone(e)) _reportOnce(e, s, 'serving a stream proxy request');
      try {
        res.detachSocket(writeHeaders: false).then((s) => s.destroy(), onError: (_) {});
      } catch (_) {}
    }
  }

  static bool _isClientGone(Object e) =>
      e is SocketException ||
      e is HttpException ||
      e is _ChunkGone ||
      e is StateError ||
      e is TimeoutException;

  Future<void> _stream(HttpResponse res, _Reader reader) async {
    _readers.add(reader);
    unawaited(
      res.done.then((_) {}, onError: (Object _) {}).whenComplete(() {
        if (!reader.gone.isCompleted) reader.gone.complete();
        _readers.remove(reader);
        if (!_closed) _pump();
      }),
    );
    final cs = _entry.chunkSize;
    var pos = reader.start;
    try {
      while (pos <= reader.end && !reader.cancelled && !_closed) {
        final idx = pos ~/ cs;
        final chunkStart = idx * cs;
        final chunkEnd = chunkStart + _entry.chunkLength(idx) - 1;
        final stop = math.min(reader.end, chunkEnd);
        reader.pos = pos;
        _pump();
        var avail = stop;
        if (_entry.hasChunk(idx)) {
          _cacheHitBytes += stop - pos + 1;
        } else {
          final fetch = _fetchCovering(idx) ?? _startFetch(idx, 1);
          await Future.any([fetch.waitFor(pos - fetch.start + 1), reader.gone.future]);
          if (reader.cancelled) break;
          avail = fetch.done ? stop : math.min(stop, fetch.start + fetch.written - 1);
        }
        while (pos <= avail && !reader.cancelled) {
          final slice = math.min(256 * 1024, avail - pos + 1);
          final data = await _entry.read(pos, slice);
          if (data.isEmpty) throw StateError('cache read came back empty');
          res.add(data);
          pos += data.length;
          reader.pos = pos;
          _servedBytes += data.length;
          await res.flush();
        }
      }
      await res.close();
    } finally {
      if (!reader.gone.isCompleted) reader.gone.complete();
      _readers.remove(reader);
      if (!_closed) _pump();
    }
  }

  // ---- scheduling -----------------------------------------------------------

  _Reader? _primary() {
    _Reader? best;
    for (final r in _readers) {
      if (r.cancelled) continue;
      if (best == null || r.serial > best.serial) best = r;
    }
    return best;
  }

  int get _aheadChunks {
    final secs = _boosted ? config.aheadSecs * 3 : config.aheadSecs;
    final bps = _bitrateBps;
    var bytes = bps != null && bps > 0
        ? bps / 8 * secs
        : (_controller.current * 3 * config.chunkSize).toDouble();
    final cap = _boosted ? config.maxAheadBytes * 3 : config.maxAheadBytes;
    bytes = math.min(bytes, cap.toDouble());
    return math.max((bytes / config.chunkSize).ceil(), _controller.current * 2);
  }

  List<int> _wanted() {
    final out = <int>[];
    final seen = <int>{};
    final primary = _primary();
    final lastChunk = _entry.chunkCount - 1;
    final live = _readers.where((r) => !r.cancelled).toList()
      ..sort((a, b) => b.serial.compareTo(a.serial));
    for (final r in live) {
      final first = math.min(r.pos ~/ _entry.chunkSize, lastChunk);
      final window = identical(r, primary) ? _aheadChunks : 2;
      for (var i = first; i <= math.min(first + window, lastChunk); i++) {
        if (seen.add(i)) out.add(i);
      }
    }
    return out;
  }

  void _pump() {
    if (_closed) return;
    final wanted = _wanted();
    final wantedSet = wanted.toSet();
    for (final f in _fetches.values.toList()) {
      if (f.live && !wantedSet.any(f.covers)) _abort(f);
    }
    var active = _fetches.values.where((f) => f.live).length;
    final now = _now();
    final primary = _primary();
    final demandIdx = primary == null ? -1 : primary.pos ~/ _entry.chunkSize;
    for (final idx in wanted) {
      if (active >= _controller.current) break;
      if (_entry.hasChunk(idx) || _fetchCovering(idx) != null) continue;
      final cool = _coolDown[idx];
      if (cool != null && now.isBefore(cool)) continue;
      var count = 1;
      if (idx != demandIdx) {
        while (count < kMaxFetchSpan &&
            idx + count < _entry.chunkCount &&
            wantedSet.contains(idx + count) &&
            !_entry.hasChunk(idx + count) &&
            _fetchCovering(idx + count) == null) {
          count++;
        }
      }
      _startFetch(idx, count);
      active++;
    }
  }

  void _abort(_Fetch f) {
    f.aborted = true;
    try {
      f.request?.abort();
    } catch (_) {}
    f.fail(_ChunkGone('no longer wanted'));
    _fetches.remove(f.index);
    _endBusyIfIdle();
  }

  _Fetch? _fetchCovering(int idx) {
    for (final f in _fetches.values) {
      if (f.covers(idx)) return f;
    }
    return null;
  }

  _Fetch _startFetch(int idx, int count) {
    final start = idx * _entry.chunkSize;
    final end = math.min(totalBytes, (idx + count) * _entry.chunkSize);
    final f = _Fetch(idx, start, end - start, count);
    _fetches[idx] = f;
    if (!_busy.isRunning) _busy.start();
    unawaited(_run(f));
    return f;
  }

  void _endBusyIfIdle() {
    if (_busy.isRunning && !_fetches.values.any((f) => f.live)) _busy.stop();
  }

  // ---- origin ---------------------------------------------------------------

  Future<void> _ensureFresh() async {
    final ttl = config.urlTtl;
    if (ttl == null) return;
    if (_now().difference(_originIssued) < ttl * 0.9) return;
    try {
      await _resignNow('proactive');
    } catch (_) {
      // The old URL may still work for a while; a 403 will force the issue.
    }
  }

  Future<void> _resignNow(String reason) {
    return _resigning ??= () async {
      try {
        final fresh = await _resign();
        _origin = fresh;
        _originIssued = _now();
        trace('stream url re-signed', category: 'media', data: {'reason': reason});
      } finally {
        _resigning = null;
      }
    }();
  }

  Future<void> _run(_Fetch f) async {
    var attempt = 0;
    var resigns = 0;
    try {
      while (!f.aborted && !_closed) {
        try {
          await _ensureFresh();
          final from = f.start + f.written;
          final to = f.start + f.length - 1;
          final used = _origin;
          final req = await _client.getUrl(used);
          f.request = req;
          req.headers
            ..set(HttpHeaders.rangeHeader, 'bytes=$from-$to')
            ..set(HttpHeaders.acceptEncodingHeader, 'identity');
          final res = await req.close();
          final code = res.statusCode;
          if (code == HttpStatus.unauthorized || code == HttpStatus.forbidden) {
            await res.drain<void>().catchError((Object _) {});
            // Another fetch may already have re-signed while this one was in
            // flight; asking again would only cost a download-url call.
            if (!identical(used, _origin)) continue;
            if (++resigns > 3) throw _ChunkGone('origin keeps refusing the signature ($code)');
            await _resignNow('http $code');
            continue;
          }
          if (code == HttpStatus.notFound || code == HttpStatus.gone) {
            await res.drain<void>().catchError((Object _) {});
            throw _ChunkGone('the object is gone ($code)');
          }
          if (code == HttpStatus.requestedRangeNotSatisfiable) {
            await res.drain<void>().catchError((Object _) {});
            throw _ChunkGone('the object changed size');
          }
          if (code >= 500 || code == HttpStatus.tooManyRequests) {
            await res.drain<void>().catchError((Object _) {});
            throw HttpException('origin answered $code');
          }
          if (code != HttpStatus.partialContent && code != HttpStatus.ok) {
            await res.drain<void>().catchError((Object _) {});
            throw _ChunkGone('unexpected origin status $code');
          }
          if (code == HttpStatus.partialContent) {
            final t = totalFromContentRange(res.headers.value(HttpHeaders.contentRangeHeader));
            if (t != null && t != totalBytes) throw _ChunkGone('the object changed size');
          } else if (from != 0) {
            // A 200 to a ranged request is the whole object from byte 0; taking
            // it mid-chunk would write the wrong bytes.
            await res.drain<void>().catchError((Object _) {});
            throw _ChunkGone('origin ignores ranges');
          }
          await for (final data in res) {
            if (f.aborted || _closed) break;
            final room = f.length - f.written;
            if (room <= 0) break;
            final bytes = data is Uint8List ? data : Uint8List.fromList(data);
            final take = bytes.length > room ? Uint8List.sublistView(bytes, 0, room) : bytes;
            await _entry.write(f.start + f.written, take);
            f.written += take.length;
            _originBytes += take.length;
            await _markWholeChunks(f);
            f.progress();
            attempt = 0;
            if (f.written >= f.length) break;
          }
          if (f.aborted || _closed) return;
          if (f.written >= f.length) {
            await _markWholeChunks(f);
            f.done = true;
            f.progress();
            _consecutiveFatal = 0;
            _fetches.remove(f.index);
            _endBusyIfIdle();
            _pump();
            return;
          }
          throw const HttpException('origin closed the connection early');
        } on _ChunkGone {
          rethrow;
        } on FileSystemException {
          rethrow;
        } catch (e) {
          if (f.aborted || _closed) return;
          _errors++;
          _windowErrors++;
          if (++attempt >= config.maxAttempts) rethrow;
          final backoff = Duration(
            milliseconds: math.min(
              config.maxBackoff.inMilliseconds,
              config.baseBackoff.inMilliseconds * (1 << (attempt - 1)),
            ),
          );
          trace(
            'origin fetch retrying',
            category: 'network',
            data: {
              'chunk': f.index,
              'attempt': attempt,
              'kind': e is SocketException
                  ? 'socket'
                  : e is TimeoutException
                  ? 'timeout'
                  : e is HttpException
                  ? 'http'
                  : e.runtimeType.toString(),
              'backoff_ms': backoff.inMilliseconds,
            },
          );
          await Future<void>.delayed(backoff);
        }
      }
    } catch (e, s) {
      if (f.aborted || _closed) return;
      f.fail(e);
      _fetches.remove(f.index);
      _coolDown[f.index] = _now().add(const Duration(seconds: 5));
      _endBusyIfIdle();
      _consecutiveFatal++;
      if (e is! _ChunkGone) _reportOnce(e, s, 'fetching a stream chunk');
      trace(
        'stream chunk failed for good',
        category: 'media',
        data: {'chunk': f.index, 'reason': e is _ChunkGone ? e.why : e.runtimeType.toString()},
      );
      if (_consecutiveFatal >= 3) onFatal?.call(e is _ChunkGone ? e.why : 'origin unreachable');
    } finally {
      if (!f.done && f.error == null && !f.aborted && !_closed) {
        _fetches.remove(f.index);
      }
    }
  }

  Future<void> _markWholeChunks(_Fetch f) async {
    while (f.marked < f.count) {
      final k = f.index + f.marked;
      final chunkEnd = math.min(f.start + f.length, (k + 1) * _entry.chunkSize);
      if (f.start + f.written < chunkEnd) break;
      await _entry.markChunk(k);
      f.marked++;
    }
  }

  void _adapt() {
    if (_closed) return;
    final busy = _busy.elapsedMicroseconds;
    final dBusy = busy - _lastAdaptBusy;
    final dBytes = _originBytes - _lastAdaptBytes;
    _lastAdaptBusy = busy;
    _lastAdaptBytes = _originBytes;
    final active = _fetches.values.where((f) => f.live).length;
    if (dBusy > 500000) {
      final bps = dBytes * 8 / (dBusy / 1e6);
      final saturated = active >= _controller.current;
      final before = _controller.current;
      _controller.update(
        bps: bps,
        errors: _windowErrors,
        saturated: saturated,
        now: _now(),
        requiredBps: _bitrateBps,
      );
      if (_controller.current != before) {
        trace(
          'stream parallelism changed',
          category: 'network',
          data: {'from': before, 'to': _controller.current, 'mbps': (bps / 1e6).round()},
        );
      }
    }
    _windowErrors = 0;
    unawaited(_entry.persist());
    _pump();
  }

  void _reportOnce(Object e, StackTrace s, String during) {
    if (_reportedFailure) return;
    _reportedFailure = true;
    reportNonFatal(e, s, during: during);
  }

  // ---- lifecycle ------------------------------------------------------------

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _adaptTimer?.cancel();
    for (final f in _fetches.values.toList()) {
      f.aborted = true;
      try {
        f.request?.abort();
      } catch (_) {}
      f.fail(_ChunkGone('proxy closed'));
    }
    _fetches.clear();
    for (final r in _readers.toList()) {
      if (!r.gone.isCompleted) r.gone.complete();
    }
    try {
      await _server.close(force: true);
    } catch (_) {}
    _client.close(force: true);
    await _entry.close();
    trace(
      'stream proxy closed',
      category: 'media',
      data: {
        'origin_bytes': _originBytes,
        'served_bytes': _servedBytes,
        'cache_hit_bytes': _cacheHitBytes,
        'errors': _errors,
      },
    );
  }

  // ---- small utilities ------------------------------------------------------

  static Future<int?> _probeTotal(HttpClient client, Uri url) async {
    try {
      final req = await client.getUrl(url);
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
      final res = await req.close();
      await res.drain<void>();
      if (res.statusCode == HttpStatus.partialContent) {
        return totalFromContentRange(res.headers.value(HttpHeaders.contentRangeHeader));
      }
    } catch (_) {}
    return null;
  }

  /// Identity of the object, stable across re-signs: the URL's path, never its
  /// query (that is where the credential lives).
  static String _stableKey(Uri url) => '${url.host}${url.path}';

  static String _randomToken() {
    final rng = math.Random.secure();
    return List.generate(16, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  static String _safeName(String name) {
    final dot = name.lastIndexOf('.');
    final ext = dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
    return RegExp(r'^[a-z0-9]{1,5}$').hasMatch(ext) ? 'video.$ext' : 'video';
  }

  static String _contentTypeFor(String name) {
    final dot = name.lastIndexOf('.');
    final ext = dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
    return switch (ext) {
      'mp4' || 'm4v' => 'video/mp4',
      'mkv' => 'video/x-matroska',
      'webm' => 'video/webm',
      'mov' => 'video/quicktime',
      'avi' => 'video/x-msvideo',
      _ => 'application/octet-stream',
    };
  }
}
