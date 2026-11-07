import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../analytics.dart';
import '../nav.dart';
import '../platform.dart';
import '../profile/profile_service.dart';
import '../ui/banners.dart';
import '../ui/booth_icons.g.dart';
import '../ui/buttons.dart';
import '../ui/glass.dart';
import '../ui/pt_theme.dart';
import 'pair_logic.dart';
import 'pair_models.dart';
import 'pair_page.dart';
import 'pair_service.dart';
import 'pair_share.dart';
import 'pair_widgets.dart';

/// Date nights: the ones coming up, answered or waiting, and the way to plan
/// another. Planning needs Patron on either side; answering, moving and
/// cancelling one never does.
class DateNightScreen extends StatefulWidget {
  const DateNightScreen({super.key});

  @override
  State<DateNightScreen> createState() => _DateNightScreenState();
}

class _DateNightScreenState extends State<DateNightScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    unawaited(PairService.instance.load());
    // Countdowns are in minutes, so a minute is as often as they need to move.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PairService.instance,
      builder: (context, _) {
        final svc = PairService.instance;
        final pair = svc.pair;
        final me = ProfileService.instance.profile?.id ?? '';
        final now = DateTime.now().toUtc();
        final nights = upcomingNights(now, svc.nights);
        return PairPage(
          title: 'Date nights',
          footer: PTButton(
            label: 'Plan a date night',
            icon: BoothIcons.add,
            onPressed: pair == null ? null : () => showPlanNight(context),
          ),
          children: [
            if (nights.isEmpty)
              PairPanel(
                child: Column(
                  crossAxisAlignment: .start,
                  spacing: 6,
                  children: [
                    Text('Nothing planned', style: PTText.cardHeading.copyWith(fontSize: 18)),
                    Text(
                      'Pick a night, see it on both your clocks, and get a nudge fifteen minutes before.',
                      style: PTText.body.copyWith(
                        color: PTColors.fgSoft,
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            for (final night in nights)
              _NightCard(
                night: night,
                standing: nightStanding(now, night, me),
                partner: pair?.partner,
                now: now,
              ),
            if (pair != null && !pair.patron)
              const PairNote(
                'Planning a date night needs Patron on either side. Answering one never does.',
                center: true,
              ),
          ],
        );
      },
    );
  }
}

class _NightCard extends StatelessWidget {
  const _NightCard({
    required this.night,
    required this.standing,
    required this.partner,
    required this.now,
  });

  final DateNight night;
  final NightStanding standing;
  final PairPartner? partner;
  final DateTime now;

  String get _first => partner?.displayName.split(' ').first ?? 'your person';

  Future<void> _calendar(BuildContext context) async {
    final ics = buildDateNightIcs(
      id: night.id,
      title: night.title,
      startsAt: night.startsAt,
      withName: _first,
    );
    await shareBytes(
      context,
      bytes: utf8.encode(ics),
      name: 'date-night.ics',
      mimeType: 'text/calendar',
    );
  }

  Future<void> _answer(BuildContext context, bool accept) async {
    try {
      await PairService.instance.answerNight(night.id, accept: accept);
    } catch (e) {
      if (context.mounted) showPTSnack(context, PairErrorCode.fromError(e).message, kind: .error);
    }
  }

  Future<void> _move(BuildContext context) async {
    final when = await pickNightTime(context, initial: night.startsAt.toLocal());
    if (when == null || !context.mounted) return;
    try {
      await PairService.instance.rescheduleNight(night.id, when);
    } catch (e) {
      if (context.mounted) showPTSnack(context, PairErrorCode.fromError(e).message, kind: .error);
    }
  }

  Future<void> _cancel(BuildContext context) async {
    final go = await showGlassDialog<bool>(
      context: context,
      width: 400,
      builder: (ctx) => Column(
        crossAxisAlignment: .stretch,
        spacing: 14,
        children: [
          Text('Cancel ${night.title}?', style: PTText.screenTitle.copyWith(fontSize: 24)),
          Text(
            'Tells $_first once, quietly, and both reminders go away.',
            style: PTText.body.copyWith(color: PTColors.fgSoft, height: 1.5),
          ),
          Row(
            spacing: 10,
            children: [
              Expanded(
                child: PTButton(
                  label: 'Keep it',
                  variant: .secondary,
                  height: 44,
                  onPressed: () => Navigator.of(ctx).pop(false),
                ),
              ),
              Expanded(
                child: PTButton(
                  label: 'Cancel night',
                  variant: .destructive,
                  height: 44,
                  onPressed: () => Navigator.of(ctx).pop(true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (go == true) await PairService.instance.cancelNight(night.id);
  }

  @override
  Widget build(BuildContext context) {
    final placement = placeNight(night.startsAt, partnerZone: partner?.timezone);
    final imminent = isNightImminent(now, night);
    final label = switch (standing) {
      NightStanding.awaitingMe => '$_first proposed this',
      NightStanding.awaitingThem => 'Waiting for $_first',
      NightStanding.accepted => 'Locked in',
      NightStanding.done => 'Just finished',
      NightStanding.declined => 'Declined',
      NightStanding.cancelled => 'Cancelled',
    };
    return PairPanel(
      live: imminent && standing == NightStanding.accepted,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 12,
        children: [
          Row(
            children: [
              Expanded(
                child: PairKicker(
                  label,
                  color: standing == NightStanding.awaitingMe ? PTColors.primary : null,
                ),
              ),
              if (standing == NightStanding.accepted)
                PairPill(
                  countdownTo(night.startsAt, now).label,
                  color: imminent ? PTColors.primary : PTColors.online,
                  fill: imminent ? PTColors.pillWarning : null,
                ),
            ],
          ),
          Text(night.title, style: PTText.cardHeading.copyWith(fontSize: 22, height: 1.1)),
          _When(placement: placement, partnerName: _first),
          if (placement.lateForThem && standing != NightStanding.cancelled)
            Row(
              spacing: 8,
              children: [
                const Icon(BoothIcons.clock, size: 16, color: PTColors.warning),
                Expanded(
                  child: Text(
                    "That's the middle of the night for $_first.",
                    style: PTText.caption.copyWith(color: PTColors.warning),
                  ),
                ),
              ],
            ),
          ..._actions(context),
        ],
      ),
    );
  }

  List<Widget> _actions(BuildContext context) {
    return switch (standing) {
      NightStanding.awaitingMe => [
        Row(
          spacing: 10,
          children: [
            Expanded(
              child: PTButton(
                label: "I'm in",
                icon: BoothIcons.check,
                height: 44,
                onPressed: () => _answer(context, true),
              ),
            ),
            Expanded(
              child: PTButton(
                label: "Can't make it",
                variant: .secondary,
                height: 44,
                onPressed: () => _answer(context, false),
              ),
            ),
          ],
        ),
        Center(
          child: DialogTextButton(label: 'Suggest another time', onPressed: () => _move(context)),
        ),
      ],
      NightStanding.awaitingThem => [
        Row(
          spacing: 10,
          children: [
            Expanded(
              child: PTButton(
                label: 'Change time',
                variant: .secondary,
                height: 42,
                onPressed: () => _move(context),
              ),
            ),
            Expanded(
              child: PTButton(
                label: 'Cancel',
                variant: .secondary,
                height: 42,
                onPressed: () => _cancel(context),
              ),
            ),
          ],
        ),
      ],
      NightStanding.accepted => [
        Builder(
          builder: (buttonContext) => PTButton(
            label: 'Add to calendar',
            variant: .secondary,
            icon: BoothIcons.calendar,
            height: 44,
            onPressed: () => _calendar(buttonContext),
          ),
        ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 18,
          runSpacing: 2,
          children: [
            DialogTextButton(label: 'Change time', onPressed: () => _move(context)),
            DialogTextButton(
              label: 'Cancel night',
              color: PTColors.danger,
              onPressed: () => _cancel(context),
            ),
          ],
        ),
      ],
      _ => const [],
    };
  }
}

/// A night's time on your clock, and on theirs only when theirs is different.
class _When extends StatelessWidget {
  const _When({required this.placement, required this.partnerName});

  final NightPlacement placement;
  final String partnerName;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: .start,
      spacing: 4,
      children: [
        Text(
          formatMoment(placement.mine),
          style: PTText.mono.copyWith(fontSize: 14, color: PTColors.fg),
        ),
        if (placement.zonesDiffer && placement.theirs != null)
          Text(
            '${formatClock(placement.theirs!)} for $partnerName'
            '${placement.theirCity.isEmpty ? '' : ' in ${placement.theirCity}'}',
            style: PTText.mono.copyWith(fontSize: 12.5, color: PTColors.fgSoft),
          ),
      ],
    );
  }
}

// ------------------------------------------------------------------ planning

/// Date then time, as the platform's own pickers. Returns the chosen local
/// moment, or null if either was dismissed.
Future<DateTime?> pickNightTime(BuildContext context, {DateTime? initial}) async {
  final now = DateTime.now();
  final start = initial ?? DateTime(now.year, now.month, now.day + 1, 21);
  final day = await showDatePicker(
    context: context,
    initialDate: start.isBefore(now) ? now : start,
    firstDate: DateTime(now.year, now.month, now.day),
    lastDate: now.add(const Duration(days: 365)),
  );
  if (day == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: start.hour, minute: start.minute),
  );
  if (time == null) return null;
  return DateTime(day.year, day.month, day.day, time.hour, time.minute);
}

/// Plan a date night: what, when, and how that lands on each clock. Shows the
/// Patron gate instead when neither partner has it.
Future<void> showPlanNight(BuildContext context) async {
  final svc = PairService.instance;
  final pair = svc.pair;
  if (pair == null) return;
  if (!pair.patron) {
    await _showGate(context);
    return;
  }
  final title = TextEditingController(
    text: svc.watchlist.where((i) => !i.watched).firstOrNull?.title ?? '',
  );
  var when = DateTime.now().add(const Duration(days: 1)).copyWith(hour: 21, minute: 0, second: 0);
  var busy = false;
  String? problem;
  await showGlassDialog<void>(
    context: context,
    width: 440,
    sheetOnCompact: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final placement = placeNight(when.toUtc(), partnerZone: pair.partner.timezone);
        final first = pair.partner.displayName.split(' ').first;

        Future<void> send() async {
          setState(() {
            busy = true;
            problem = null;
          });
          try {
            await svc.planNight(title: title.text, startsAt: when);
            if (ctx.mounted) Navigator.of(ctx).pop();
          } catch (e) {
            setState(() {
              busy = false;
              problem = PairErrorCode.fromError(e).message;
            });
          }
        }

        return Column(
          crossAxisAlignment: .stretch,
          spacing: 14,
          children: [
            Text('Plan a date night', style: PTText.screenTitle.copyWith(fontSize: 24)),
            TextField(
              controller: title,
              maxLength: 120,
              textCapitalization: TextCapitalization.sentences,
              style: PTText.body,
              decoration: const InputDecoration(hintText: 'What are you watching?'),
            ),
            PTButton(
              label: formatMoment(when),
              variant: .secondary,
              icon: BoothIcons.calendar,
              height: 46,
              onPressed: () async {
                final picked = await pickNightTime(ctx, initial: when);
                if (picked != null) setState(() => when = picked);
              },
            ),
            _Strips(placement: placement, partnerName: first),
            if (placement.lateForThem)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: PTColors.pillWarning,
                  borderRadius: BorderRadius.circular(PTRadius.control),
                  border: Border.all(color: PTColors.primary.withValues(alpha: 0.4)),
                ),
                child: Row(
                  spacing: 10,
                  children: [
                    const Icon(BoothIcons.clock, size: 18, color: PTColors.warning),
                    Expanded(
                      child: Text(
                        'That is ${formatClock(placement.theirs!)} for $first. Send it anyway, '
                        'or try a time that lands in their evening.',
                        style: PTText.caption.copyWith(color: PTColors.warning, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            if (problem != null)
              Text(problem!, style: PTText.body.copyWith(color: PTColors.danger, fontSize: 14)),
            Row(
              spacing: 10,
              children: [
                Expanded(
                  child: PTButton(
                    label: 'Cancel',
                    variant: .secondary,
                    height: 44,
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ),
                Expanded(
                  child: PTButton(
                    label: placement.lateForThem ? 'Send anyway' : 'Send to $first',
                    height: 44,
                    loading: busy,
                    onPressed: send,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    ),
  );
  title.dispose();
}

Future<void> _showGate(BuildContext context) async {
  Analytics.instance.track('upgrade_cta_shown', {'surface': 'date_night'});
  await showGlassDialog<void>(
    context: context,
    width: 420,
    sheetOnCompact: true,
    builder: (ctx) => Column(
      crossAxisAlignment: .stretch,
      spacing: 14,
      children: [
        Row(
          spacing: 10,
          children: [
            Expanded(child: Text('Date nights', style: PTText.screenTitle.copyWith(fontSize: 24))),
            const PatronTag(),
          ],
        ),
        Text(
          "Planning a date night needs Patron on either side - one seat covers the both of you. "
          "Answering, moving or cancelling one you're sent never does.",
          style: PTText.body.copyWith(color: PTColors.fgSoft, height: 1.5),
        ),
        if (canSellPremium)
          PTButton(
            label: 'Get a Patron seat',
            icon: BoothIcons.crown,
            onPressed: () {
              Analytics.instance.track('upgrade_cta_clicked', {
                'surface': 'date_night',
                'action': 'subscribe',
              });
              Navigator.of(ctx).pop();
              openPage(context, '/lobby/subscribe?source=date_night');
            },
          ),
        PTButton(label: 'Not now', variant: .secondary, onPressed: () => Navigator.of(ctx).pop()),
      ],
    ),
  );
}

/// Both people's day as two 24-hour strips with the proposed time marked, night
/// shaded: the "is this a bad hour for them" answer, at a glance.
class _Strips extends StatelessWidget {
  const _Strips({required this.placement, required this.partnerName});

  final NightPlacement placement;
  final String partnerName;

  @override
  Widget build(BuildContext context) {
    return PairPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 12,
        children: [
          _Strip(label: 'You', wall: placement.mine, warn: false),
          if (placement.theirs != null)
            _Strip(
              label: placement.theirCity.isEmpty
                  ? partnerName
                  : '$partnerName · ${placement.theirCity}',
              wall: placement.theirs!,
              warn: placement.lateForThem,
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final h in const ['00', '06', '12', '18', '24'])
                Text(h, style: PTText.mono.copyWith(fontSize: 9, color: PTColors.fgMute)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip({required this.label, required this.wall, required this.warn});

  final String label;
  final DateTime wall;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final start = wall.hour + wall.minute / 60;
    final color = warn ? PTColors.warning : PTColors.primary;
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 6,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: .ellipsis,
                style: PTText.body.copyWith(fontSize: 13, color: PTColors.fgDim),
              ),
            ),
            Text(
              formatClock(wall),
              style: PTText.mono.copyWith(
                fontSize: 13,
                color: warn ? PTColors.warning : PTColors.fg,
              ),
            ),
          ],
        ),
        LayoutBuilder(
          builder: (context, box) {
            double x(double h) => box.maxWidth * h / 24;
            final window = (start + 3 > 24) ? 24 - start : 3.0;
            return SizedBox(
              height: 18,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: PTColors.glassBase,
                  borderRadius: BorderRadius.circular(PTRadius.control),
                  border: Border.all(color: PTColors.rail),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(PTRadius.control),
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        width: x(7),
                        top: 0,
                        bottom: 0,
                        child: const ColoredBox(color: PTColors.aisle),
                      ),
                      Positioned(
                        left: x(22),
                        right: 0,
                        top: 0,
                        bottom: 0,
                        child: const ColoredBox(color: PTColors.aisle),
                      ),
                      Positioned(
                        left: x(start),
                        width: x(window),
                        top: 2,
                        bottom: 2,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
