import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A report waiting for the network. Screenshot and logs sit in files beside
/// the queue (prefs holds only their basenames) so the prefs blob stays small.
class QueuedReport {
  QueuedReport({
    required this.id,
    required this.category,
    required this.note,
    required this.context,
    required this.createdAt,
    this.screenshotFile,
    this.logsFile,
    this.attempts = 0,
    this.notifyWhenFixed = true,
    this.appendix,
  });

  final String id;
  final String? category;
  final String? note;
  final Map<String, Object?> context;
  final DateTime createdAt;
  final String? screenshotFile;
  final String? logsFile;
  int attempts;

  /// "Tell me when it's fixed", chosen on the success screen and sent with the
  /// report once it has a code. On by default, as the screen shows it.
  bool notifyWhenFixed;

  /// "Add more details" written before the report had a code.
  String? appendix;

  Map<String, Object?> toJson() => {
    'id': id,
    'category': category,
    'note': note,
    'context': context,
    'createdAt': createdAt.toIso8601String(),
    'screenshotFile': screenshotFile,
    'logsFile': logsFile,
    'attempts': attempts,
    'notifyWhenFixed': notifyWhenFixed,
    'appendix': appendix,
  };

  static QueuedReport fromJson(Map<String, dynamic> j) => QueuedReport(
    id: j['id'] as String,
    category: j['category'] as String?,
    note: j['note'] as String?,
    context: (j['context'] as Map).cast<String, Object?>(),
    createdAt: DateTime.parse(j['createdAt'] as String),
    screenshotFile: j['screenshotFile'] as String?,
    logsFile: j['logsFile'] as String?,
    attempts: (j['attempts'] as int?) ?? 0,
    notifyWhenFixed: (j['notifyWhenFixed'] as bool?) ?? true,
    appendix: j['appendix'] as String?,
  );
}

/// Durable offline queue: capped, deduped by id, survives restarts.
class BugReportQueue {
  BugReportQueue({Future<Directory> Function()? dir})
    : _dir =
          dir ??
          (() async =>
              Directory('${(await getApplicationSupportDirectory()).path}/feedback_queue'));

  static const _key = 'feedback.queue.v1';
  static const maxEntries = 10;

  final Future<Directory> Function() _dir;

  Future<List<QueuedReport>> load() async {
    final raw = (await SharedPreferences.getInstance()).getStringList(_key) ?? const [];
    final out = <QueuedReport>[];
    for (final s in raw) {
      try {
        out.add(QueuedReport.fromJson(jsonDecode(s) as Map<String, dynamic>));
      } catch (_) {}
    }
    return out;
  }

  Future<void> _save(List<QueuedReport> all) async => (await SharedPreferences.getInstance())
      .setStringList(_key, [for (final r in all) jsonEncode(r.toJson())]);

  /// Adds [r] (no-op if the id is already queued), writing its files; the
  /// oldest entries beyond [maxEntries] are dropped with their files.
  Future<void> add(QueuedReport r, {Uint8List? screenshot, String? logs}) async {
    final all = await load();
    if (all.any((e) => e.id == r.id)) return;
    final dir = await _dir();
    await dir.create(recursive: true);
    String? shot, log;
    if (screenshot != null) {
      shot = '${r.id}.png';
      await File('${dir.path}/$shot').writeAsBytes(screenshot);
    }
    if (logs != null && logs.isNotEmpty) {
      log = '${r.id}.txt';
      await File('${dir.path}/$log').writeAsString(logs);
    }
    all.add(
      QueuedReport(
        id: r.id,
        category: r.category,
        note: r.note,
        context: r.context,
        createdAt: r.createdAt,
        screenshotFile: shot,
        logsFile: log,
        attempts: r.attempts,
        notifyWhenFixed: r.notifyWhenFixed,
        appendix: r.appendix,
      ),
    );
    while (all.length > maxEntries) {
      await _deleteFiles(all.removeAt(0));
    }
    await _save(all);
  }

  Future<Uint8List?> screenshotOf(QueuedReport r) async => _read(r.screenshotFile);

  Future<String?> logsOf(QueuedReport r) async {
    final b = await _read(r.logsFile);
    return b == null ? null : utf8.decode(b, allowMalformed: true);
  }

  Future<Uint8List?> _read(String? name) async {
    if (name == null) return null;
    final f = File('${(await _dir()).path}/$name');
    return await f.exists() ? f.readAsBytes() : null;
  }

  Future<void> setAttempts(String id, int attempts) async {
    final all = await load();
    for (final e in all) {
      if (e.id == id) e.attempts = attempts;
    }
    await _save(all);
  }

  /// Records the notify choice on a queued report. False when [id] is not
  /// queued (it is a code, or the report already went).
  Future<bool> setNotify(String id, bool on) async {
    final all = await load();
    var found = false;
    for (final e in all) {
      if (e.id == id) {
        e.notifyWhenFixed = on;
        found = true;
      }
    }
    if (found) await _save(all);
    return found;
  }

  /// Adds [text] to a queued report's extra details. False when [id] is not
  /// queued.
  Future<bool> appendNote(String id, String text) async {
    final all = await load();
    var found = false;
    for (final e in all) {
      if (e.id == id) {
        e.appendix = e.appendix == null ? text : '${e.appendix}\n\n$text';
        found = true;
      }
    }
    if (found) await _save(all);
    return found;
  }

  Future<void> remove(String id) async {
    final all = await load();
    final gone = all.where((e) => e.id == id).toList();
    for (final g in gone) {
      await _deleteFiles(g);
    }
    await _save(all.where((e) => e.id != id).toList());
  }

  Future<void> _deleteFiles(QueuedReport r) async {
    final dir = await _dir();
    for (final n in [r.screenshotFile, r.logsFile]) {
      if (n == null) continue;
      final f = File('${dir.path}/$n');
      if (await f.exists()) await f.delete();
    }
  }
}
