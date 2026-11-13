import 'redact.dart';

/// The last [capacity] `trace` steps, kept in memory so a bug report can attach
/// them as logs.txt. Sentry's own breadcrumb buffer cannot be read back, and a
/// report must still carry a trail when Sentry is off (no DSN).
///
/// Fed from `trace` and `reportNonFatal` in lib/diagnostics.dart. Everything is
/// redacted when rendered, never stored raw twice.
abstract final class BreadcrumbLog {
  static const capacity = 100;
  static final List<_Crumb> _crumbs = [];

  static void record(String message, {String? category, Map<String, dynamic>? data, DateTime? at}) {
    _crumbs.add(_Crumb(at ?? DateTime.now(), category ?? '-', message, data));
    if (_crumbs.length > capacity) _crumbs.removeRange(0, _crumbs.length - capacity);
  }

  static int get length => _crumbs.length;

  static void clear() => _crumbs.clear();

  /// One redacted line per step, oldest first. Identical steps in a row (a
  /// report opened three times) collapse into one line with a count.
  static String render() {
    final lines = <String>[];
    String? previous;
    var repeats = 0;
    void flush() {
      final line = previous;
      if (line == null) return;
      lines.add(repeats > 1 ? '$line (x$repeats)' : line);
    }

    for (final c in _crumbs) {
      final line = c.line();
      if (c.sameStepAs(previous)) {
        repeats++;
        continue;
      }
      flush();
      previous = line;
      repeats = 1;
    }
    flush();
    return lines.join('\n');
  }

  /// Last [n] `category.message` labels, newest last, for the summary preview.
  /// Our own [skipCategories] steps (the report being opened) are noise in a
  /// preview of what *led up to* the problem, and a run of the same step shows once.
  static List<String> lastLabels(int n, {Set<String> skipCategories = const {'feedback'}}) {
    final labels = <String>[];
    for (final c in _crumbs) {
      if (skipCategories.contains(c.category)) continue;
      final label = redactText('${c.category}.${c.message}');
      if (labels.isNotEmpty && labels.last == label) continue;
      labels.add(label);
    }
    return labels.length <= n ? labels : labels.sublist(labels.length - n);
  }
}

class _Crumb {
  _Crumb(this.at, this.category, this.message, this.data);
  final DateTime at;
  final String category;
  final String message;
  final Map<String, dynamic>? data;

  /// Whether [line] (a rendered crumb) is this same step, ignoring the time.
  bool sameStepAs(String? line) => line != null && line.substring(13) == this.line().substring(13);

  String line() {
    final t = at.toUtc().toIso8601String().substring(11, 23);
    final d = data == null || data!.isEmpty ? '' : ' ${redactValue(data)}';
    return '$t [$category] ${redactText(message)}$d';
  }
}
