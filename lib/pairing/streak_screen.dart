import 'dart:async';

import 'package:flutter/material.dart';

import '../nav.dart';
import '../ui/booth_icons.g.dart';
import '../ui/buttons.dart';
import '../ui/pt_theme.dart';
import 'date_night_plan.dart';
import 'pair_logic.dart';
import 'pair_models.dart';
import 'pair_page.dart';
import 'pair_service.dart';
import 'pair_widgets.dart';

/// Your streak: the weekly flame, the totals, and the doors to the year card and the
/// history. A week counts when you spent twenty minutes together in it.
class StreakScreen extends StatefulWidget {
  const StreakScreen({super.key});

  @override
  State<StreakScreen> createState() => _StreakScreenState();
}

class _StreakScreenState extends State<StreakScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(PairService.instance.load());
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PairService.instance,
      builder: (context, _) {
        final stats = PairService.instance.stats;
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
              child: Column(
                children: [
                  PairRow(
                    icon: BoothIcons.film,
                    title: 'Our history',
                    onTap: () => openPage(context, '/lobby/pair/history'),
                  ),
                  const PairDivider(),
                  PairRow(
                    icon: BoothIcons.star,
                    title: 'Our year',
                    onTap: () => openPage(context, '/lobby/pair/year'),
                  ),
                ],
              ),
            ),
            PTButton(
              label: 'Plan this week',
              icon: BoothIcons.calendar,
              onPressed: () => showPlanNight(context),
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
