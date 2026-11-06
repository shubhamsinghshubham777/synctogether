/// Everything a room needs to stream a shared film well, behind one object.
///
/// Owns the loopback proxy, the mpv tuning, the health monitor, the notice
/// state and the "buffer ahead" hold, so `RoomScreen` only opens, forwards a few
/// player edges and renders the notice. Any part can be absent: no proxy (the
/// toggle is off, or it failed to start) leaves a direct-URL stream with the same
/// tuning, health monitoring and notice.
// ignore_for_file: prefer_initializing_formals
library;

import 'dart:async';

import 'package:synctogether/diagnostics.dart';
import 'package:synctogether/env.dart';
import 'package:synctogether/player/stream/link_probe.dart';
import 'package:synctogether/player/stream/stream_health.dart';
import 'package:synctogether/player/stream/stream_notice.dart';
import 'package:synctogether/player/stream/stream_proxy.dart';
import 'package:synctogether/player/stream/stream_tuning.dart';
import 'package:synctogether/rooms/media_sharing_cache.dart';
import 'package:synctogether/rooms/media_sharing_service.dart';

/// The longest a member is held in "loading" for a buffer-ahead request, so one
/// slow connection can never hold a whole room for long.
const Duration kBufferAheadMaxHold = Duration(seconds: 90);

class SharedStreamSession {
  SharedStreamSession({
    required this.roomId,
    required this.fetchUrl,
    required this.cache,
    required this.device,
    required this.setOption,
    this.readOption,
    required this.mpvCacheBps,
    required this.bufferedAhead,
    required this.remaining,
    required this.onChanged,
    required this.onReadinessChanged,
    required this.onProxyFatal,
    bool Function()? proxyEnabled,
    StreamHealthConfig health = const StreamHealthConfig(),
    this.probeFn,
    DateTime Function()? now,
  }) : _proxyEnabled = proxyEnabled ?? (() => Env.streamProxyEnabled),
       _health = health,
       _now = now ?? DateTime.now {
    notice = StreamNoticeController(probe: _probe, escalate: _escalate)..addListener(onChanged);
  }

  final String roomId;
  final Future<DownloadUrlResult> Function() fetchUrl;
  final MediaSharingCache cache;
  final StreamDeviceClass device;

  /// Applies one mpv property; failures are the caller's to swallow.
  final Future<void> Function(String key, String value) setOption;

  /// Reads an mpv property back (null when unavailable); used only to verify that
  /// the tuning took effect, once per opened stream.
  final Future<String?> Function(String key)? readOption;
  final Future<double?> Function() mpvCacheBps;

  /// Seconds of media mpv already holds beyond the playhead, and how much of the
  /// film is left.
  final Duration Function() bufferedAhead;
  final Duration Function() remaining;
  final void Function() onChanged;
  final void Function() onReadinessChanged;
  final void Function(String reason) onProxyFatal;
  final Future<double?> Function(Uri url, int totalBytes, int Function()? alsoBytes)? probeFn;

  final bool Function() _proxyEnabled;
  final StreamHealthConfig _health;
  final DateTime Function() _now;

  late final StreamNoticeController notice;
  StreamProxy? proxy;
  StreamHealthMonitor? _monitor;
  DownloadUrlResult? _dl;
  DateTime? _openedAt;
  int? _bitrateBps;
  bool _escalated = false;
  bool _bufferAhead = false;
  bool _holding = false;
  DateTime? _holdStarted;
  Timer? _holdTimer;
  bool _playing = false;
  bool _buffering = false;
  bool _firstFrame = false;
  bool _disposed = false;

  /// While true the member reports "loading" to the room instead of "ready".
  bool get holdingForBuffer => _holding;

  /// (seconds ready, seconds wanted) for the buffering-ahead banner.
  (int, int) get holdProgress {
    final want = _holdTarget().inSeconds;
    final have = bufferedAhead().inSeconds;
    return (have > want ? want : have, want);
  }

  Duration _holdTarget() {
    const target = Duration(seconds: kBufferAheadTargetSecs);
    final left = remaining();
    return left > Duration.zero && left < target ? left : target;
  }

  /// Opens a session for [dl]: starts the proxy if enabled, applies the remote
  /// tuning, and returns the URL mpv should open.
  Future<Uri> start(DownloadUrlResult dl, {Duration? duration}) async {
    await _closeParts();
    _dl = dl;
    _openedAt = _now();
    _firstFrame = false;
    _escalated = false;
    _bufferAhead = false;
    notice.resetForNewFile();
    _bitrateBps = requiredBitrateBps(fileBytes: dl.fileSize, duration: duration);
    await _applyOptions();
    unawaited(_verifyOptions());
    Uri source = dl.streamUrl;
    if (_proxyEnabled()) {
      proxy = await StreamProxy.start(
        originUrl: dl.streamUrl,
        totalBytes: dl.fileSize,
        cacheKey: roomId,
        resign: () async => (await fetchUrl()).streamUrl,
        cache: cache,
        fileName: dl.fileName,
        config: streamConfigFromHints(
          chunkBytes: dl.chunkBytes,
          maxParallel: dl.maxParallel,
          urlTtl: Duration(seconds: dl.expiresInSeconds),
        ),
        bitrateBps: _bitrateBps,
        onFatal: (reason) {
          if (_disposed) return;
          trace('stream proxy gave up', category: 'media', data: {'reason': reason});
          onProxyFatal(reason);
        },
      );
      if (proxy != null) source = proxy!.localUrl;
    }
    _ensureMonitor();
    return source;
  }

  /// What to hand mpv to reopen the same film (after an error): the live proxy
  /// if there is one - it re-signs itself - else a fresh direct URL.
  Future<Uri> reopenSource() async {
    final p = proxy;
    if (p != null) return p.localUrl;
    final dl = await fetchUrl();
    _dl = dl;
    return dl.streamUrl;
  }

  /// Drops the proxy and returns a fresh direct URL: the fallback when the
  /// proxy has proven it cannot reach the origin.
  Future<Uri> fallBackToDirect() async {
    final p = proxy;
    proxy = null;
    await p?.close();
    final dl = await fetchUrl();
    _dl = dl;
    return dl.streamUrl;
  }

  /// The duration is known only after mpv opens the file; the bitrate needs it.
  void onDuration(Duration duration) {
    final dl = _dl;
    if (dl == null || duration == Duration.zero) return;
    final bps = requiredBitrateBps(fileBytes: dl.fileSize, duration: duration);
    if (bps == null || bps == _bitrateBps) return;
    _bitrateBps = bps;
    proxy?.setBitrate(bps);
    unawaited(_applyOptions());
    _ensureMonitor();
  }

  void onPlaying(bool playing) {
    _playing = playing;
    _monitor?.onPlaying(playing);
  }

  void onBuffering(bool buffering) {
    _buffering = buffering;
    _monitor?.onBuffering(buffering);
  }

  void onFirstFrame() {
    _firstFrame = true;
    _monitor?.onFirstFrame();
  }

  void _ensureMonitor() {
    final bps = _bitrateBps;
    if (_monitor != null || bps == null || _disposed) return;
    final m = StreamHealthMonitor(
      requiredBps: bps,
      config: _health,
      now: _now,
      sampler: _sample,
      onSuspect: (snapshot) => unawaited(notice.onSuspect(snapshot)),
    )..start(openedAt: _openedAt);
    _monitor = m;
    if (_firstFrame) m.onFirstFrame();
    m.onPlaying(_playing);
    m.onBuffering(_buffering);
  }

  Future<StreamSample> _sample() async {
    final p = proxy;
    if (p != null) {
      final s = p.stats;
      return StreamSample(originBytes: s.originBytes, busyMicros: s.busyMicros);
    }
    return StreamSample(mpvCacheBps: await mpvCacheBps());
  }

  Future<double?> _probe() async {
    final dl = _dl;
    if (dl == null) return null;
    final p = proxy;
    try {
      final url = p != null ? await p.freshOriginUrl() : (await fetchUrl()).streamUrl;
      final alsoBytes = p == null ? null : () => p.stats.originBytes;
      final fn = probeFn;
      return fn != null
          ? await fn(url, dl.fileSize, alsoBytes)
          : await measureLinkBps(url: url, totalBytes: dl.fileSize, alsoBytes: alsoBytes);
    } catch (e) {
      trace('link probe failed', category: 'network', data: {'error': e.runtimeType.toString()});
      return null;
    }
  }

  void _escalate() {
    if (_escalated) return;
    _escalated = true;
    proxy?.boost();
    unawaited(_applyOptions());
    trace('stream escalated silently', category: 'media', data: {'proxy': proxy != null});
  }

  /// Reads the lavf option boxes back and records whether our reconnect options
  /// stuck and media_kit's protocol whitelist survived. Once per stream; never
  /// blocks opening. Breadcrumb always; a non-fatal only when something is off,
  /// so a bundled libmpv that ignores `stream-lavf-o` shows up in the dashboard.
  Future<void> _verifyOptions() async {
    final read = readOption;
    if (read == null) return;
    try {
      final verdict = verifyLavfOptions(
        streamLavf: await read('stream-lavf-o'),
        demuxerLavf: await read('demuxer-lavf-o'),
      );
      trace(
        'stream options verified',
        category: 'media',
        data: {
          'reconnect_applied': verdict.reconnectApplied,
          'whitelist_intact': verdict.whitelistIntact,
        },
      );
      if (!verdict.reconnectApplied || !verdict.whitelistIntact) {
        reportNonFatal(
          StateError(
            'stream options not as expected: reconnect=${verdict.reconnectApplied} '
            'whitelist=${verdict.whitelistIntact}',
          ),
          StackTrace.current,
          during: 'verifying the stream tuning',
        );
      }
    } catch (_) {
      trace('stream options could not be read back', category: 'media');
    }
  }

  Future<void> _applyOptions() async {
    final options = remoteStreamOptions(
      device: device,
      bitrateBps: _bitrateBps,
      bufferAhead: _bufferAhead,
      escalated: _escalated,
    );
    for (final e in options.entries) {
      try {
        await setOption(e.key, e.value);
      } catch (err) {
        trace('stream option not applied', category: 'media', data: {'option': e.key});
        break;
      }
    }
  }

  /// "Buffer ahead": deepen the buffer and hold this member at "loading" until
  /// enough is ready (or [kBufferAheadMaxHold] passes).
  void bufferAhead() {
    if (_holding || _disposed) return;
    _bufferAhead = true;
    _holding = true;
    _holdStarted = _now();
    notice.startBufferAhead();
    proxy?.boost();
    unawaited(_applyOptions());
    trace(
      'buffer ahead requested',
      category: 'media',
      data: {'ahead_s': bufferedAhead().inSeconds, 'target_s': _holdTarget().inSeconds},
    );
    _holdTimer = Timer.periodic(const Duration(seconds: 1), (_) => _checkHold());
    onReadinessChanged();
    onChanged();
  }

  void _checkHold() {
    if (!_holding) return;
    final waited = _now().difference(_holdStarted!);
    if (bufferedAhead() >= _holdTarget() || waited >= kBufferAheadMaxHold) {
      releaseHold(reason: waited >= kBufferAheadMaxHold ? 'timeout' : 'ready');
    } else {
      onChanged(); // progress text
    }
  }

  /// "Start anyway", or the wait finished.
  void releaseHold({String reason = 'user'}) {
    if (!_holding) return;
    _holding = false;
    _holdTimer?.cancel();
    _holdTimer = null;
    _bufferAhead = false;
    _escalated = true;
    unawaited(_applyOptions());
    trace(
      'buffer ahead finished',
      category: 'media',
      data: {'reason': reason, 'ahead_s': bufferedAhead().inSeconds},
    );
    notice.dismiss();
    onReadinessChanged();
    onChanged();
  }

  Future<void> _closeParts() async {
    _monitor?.stop();
    _monitor = null;
    _holdTimer?.cancel();
    _holdTimer = null;
    _holding = false;
    final p = proxy;
    proxy = null;
    await p?.close();
  }

  /// Back to local-file defaults, for a room that moves on to a local file or
  /// YouTube.
  Future<void> reset() async {
    await _closeParts();
    _dl = null;
    notice.resetForNewFile();
    for (final e in localFileStreamOptions.entries) {
      try {
        await setOption(e.key, e.value);
      } catch (_) {
        break;
      }
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await _closeParts();
    notice.dispose();
  }
}
