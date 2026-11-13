import 'package:flutter/material.dart';

import '../pairing/pair_page.dart';
import '../ui/buttons.dart';
import '../ui/glass.dart';
import '../ui/loader.dart';
import '../ui/pt_theme.dart';
import 'bug_report.dart';
import 'contract.dart';
import 'feedback_services.dart';
import 'reports_screen.dart';

/// One report's page, for the two states that have something to say: a closed
/// report (the reason in full, and a way back) and a duplicate (the original it
/// follows, where that stands). Board 84.
class ReportDetailScreen extends StatelessWidget {
  const ReportDetailScreen({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context) => PairPage(
    title: code,
    children: [ReportDetailBody(code: code)],
  );
}

/// The page body apart from its frame, so it can be tested alone.
class ReportDetailBody extends StatelessWidget {
  const ReportDetailBody({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BugReportRow>>(
      stream: FeedbackServices.instance.watchMine(),
      builder: (context, snap) {
        final rows = snap.data;
        if (rows == null) {
          return const Padding(
            padding: EdgeInsets.only(top: 48),
            child: Center(child: PTLoader()),
          );
        }
        final row = rows.where((r) => r.code == code).firstOrNull;
        if (row == null) {
          return Padding(
            padding: const EdgeInsets.only(top: 32),
            child: Text(
              "Hmm, we can't find that report. It may be on another account.",
              style: PTText.body.copyWith(color: PTColors.fgSoft, height: 1.5),
            ),
          );
        }
        return switch (row.status) {
          BugStatus.wontfix => _ClosedDetail(row: row),
          BugStatus.duplicate when row.duplicateOf != null => _DuplicateDetail(row: row),
          _ => _Header(row: row, pill: reportPill(row)),
        };
      },
    );
  }
}

/// The pill, the title and when it was sent (and closed).
class _Header extends StatelessWidget {
  const _Header({required this.row, required this.pill});

  final BugReportRow row;
  final (String, Color) pill;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final closed = row.closedAt;
    return Column(
      crossAxisAlignment: .start,
      spacing: 8,
      children: [
        StatusPill(label: pill.$1, ink: pill.$2),
        Text(row.title, style: PTText.screenTitle.copyWith(fontSize: 26, height: 1.05)),
        Text(
          'Sent ${reportWhen(row.createdAt, now)}'
          '${closed == null ? '' : ' · closed ${reportWhen(closed, now)}'}',
          style: PTText.finePrint.copyWith(fontSize: 13, color: PTColors.fgMute),
        ),
      ],
    );
  }
}

class _ClosedDetail extends StatelessWidget {
  const _ClosedDetail({required this.row});

  final BugReportRow row;

  @override
  Widget build(BuildContext context) {
    final reason = row.reason?.trim();
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 16,
      children: [
        _Header(row: row, pill: reportPill(row)),
        GlassPanel(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: .start,
            spacing: 8,
            children: [
              Text('WHY WE CLOSED THIS', style: PTText.label.copyWith(fontSize: 11)),
              Text(
                reason == null || reason.isEmpty
                    ? 'We looked into this one and closed it.'
                    : reason,
                style: PTText.body.copyWith(height: 1.55, color: PTColors.fg),
              ),
            ],
          ),
        ),
        Text(
          'Think we got it wrong? Tell us. It takes one tap, and we’ll look again.',
          style: PTText.body.copyWith(fontSize: 14, height: 1.5, color: PTColors.fgSoft),
        ),
        PTButton(
          label: 'Still happening? Tell us',
          variant: .secondary,
          onPressed: () => BugReport.open(context, source: 'reports', followUpOf: row.code),
        ),
      ],
    );
  }
}

class _DuplicateDetail extends StatelessWidget {
  const _DuplicateDetail({required this.row});

  final BugReportRow row;

  @override
  Widget build(BuildContext context) {
    final original = row.duplicateOf!;
    final label = switch (original.status) {
      BugStatus.looking => 'LOOKING INTO IT',
      BugStatus.fixed => 'FIXED',
      BugStatus.wontfix => 'CLOSED',
      _ => 'RECEIVED',
    };
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 16,
      children: [
        _Header(row: row, pill: ('SAME AS ${original.code}', PTColors.fgDim)),
        Text(
          "Good news: someone already reported this, so we're on it. You'll hear about it the "
          'moment it’s fixed, with nothing more needed from you.',
          style: PTText.body.copyWith(height: 1.5, color: PTColors.fgDim),
        ),
        // Only the original's code, a neutral title and where it stands: never
        // the other reporter's note, screenshot or details.
        GlassPanel(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: .start,
            spacing: 6,
            children: [
              Text('TRACKING', style: PTText.label.copyWith(fontSize: 11)),
              Wrap(
                crossAxisAlignment: .center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    original.code,
                    style: PTText.label.copyWith(color: PTColors.fgDim, letterSpacing: 1),
                  ),
                  StatusPill(label: label, ink: originalStatusInkFor(original.status)),
                ],
              ),
              Text(
                original.title,
                style: PTText.body.copyWith(fontSize: 16, fontWeight: .w500, color: PTColors.fg),
              ),
              const SizedBox(height: 4),
              _Steps(status: original.status),
              if (row.sameCount > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    "${row.sameCount + 1} people have sent this one, so it's near the top of the list.",
                    style: PTText.finePrint.copyWith(fontSize: 12.5, color: PTColors.fgMute),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A pill's ink for the original's status: Beam while it is being looked at,
/// Cue once fixed, otherwise the neutral outline.
Color originalStatusInkFor(BugStatus s) => switch (s) {
  BugStatus.looking => PTColors.primary,
  BugStatus.fixed => PTColors.online,
  _ => PTColors.fgDim,
};

/// Received, looking into it, fixed: the steps passed are filled, the one it is
/// on takes the status colour, the rest stay hollow.
class _Steps extends StatelessWidget {
  const _Steps({required this.status});

  final BugStatus status;

  @override
  Widget build(BuildContext context) {
    final at = switch (status) {
      BugStatus.looking => 1,
      BugStatus.fixed => 2,
      _ => 0,
    };
    const names = ['Received', 'Looking into it', 'Fixed'];
    final inks = [PTColors.fgSoft, PTColors.primary, PTColors.online];
    return Column(
      crossAxisAlignment: .start,
      children: [
        for (var i = 0; i < 3; i++)
          SizedBox(
            height: 30,
            child: Row(
              spacing: 10,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i <= at ? (i == at ? inks[i] : PTColors.fgSoft) : null,
                    border: Border.all(
                      color: i <= at ? (i == at ? inks[i] : PTColors.fgSoft) : PTColors.railStrong,
                      width: 2,
                    ),
                  ),
                ),
                Text(
                  names[i],
                  style: PTText.caption.copyWith(
                    fontSize: 13,
                    color: i == at ? PTColors.fg : (i < at ? PTColors.fgSoft : PTColors.fgMute),
                    fontWeight: i == at ? .w600 : .w500,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
