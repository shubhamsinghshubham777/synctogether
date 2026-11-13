/// Named snapshot providers other subsystems register so a report can describe
/// them without `lib/feedback` importing them (sync, AV, the media player live
/// inside `RoomScreen`, not in a global). A provider returns ordered
/// label -> value lines; it must be cheap, synchronous and free of chat text.
abstract final class FeedbackProbes {
  static final Map<String, Map<String, String> Function()> _probes = {};

  /// Returns a function that unregisters it (call from `dispose`).
  static void Function() register(String name, Map<String, String> Function() read) {
    _probes[name] = read;
    return () {
      if (_probes[name] == read) _probes.remove(name);
    };
  }

  /// `name` -> its snapshot; a throwing probe is skipped, and so is one with
  /// nothing to say (a film with no subtitles has no `subs` line).
  static Map<String, Map<String, String>> snapshot() {
    final out = <String, Map<String, String>>{};
    for (final e in _probes.entries) {
      try {
        final lines = e.value();
        if (lines.isNotEmpty) out[e.key] = lines;
      } catch (_) {}
    }
    return out;
  }

  static final Map<String, String? Function()> _optional = {};

  /// A value that is **never** part of [snapshot]: it only travels when the
  /// user switches it on (the video's file name). The sheet asks for it by
  /// name through [optional].
  static void Function() registerOptional(String name, String? Function() read) {
    _optional[name] = read;
    return () {
      if (_optional[name] == read) _optional.remove(name);
    };
  }

  /// The current value of an opt-in field, or null if nothing registered it.
  static String? optional(String name) {
    try {
      return _optional[name]?.call();
    } catch (_) {
      return null;
    }
  }
}
