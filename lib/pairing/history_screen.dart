import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../analytics.dart';
import '../nav.dart';
import '../platform.dart';
import '../ui/banners.dart';
import '../ui/booth_icons.g.dart';
import '../ui/buttons.dart';
import '../ui/pt_theme.dart';
import 'pair_logic.dart';
import 'pair_models.dart';
import 'pair_page.dart';
import 'pair_service.dart';
import 'pair_share.dart';
import 'pair_widgets.dart';

/// Your streak and what you watched together. The last seven days are free; the
/// rest is kept (never deleted) behind Patron on either side - and the export
/// is always free, so a lapse never feels like losing the memories.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    unawaited(PairService.instance.load());
    unawaited(PairService.instance.loadHistory());
  }

  Future<void> _export(BuildContext buttonContext) async {
    setState(() => _exporting = true);
    try {
      final all = await PairService.instance.exportHistory();
      if (!buttonContext.mounted) return;
      await shareBytes(
        buttonContext,
        bytes: utf8.encode(historyToCsv(all)),
        name: 'our-history.csv',
        mimeType: 'text/csv',
      );
    } catch (_) {
      if (mounted) showPTSnack(context, "Couldn't export just now. Try again.", kind: .error);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PairService.instance,
      builder: (context, _) {
        final svc = PairService.instance;
        final stats = svc.stats;
        final history = svc.history;

        // Group the visible sittings by month, newest first.
        final byMonth = <String, List<PairSession>>{};
        for (final s in history.items) {
          byMonth.putIfAbsent(monthHeading(s.startedAt.toLocal()), () => []).add(s);
        }

        return PairPage(
          title: 'Our streak',
          children: [
            _StreakCard(stats: stats),
            Row(
              spacing: 10,
              children: [
                Expanded(
                  child: _Stat(value: '${stats.nights}', label: 'nights'),
                ),
                Expanded(
                  child: _Stat(value: hoursLabel(stats.hours), label: 'hours'),
                ),
                Expanded(
                  child: _Stat(value: '${stats.films}', label: 'films'),
                ),
              ],
            ),
            const PairNote(
              'A week counts when you spent twenty minutes together in it. Missing one only affects this streak, never your own.',
            ),
            PairPanel(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: PairRow(
                icon: BoothIcons.star,
                title: 'Our year',
                onTap: () => openPage(context, '/lobby/pair/year'),
              ),
            ),
            const SizedBox(height: 4),
            const PairKicker('Watched together'),
            if (history.items.isEmpty && history.lockedCount == 0)
              PairPanel(
                child: Text(
                  'Nothing yet. The first film you finish together lands here.',
                  style: PTText.body.copyWith(color: PTColors.fgSoft, fontSize: 14, height: 1.45),
                ),
              )
            else ...[
              for (final entry in byMonth.entries) ...[
                PairKicker(entry.key),
                PairPanel(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Column(
                    children: [
                      for (var i = 0; i < entry.value.length; i++) ...[
                        if (i > 0) const PairDivider(),
                        _SessionRow(session: entry.value[i]),
                      ],
                    ],
                  ),
                ),
              ],
              if (history.lockedCount > 0) _LockedCard(count: history.lockedCount),
            ],
            if (history.items.isNotEmpty || history.lockedCount > 0)
              Builder(
                builder: (buttonContext) => PTButton(
                  label: 'Export my history',
                  variant: .secondary,
                  icon: BoothIcons.share,
                  height: 44,
                  loading: _exporting,
                  onPressed: () => _export(buttonContext),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.stats});

  final PairStats stats;

  @override
  Widget build(BuildContext context) {
    final weeks = stats.streakWeeks;
    final lit = weeks.clamp(0, 8);
    return PairPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 16,
        children: [
          Row(
            spacing: 10,
            children: [
              const Icon(BoothIcons.fire, size: 28, color: PTColors.streak),
              Text(
                '$weeks',
                style: PTText.display.copyWith(fontSize: 48, height: 1, color: PTColors.streak),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  spacing: 2,
                  children: [
                    Text(
                      weeks == 1 ? 'week of date nights' : 'weeks of date nights',
                      style: PTText.body.copyWith(
                        fontWeight: .w600,
                        fontSize: 15,
                        color: PTColors.fg,
                      ),
                    ),
                    Text(
                      'BEST · ${stats.bestStreakWeeks} ${stats.bestStreakWeeks == 1 ? 'WEEK' : 'WEEKS'}',
                      style: PTText.mono.copyWith(fontSize: 11, color: PTColors.fgMute),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 8,
            children: [
              for (var i = 0; i < 8; i++)
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < lit ? PTColors.streak : Colors.transparent,
                    border: Border.all(
                      color: i < lit ? PTColors.streak : PTColors.rail,
                      width: 1.5,
                    ),
                  ),
                ),
            ],
          ),
          Text(
            stats.doneThisWeek
                ? "That's this week done. See you next week."
                : weeks > 0
                ? 'One night together a week keeps it going. Next one by Sunday.'
                : 'Spend twenty minutes together this week to start one.',
            textAlign: TextAlign.center,
            style: PTText.caption.copyWith(color: PTColors.fgSoft),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => PairPanel(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: .start,
      spacing: 4,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: PTText.display.copyWith(fontSize: 30, height: 1)),
        ),
        Text(label, style: PTText.caption.copyWith(color: PTColors.fgSoft, fontSize: 12)),
      ],
    ),
  );
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session});

  final PairSession session;

  @override
  Widget build(BuildContext context) {
    final local = session.startedAt.toLocal();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        spacing: 12,
        children: [
          _DateTile(day: local),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              spacing: 3,
              children: [
                Text(
                  session.title ?? 'A night in',
                  maxLines: 2,
                  overflow: .ellipsis,
                  style: PTText.body.copyWith(fontSize: 15, fontWeight: .w600, color: PTColors.fg),
                ),
                Text(
                  formatClock(local).toUpperCase(),
                  style: PTText.mono.copyWith(fontSize: 11, color: PTColors.fgMute),
                ),
              ],
            ),
          ),
          Text(
            durationLabel(session.seconds),
            style: PTText.mono.copyWith(fontSize: 12, color: PTColors.fgDim),
          ),
        ],
      ),
    );
  }
}

/// Older nights are kept, not deleted: they are only hidden behind Patron.
class _LockedCard extends StatelessWidget {
  const _LockedCard({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return PairPanel(
      brass: true,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 12,
        children: [
          Row(
            spacing: 12,
            children: [
              const Icon(BoothIcons.lock, size: 18, color: PTColors.premium),
              Expanded(
                child: Text(
                  '$count older ${count == 1 ? 'night is' : 'nights are'} kept safe. Patron on either side brings them back.',
                  style: PTText.body.copyWith(fontSize: 14, color: PTColors.fgDim, height: 1.4),
                ),
              ),
              const PatronTag(),
            ],
          ),
          if (canSellPremium)
            PTButton(
              label: 'Get a Patron seat',
              icon: BoothIcons.crown,
              height: 42,
              onPressed: () {
                Analytics.instance.track('upgrade_cta_clicked', {
                  'surface': 'pair_history',
                  'action': 'subscribe',
                });
                openPage(context, '/lobby/subscribe?source=pair_history');
              },
            ),
        ],
      ),
    );
  }
}

/// The row's lead: the day the night started, as a weekday over a day number. A night
/// can hold many films and a video can vanish, so the tile says only what is always true.
/// Fixed 44 x 44: text scales to 1.3x and then fits inside the box, it never grows it.
class _DateTile extends StatelessWidget {
  const _DateTile({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: formatDay(day),
      excludeSemantics: true,
      child: Container(
        width: 44,
        height: 44,
        padding: const EdgeInsets.all(2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: PTColors.aisle,
          borderRadius: BorderRadius.circular(PTRadius.control),
        ),
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: .min,
              children: [
                Text(
                  weekdayShort(day),
                  style: PTText.mono.copyWith(fontSize: 9, height: 1.1, color: PTColors.fgMute),
                ),
                Text(
                  '${day.day}',
                  style: PTText.mono.copyWith(
                    fontSize: 18,
                    height: 1.1,
                    fontWeight: .w600,
                    color: PTColors.fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
