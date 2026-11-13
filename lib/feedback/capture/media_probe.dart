import 'dart:async';

import 'package:media_kit/media_kit.dart';

import '../../diagnostics.dart';
import 'media_details.dart';
import 'probes.dart';

/// Describes the film that is playing to a bug report: container, codec, colour,
/// tracks, decode path and the last mpv warnings (see `media_details.dart`).
///
/// Probes are synchronous and mpv reads are not, so the mpv half is read in the
/// background whenever the media changes (tracks, video or audio parameters,
/// duration) and the report reads the last result. The live half (position,
/// playing, subtitle formats) is computed at snapshot time from [facts].
///
/// One per room: [start] on entry, the function [register] returns plus
/// [dispose] on exit. The video's name is **never** in a probe line; it is only
/// reachable through the opt-in `media.file_name` field.
class MediaProbe {
  MediaProbe({required this.player, required this.facts});

  final Player player;

  /// What the room knows right now. Cheap and synchronous.
  final MediaFacts Function() facts;

  final MpvLogBuffer log = MpvLogBuffer();
  final List<StreamSubscription<Object?>> _subs = [];
  Map<String, Map<String, String>> _mpv = const {};
  Timer? _debounce;
  bool _busy = false;
  bool _again = false;
  bool _disposed = false;
  DateTime? _lastKick;

  /// Subscribes to the player once and does a first read.
  void start() {
    _subs
      ..add(player.stream.tracks.listen((_) => _changed()))
      ..add(player.stream.videoParams.listen((_) => _changed()))
      ..add(player.stream.audioParams.listen((_) => _changed()))
      ..add(player.stream.duration.listen((_) => _changed()))
      ..add(player.stream.log.listen((l) => log.add(l.level, l.text)));
    _changed();
  }

  void _changed() {
    if (_disposed) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => unawaited(_refresh()));
  }

  Future<void> _refresh() async {
    if (_disposed) return;
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    try {
      final Object? native;
      try {
        native = player.platform;
      } on TypeError {
        // A player double (tests) or a platform with no native backend.
        _mpv = const {};
        return;
      }
      if (native is! NativePlayer) {
        _mpv = const {};
        return;
      }
      final np = native;
      _mpv = await readMpvSections((p) => np.getProperty(p));
    } catch (e, s) {
      reportNonFatal(e, s, during: 'reading media details for a bug report');
    } finally {
      _busy = false;
      if (_again && !_disposed) {
        _again = false;
        _changed();
      }
    }
  }

  /// The six report sections plus the mpv log, as of now. Never throws.
  Map<String, Map<String, String>> sections() {
    final f = facts();
    // A report opened long after the last change still gets fresh numbers.
    final now = DateTime.now();
    if (_lastKick == null || now.difference(_lastKick!) > const Duration(seconds: 5)) {
      _lastKick = now;
      _changed();
    }
    var out = mergeSections(liveSections(f), f.mode == 'youtube' ? const {} : _mpv);
    if (f.mode != 'youtube' && log.lines.isNotEmpty) {
      out['mpv'] = {'last': log.lines.reversed.take(3).join(' | ')};
    }
    return capSections(out);
  }

  /// The redacted base name, or null. Only ever offered through
  /// `FeedbackProbes.optional('media.file_name')`.
  String? get fileName {
    final f = facts();
    return f.mode == 'youtube' ? null : mediaFileName(f.nameOrUri);
  }

  /// Registers every section as its own probe so each is its own line in
  /// "what we send", and the opt-in file name. Returns the unregister.
  void Function() register() {
    final undo = [
      for (final name in kMediaSections)
        FeedbackProbes.register(name, () => sections()[name] ?? const {}),
      FeedbackProbes.registerOptional('media.file_name', () => fileName),
    ];
    return () {
      for (final u in undo) {
        u();
      }
    };
  }

  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
  }
}
