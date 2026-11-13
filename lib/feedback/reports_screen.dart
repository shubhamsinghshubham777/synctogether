import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../pairing/pair_page.dart';
import '../ui/loader.dart';
import '../ui/pt_motion.dart';
import '../ui/pt_theme.dart';
import 'contract.dart';
import 'discovery/discovery_triggers.dart';
import 'feedback_services.dart';
import 'fixed_from.dart';

/// Where one report's page lives, under Your reports so the stack pops back to
/// the list.
String reportPath(String code) => '/lobby/profile/reports/${Uri.encodeComponent(code)}';

/// Profile > Your reports: every report the user sent, with where it stands.
/// A fix shown here is the quiet end of the loop - the user was heard and told.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PairPage(title: 'Your reports', spacing: 0, children: const [ReportsBody()]);
  }
}

/// The list itself, apart from the page frame so it can be tested alone.
class ReportsBody extends StatelessWidget {
  const ReportsBody({super.key});

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
        if (rows.isEmpty) return const _Empty();
        return Column(
          crossAxisAlignment: .stretch,
          children: [
            for (final (i, r) in rows.indexed) ReportTile(row: r, first: i == 0),
            Padding(
              padding: const EdgeInsets.only(top: 22),
              child: Text(
                'Fixes and replies land here, with a quiet notification if you asked for one.',
                textAlign: TextAlign.center,
                style: PTText.finePrint.copyWith(fontSize: 13, color: PTColors.fgMute, height: 1.5),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 32),
    child: Text(
      "Nothing sent yet. If something looks off, tap the bug at the top of any screen and we'll take it from there.",
      style: PTText.body.copyWith(color: PTColors.fgSoft, height: 1.5),
    ),
  );
}

/// One report: code and status pill, the title, one honest line about where it
/// stands. [first] drops the hairline above the list.
///
/// A closed or duplicate report opens its own page (the reason in full, or the
/// original being followed); the rest have nothing more to say.
class ReportTile extends StatelessWidget {
  const ReportTile({super.key, required this.row, this.first = false});

  final BugReportRow row;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final (label, ink) = reportPill(row);
    final canUpdate =
        row.status == BugStatus.fixed &&
        showUpdateFor(row.fixedIn, canUpdate: DiscoveryTriggers.onUpdate != null);
    final opens = row.status == BugStatus.wontfix || row.status == BugStatus.duplicate;
    final body = Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(top: first ? BorderSide.none : const BorderSide(color: PTColors.aisle)),
      ),
      child: Column(
        crossAxisAlignment: .start,
        spacing: 6,
        children: [
          Wrap(
            crossAxisAlignment: .center,
            spacing: 8,
            runSpacing: 4,
            children: [
              if (row.status != BugStatus.saved)
                Text(
                  row.code,
                  style: PTText.label.copyWith(color: PTColors.fgDim, letterSpacing: 1),
                ),
              StatusPill(label: label, ink: ink),
            ],
          ),
          Text(
            row.title,
            style: PTText.body.copyWith(fontSize: 16, fontWeight: .w500, color: PTColors.fg),
          ),
          _detail(),
          if (canUpdate)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: OutlinedButton(
                onPressed: DiscoveryTriggers.onUpdate,
                child: const Text('Update now'),
              ),
            ),
        ],
      ),
    );
    if (!opens) return body;
    return Semantics(
      button: true,
      label: '${row.code}, ${row.title}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: PTPressable(
          pressedScale: 0.99,
          onTap: () => context.push(reportPath(row.code)),
          child: body,
        ),
      ),
    );
  }

  Widget _detail() {
    final style = PTText.caption.copyWith(color: PTColors.fgSoft, height: 1.45);
    final original = row.duplicateOf;
    return switch (row.status) {
      BugStatus.fixed => Text(fixedLine(row.fixedIn), style: style),
      BugStatus.looking => Text(
        row.sameCount > 1
            ? "We're on it. ${row.sameCount + 1} people have sent this one."
            : "We're on it. Nothing needed from you.",
        style: style,
      ),
      BugStatus.received => Text(reportWhen(row.createdAt, DateTime.now()), style: style),
      BugStatus.saved => Text(
        "It sends itself the moment you're back online. No need to do anything.",
        style: style,
      ),
      BugStatus.wontfix => Text(
        row.reason == null || row.reason!.isEmpty
            ? 'We looked into it and closed this one.'
            : row.reason!,
        maxLines: 2,
        overflow: .ellipsis,
        style: style,
      ),
      BugStatus.duplicate =>
        original == null
            ? Text("Someone already reported this, so we're on it.", style: style)
            : Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: 'Following ${original.code} · '),
                    TextSpan(
                      text: originalStatusWord(original.status),
                      style: TextStyle(color: originalStatusInk(original.status)),
                    ),
                  ],
                ),
                style: style,
              ),
    };
  }
}

/// The status pill of a report: its text and ink. Closed and same-as are
/// deliberately neutral, never red.
(String, Color) reportPill(BugReportRow row) => switch (row.status) {
  BugStatus.fixed => (fixedPill(row.fixedIn), PTColors.online),
  BugStatus.looking => ('LOOKING INTO IT', PTColors.primary),
  BugStatus.received => ('RECEIVED', PTColors.fgDim),
  BugStatus.saved => ('SAVED ON THIS DEVICE', PTColors.danger),
  BugStatus.wontfix => ('CLOSED', PTColors.fgDim),
  BugStatus.duplicate => (
    row.duplicateOf == null ? 'SAME AS ANOTHER REPORT' : 'SAME AS ${row.duplicateOf!.code}',
    PTColors.fgDim,
  ),
};

/// A status as one lowercase phrase, for "Following BUG-3F9A · looking into it".
String originalStatusWord(BugStatus s) => switch (s) {
  BugStatus.looking => 'looking into it',
  BugStatus.fixed => 'fixed',
  BugStatus.wontfix => 'closed',
  BugStatus.saved => 'saved',
  BugStatus.received || BugStatus.duplicate => 'received',
};

Color originalStatusInk(BugStatus s) => switch (s) {
  BugStatus.looking => PTColors.primary,
  BugStatus.fixed => PTColors.online,
  _ => PTColors.fgSoft,
};

/// The small outlined status tag every report wears. [ink] fgDim draws the
/// neutral Rail outline; closed and same-as are deliberately never red.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.ink});

  final String label;
  final Color ink;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      border: Border.all(color: ink == PTColors.fgDim ? PTColors.railStrong : ink),
      borderRadius: BorderRadius.circular(2),
    ),
    child: Text(label, style: PTText.label.copyWith(fontSize: 10, letterSpacing: 1, color: ink)),
  );
}

/// "Today 21:52", "Fri 21:52" within a week, otherwise "Nov 4". Plain Dart, no
/// intl: these are three short strings.
String reportWhen(DateTime at, DateTime now) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  String two(int n) => n.toString().padLeft(2, '0');
  final time = '${two(at.hour)}:${two(at.minute)}';
  final sameDay = at.year == now.year && at.month == now.month && at.day == now.day;
  if (sameDay) return 'Today $time';
  if (now.difference(at) < const Duration(days: 6)) return '${days[at.weekday - 1]} $time';
  return '${months[at.month - 1]} ${at.day}';
}
