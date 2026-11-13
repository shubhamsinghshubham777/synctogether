import 'dart:async';

import 'package:flutter/widgets.dart';

import 'contract.dart';

/// In-memory [FeedbackService] for UI work and tests: no network, no Sentry.
class FakeFeedbackService implements FeedbackService {
  final List<BugReportRow> _rows = [];
  final _changes = <void Function()>[];
  int _n = 0;

  /// Reports passed to [submit], newest last.
  final List<BugCapture> submitted = [];

  @override
  Future<BugCapture> captureScreen(BuildContext ctx) async =>
      const BugCapture(screenRoute: '/lobby');

  @override
  Future<BugCapture> gather(BugCapture c) async =>
      c.copyWith(summary: {'app': '1.0.0 (1)', 'screen': c.screenRoute}, logsText: 'fake log');

  @override
  Future<SubmitResult> submit(
    BugCapture c, {
    required BugCategory? category,
    String? note,
    required bool includeScreenshot,
  }) async {
    submitted.add(includeScreenshot ? c : c.copyWith(clearScreenshot: true));
    final code = 'BUG-${(++_n).toString().padLeft(4, '0')}';
    _rows.insert(
      0,
      BugReportRow(
        code: code,
        category: category ?? BugCategory.other,
        title: (note == null || note.isEmpty) ? 'Bug report' : note,
        status: .received,
        createdAt: DateTime.now(),
      ),
    );
    for (final f in List.of(_changes)) {
      f();
    }
    return Sent(code);
  }

  @override
  Stream<List<BugReportRow>> watchMine() {
    late StreamController<List<BugReportRow>> ctrl;
    void push() => ctrl.add(List.unmodifiable(_rows));
    ctrl = StreamController<List<BugReportRow>>(
      onListen: () {
        _changes.add(push);
        push();
      },
      onCancel: () => _changes.remove(push),
    );
    return ctrl.stream;
  }

  @override
  Future<void> flushQueue() async {}
}
