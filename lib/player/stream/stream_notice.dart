/// The state behind the gentle "connection" notice.
///
/// Three outcomes follow a suspect stream, and only one of them speaks up about
/// the viewer's connection:
///
/// * the link probe shows plenty of room: it is *our* path. Escalate silently
///   (more connections, deeper buffer) and at most show a neutral "buffering a
///   little more" note, never blaming anyone;
/// * the probe is inconclusive: escalate silently, say nothing;
/// * the probe confirms the link is below the file's bitrate: one dismissible
///   notice per file, with a way to buffer ahead.
library;

import 'package:flutter/foundation.dart';
import 'package:synctogether/diagnostics.dart';
import 'package:synctogether/player/stream/stream_health.dart';

enum StreamNotice { none, bufferingMore, connection, bufferingAhead }

class StreamNoticeController extends ChangeNotifier {
  StreamNoticeController({required this.probe, required this.escalate, this.maxNeutralPerFile = 2});

  /// Measures the link in bits per second (null: could not measure).
  final Future<double?> Function() probe;

  /// Silent help: raise the connection count and buffer target.
  final void Function() escalate;
  final int maxNeutralPerFile;

  StreamNotice _notice = StreamNotice.none;
  StreamNotice get notice => _notice;

  int? requiredBps;
  double? capacityBps;

  bool _probing = false;
  bool _connectionShown = false;
  int _neutralShown = 0;
  bool _disposed = false;

  bool get connectionShownForFile => _connectionShown;

  void _set(StreamNotice n) {
    if (_disposed || _notice == n) return;
    _notice = n;
    notifyListeners();
  }

  /// A new file: the once-per-file allowance resets.
  void resetForNewFile() {
    _connectionShown = false;
    _neutralShown = 0;
    _probing = false;
    capacityBps = null;
    _set(.none);
  }

  /// The monitor flagged the stream. Runs the probe and decides what, if
  /// anything, the viewer sees.
  Future<ProbeOutcome?> onSuspect(StreamHealthSnapshot snapshot) async {
    if (_probing || _disposed) return null;
    _probing = true;
    requiredBps = snapshot.requiredBps;
    try {
      final bps = await probe();
      if (_disposed) return null;
      capacityBps = bps;
      final outcome = classifyProbe(probeBps: bps, requiredBps: snapshot.requiredBps);
      trace(
        'stream notice decided',
        category: 'media',
        data: {
          'outcome': outcome.name,
          'probe_mbps': bps == null ? null : (bps / 1e6).round(),
          'required_mbps': (snapshot.requiredBps / 1e6).round(),
          'stalls': snapshot.stallsInWindow,
        },
      );
      switch (outcome) {
        case .ourPath:
          escalate();
          if (_neutralShown < maxNeutralPerFile && _notice == .none) {
            _neutralShown++;
            _set(.bufferingMore);
          }
        case .inconclusive:
          escalate();
        case .userLink:
          if (!_connectionShown && _notice == .none) {
            _connectionShown = true;
            _set(.connection);
          } else {
            escalate();
          }
      }
      return outcome;
    } finally {
      _probing = false;
    }
  }

  /// "Buffer ahead": the caller raises the target; this just reflects it.
  void startBufferAhead() => _set(.bufferingAhead);

  /// Dismiss whatever is showing ("Keep going", the close button, a banner
  /// timing out, or the buffer-ahead wait ending).
  void dismiss() => _set(.none);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
