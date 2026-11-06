/// Is a shared-media stream actually struggling, and is it our fault?
///
/// The decision functions are pure over plain values so the thresholds can be
/// tested without a player; [StreamHealthMonitor] is the thin timer-driven shell
/// that feeds them from mpv and the proxy's counters.
///
/// The bias is deliberate: **silence is the default.** A notice needs sustained
/// evidence (two stalls inside a minute, or one long one) AND a measured
/// throughput under 0.9x what the file needs AND - checked separately - a link
/// probe that agrees the connection, not our delivery path, is the limit.
library;

import 'dart:async';

import 'package:synctogether/diagnostics.dart';

class StreamHealthConfig {
  const StreamHealthConfig({
    this.stallWindow = const Duration(seconds: 60),
    this.stallsToFlag = 2,
    this.longStall = const Duration(seconds: 8),
    this.shortfallFactor = 0.9,
    this.ourPathFactor = 1.3,
    this.sampleEvery = const Duration(seconds: 1),
    this.throughputWindow = 10,
    this.cooldown = const Duration(seconds: 90),
  });

  final Duration stallWindow;
  final int stallsToFlag;
  final Duration longStall;

  /// Measured throughput must be under this fraction of the required bitrate.
  final double shortfallFactor;

  /// A probe at or above this multiple of the required bitrate clears the user's link.
  final double ourPathFactor;
  final Duration sampleEvery;

  /// Samples in the rolling throughput average.
  final int throughputWindow;

  /// Quiet period after a verdict, whatever the outcome.
  final Duration cooldown;
}

class Stall {
  const Stall(this.start, this.end);
  final DateTime start;
  final DateTime end;
  Duration get length => end.difference(start);
}

enum StreamVerdict { healthy, suspect }

/// Stalls are only evidence when playback was actually trying to run, which the
/// caller guarantees; this applies the thresholds.
StreamVerdict evaluateStreamHealth({
  required List<Stall> stalls,
  required DateTime now,
  DateTime? ongoingStallStart,
  required double? measuredBps,
  required int? requiredBps,
  StreamHealthConfig config = const StreamHealthConfig(),
}) {
  if (requiredBps == null || requiredBps <= 0 || measuredBps == null) return .healthy;
  if (measuredBps >= requiredBps * config.shortfallFactor) return .healthy;
  final recent = stalls.where((s) => now.difference(s.end) <= config.stallWindow).length;
  final ongoing = ongoingStallStart == null ? Duration.zero : now.difference(ongoingStallStart);
  final ongoingCounts = ongoing > Duration.zero ? 1 : 0;
  final longest = [
    ...stalls.where((s) => now.difference(s.end) <= config.stallWindow).map((s) => s.length),
    ongoing,
  ].fold(Duration.zero, (a, b) => a > b ? a : b);
  final sustained = recent + ongoingCounts >= config.stallsToFlag || longest > config.longStall;
  return sustained ? .suspect : .healthy;
}

enum ProbeOutcome {
  /// The link has room to spare: the shortfall is in our delivery path.
  ourPath,

  /// Between "fine" and "short": do not blame anyone, just help quietly.
  inconclusive,

  /// The link really is below what the file needs.
  userLink,
}

ProbeOutcome classifyProbe({
  required double? probeBps,
  required int requiredBps,
  StreamHealthConfig config = const StreamHealthConfig(),
}) {
  if (probeBps == null) return .inconclusive;
  if (probeBps >= requiredBps * config.ourPathFactor) return .ourPath;
  if (probeBps < requiredBps) return .userLink;
  return .inconclusive;
}

/// "about 38 Mbps". Never a raw figure to the decimal.
String formatMbps(num bps) {
  final mbps = bps / 1e6;
  if (mbps < 1) return 'under 1 Mbps';
  return 'about ${mbps.round()} Mbps';
}

/// One reading of the world, taken every [StreamHealthConfig.sampleEvery].
class StreamSample {
  const StreamSample({this.originBytes, this.busyMicros, this.mpvCacheBps});

  /// The proxy's cumulative origin bytes and busy time (null without a proxy).
  final int? originBytes;
  final int? busyMicros;

  /// mpv's own `cache-speed` in bits per second (the no-proxy fallback).
  final double? mpvCacheBps;
}

class StreamHealthSnapshot {
  const StreamHealthSnapshot({
    required this.requiredBps,
    required this.measuredBps,
    required this.stallsInWindow,
    required this.longestStall,
  });

  final int requiredBps;
  final double? measuredBps;
  final int stallsInWindow;
  final Duration longestStall;
}

class StreamHealthMonitor {
  StreamHealthMonitor({
    required this.requiredBps,
    required this.sampler,
    required this.onSuspect,
    this.config = const StreamHealthConfig(),
    DateTime Function()? now,
    void Function(String, Map<String, dynamic>)? log,
  }) : _now = now ?? DateTime.now,
       _log = log ?? ((m, d) => trace(m, category: 'media', data: d));

  /// The file's average bitrate: size * 8 / duration.
  final int requiredBps;
  final Future<StreamSample> Function() sampler;
  final void Function(StreamHealthSnapshot) onSuspect;
  final StreamHealthConfig config;
  final DateTime Function() _now;
  final void Function(String, Map<String, dynamic>) _log;

  Timer? _timer;
  DateTime? _opened;
  bool _firstFrame = false;
  bool _playing = false;
  bool _buffering = false;
  DateTime? _stallStart;
  final List<Stall> _stalls = [];
  final List<double> _bpsWindow = [];
  StreamSample? _last;
  DateTime? _mutedUntil;

  /// Time to first frame in ms, once known.
  int? firstFrameMs;
  int stallCount = 0;
  Duration stallTotal = Duration.zero;

  double? get measuredBps {
    if (_bpsWindow.isEmpty) return null;
    return _bpsWindow.reduce((a, b) => a + b) / _bpsWindow.length;
  }

  void start({DateTime? openedAt}) {
    _opened ??= openedAt ?? _now();
    _timer ??= Timer.periodic(config.sampleEvery, (_) => unawaited(_tick()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _endStall();
  }

  void onFirstFrame() {
    if (_firstFrame) return;
    _firstFrame = true;
    final opened = _opened;
    if (opened != null) {
      firstFrameMs = _now().difference(opened).inMilliseconds;
      _log('stream first frame', {
        'ms': firstFrameMs!,
        'required_mbps': (requiredBps / 1e6).round(),
      });
    }
  }

  void onPlaying(bool playing) {
    _playing = playing;
    if (!playing) _endStall();
    if (playing && _buffering) _beginStall();
  }

  void onBuffering(bool buffering) {
    _buffering = buffering;
    if (buffering) {
      _beginStall();
    } else {
      _endStall();
    }
  }

  /// Marks the verdict handled; the monitor stays quiet for the cooldown.
  void mute() => _mutedUntil = _now().add(config.cooldown);

  void _beginStall() {
    // Initial buffering and a paused player are not stalls.
    if (!_firstFrame || !_playing || _stallStart != null) return;
    _stallStart = _now();
    _log('stream stall started', {
      'stalls': stallCount,
      'mbps': ((measuredBps ?? 0) / 1e6).round(),
    });
  }

  void _endStall() {
    final start = _stallStart;
    if (start == null) return;
    _stallStart = null;
    final stall = Stall(start, _now());
    _stalls.add(stall);
    stallCount++;
    stallTotal += stall.length;
    _stalls.removeWhere((s) => _now().difference(s.end) > config.stallWindow * 2);
    _log('stream stall ended', {'ms': stall.length.inMilliseconds, 'stalls': stallCount});
  }

  Future<void> _tick() async {
    StreamSample sample;
    try {
      sample = await sampler();
    } catch (_) {
      return;
    }
    final last = _last;
    _last = sample;
    if (last != null) {
      double? bps;
      if (sample.originBytes != null &&
          last.originBytes != null &&
          sample.busyMicros != null &&
          last.busyMicros != null) {
        final dBusy = sample.busyMicros! - last.busyMicros!;
        // Idle origin means the buffer was full: no information about the link.
        if (dBusy > 200000) {
          bps = (sample.originBytes! - last.originBytes!) * 8 / (dBusy / 1e6);
        }
      } else if (sample.mpvCacheBps != null) {
        bps = sample.mpvCacheBps;
      }
      if (bps != null) {
        _bpsWindow.add(bps);
        if (_bpsWindow.length > config.throughputWindow) _bpsWindow.removeAt(0);
      }
    }
    final now = _now();
    if (_mutedUntil != null && now.isBefore(_mutedUntil!)) return;
    final verdict = evaluateStreamHealth(
      stalls: _stalls,
      now: now,
      ongoingStallStart: _stallStart,
      measuredBps: measuredBps,
      requiredBps: requiredBps,
      config: config,
    );
    if (verdict == .suspect) {
      mute();
      final recent = _stalls.where((s) => now.difference(s.end) <= config.stallWindow);
      final longest = [
        ...recent.map((s) => s.length),
        if (_stallStart != null) now.difference(_stallStart!),
      ].fold(Duration.zero, (a, b) => a > b ? a : b);
      _log('stream looks unhealthy', {
        'stalls_60s': recent.length + (_stallStart == null ? 0 : 1),
        'longest_ms': longest.inMilliseconds,
        'measured_mbps': ((measuredBps ?? 0) / 1e6).round(),
        'required_mbps': (requiredBps / 1e6).round(),
      });
      onSuspect(
        StreamHealthSnapshot(
          requiredBps: requiredBps,
          measuredBps: measuredBps,
          stallsInWindow: recent.length + (_stallStart == null ? 0 : 1),
          longestStall: longest,
        ),
      );
    }
  }
}
