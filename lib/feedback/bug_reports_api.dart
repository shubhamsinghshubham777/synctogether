import 'package:supabase_flutter/supabase_flutter.dart';

import 'contract.dart';

/// The server half of a report, narrowed to what [RealFeedbackService] needs so
/// tests run without Supabase. Contract with the W2 migration:
///  - `submit_bug_report(p_category, p_note, p_context, p_sentry_event_id)`
///    returns `table(code text)`; SQLSTATE 54000 `rate_limited`
///    (30 s per user), 22023 invalid category, `note_too_long` (> 2000),
///    `context_too_large` (> 16 KB), 28000 not authenticated.
///  - `my_bug_reports()` returns `(code, category, title, status, fixed_in, created_at,
///    reason, duplicate_of_code, duplicate_of_title, duplicate_of_status, same_count,
///    notify_when_fixed, closed_at)`.
///  - `set_bug_notify_when_fixed(p_code, p_on)` and `append_bug_note(p_code, p_text)`
///    are owner-only; `append_bug_note` raises `note_too_long` (> 2000 combined).
abstract class BugReportsApi {
  Future<String> submit({
    required String? category,
    required String? note,
    required Map<String, Object?> context,
    required String? sentryEventId,
  });

  Future<List<BugReportRow>> mine();

  Future<void> setNotifyWhenFixed(String code, bool on);

  Future<void> appendNote(String code, String text);

  bool get signedIn;
}

/// The server refused the payload itself (bad category, note or context too
/// large). Retrying the same bytes can never work, so it is never queued.
class BugReportRejected implements Exception {
  const BugReportRejected(this.reason);
  final String reason;
  @override
  String toString() => 'BugReportRejected($reason)';
}

/// Thrown by an API when the server says slow down.
class BugReportRateLimited implements Exception {
  const BugReportRateLimited([this.retryIn = const Duration(seconds: 30)]);
  final Duration retryIn;
}

class SupabaseBugReportsApi implements BugReportsApi {
  SupabaseClient get _client => Supabase.instance.client;

  @override
  bool get signedIn => _client.auth.currentSession != null;

  @override
  Future<String> submit({
    required String? category,
    required String? note,
    required Map<String, Object?> context,
    required String? sentryEventId,
  }) async {
    try {
      final res = await _client.rpc(
        'submit_bug_report',
        params: {
          'p_category': category,
          'p_note': note,
          'p_context': context,
          'p_sentry_event_id': sentryEventId,
        },
      );
      final row = res is List ? res.first : res;
      return (row is Map ? row['code'] : row) as String;
    } on PostgrestException catch (e) {
      if (e.code == '54000' || e.message.contains('rate_limited')) {
        throw const BugReportRateLimited();
      }
      if (e.code == '22023' ||
          e.message.contains('note_too_long') ||
          e.message.contains('context_too_large')) {
        throw BugReportRejected(e.message);
      }
      rethrow;
    }
  }

  @override
  Future<List<BugReportRow>> mine() async {
    final res = await _client.rpc('my_bug_reports') as List;
    return [for (final r in res) rowFromJson((r as Map).cast<String, dynamic>())];
  }

  @override
  Future<void> setNotifyWhenFixed(String code, bool on) async {
    await _client.rpc('set_bug_notify_when_fixed', params: {'p_code': code, 'p_on': on});
  }

  @override
  Future<void> appendNote(String code, String text) async {
    try {
      await _client.rpc('append_bug_note', params: {'p_code': code, 'p_text': text});
    } on PostgrestException catch (e) {
      if (e.message.contains('note_too_long') || e.message.contains('empty_note')) {
        throw BugReportRejected(e.message);
      }
      rethrow;
    }
  }
}

BugCategory categoryFromName(String? name) =>
    BugCategory.values.firstWhere((c) => c.name == name, orElse: () => .other);

String categoryTitle(BugCategory c) => switch (c) {
  .video => 'Video problem',
  .sound => 'Sound problem',
  .sync => 'Sync problem',
  .chat => 'Chat problem',
  .camera => 'Camera problem',
  .other => 'Something else',
};

/// A status the server sent, as the app knows it. Anything unknown (a state a
/// newer server adds) falls back to `received`, which says the least.
BugStatus statusFromName(Object? name) => switch (name) {
  'looking' => .looking,
  'fixed' => .fixed,
  'wontfix' => .wontfix,
  'duplicate' => .duplicate,
  _ => .received,
};

BugReportRow rowFromJson(Map<String, dynamic> j) {
  final category = categoryFromName(j['category'] as String?);
  final note = ((j['title'] ?? j['note']) as String?)?.trim() ?? '';
  final firstLine = note.split('\n').first;
  final originalCode = j['duplicate_of_code'] as String?;
  final status = statusFromName(j['status']);
  return BugReportRow(
    code: j['code'] as String,
    category: category,
    title: firstLine.isEmpty
        ? categoryTitle(category)
        : (firstLine.length > 48 ? '${firstLine.substring(0, 47)}…' : firstLine),
    status: status,
    fixedIn: j['fixed_in'] as String?,
    createdAt: DateTime.parse(j['created_at'] as String),
    reason: (j['reason'] as String?)?.trim(),
    // A duplicate with no readable original still has to say what it is, so the
    // link is only built when the server sent one.
    duplicateOf: originalCode == null
        ? null
        : OriginalRef(
            code: originalCode,
            title: (j['duplicate_of_title'] as String?) ?? 'Bug report',
            status: statusFromName(j['duplicate_of_status']),
          ),
    sameCount: (j['same_count'] as num?)?.toInt() ?? 0,
    notifyWhenFixed: j['notify_when_fixed'] as bool? ?? false,
    closedAt: DateTime.tryParse((j['closed_at'] as String?) ?? ''),
  );
}
