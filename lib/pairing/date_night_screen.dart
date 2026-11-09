import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../analytics.dart';
import '../nav.dart';
import '../platform.dart';
import '../profile/profile_models.dart';
import '../profile/profile_service.dart';
import '../ui/reveal.dart';
import '../ui/panel_switcher.dart';
import '../ui/progress_bar.dart';
import '../ui/optical.dart';
import '../ui/banners.dart';
import '../ui/booth.dart';
import '../ui/booth_icons.g.dart';
import '../ui/buttons.dart';
import '../ui/glass.dart';
import '../ui/pt_motion.dart';
import '../player/local_video_chooser.dart';
import '../rooms/media_sharing_service.dart';
import '../ui/pt_theme.dart';
import 'calendar_bridge.dart';
import 'date_night_plan.dart';
import 'date_night_upload.dart';
import 'pair_logic.dart';
import 'pair_models.dart';
import 'pair_page.dart';
import 'pair_service.dart';
import 'pair_share.dart';
import 'pair_widgets.dart';

export 'date_night_plan.dart' show pickNightTime, showPlanNight;

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
      listenable: Listenable.merge([PairService.instance, DateNightUploader.instance]),
      builder: (context, _) {
        final svc = PairService.instance;
        final pair = svc.pair;
        final me = ProfileService.instance.profile?.id ?? '';
        final now = DateTime.now().toUtc();
        final nights = upcomingNights(now, svc.nights);
        final ended = recentlyEndedNights(now, svc.nights);
        final patron = pair?.patron ?? false;
        final first = pair?.partner.displayName.split(' ').first ?? 'your person';
        final sameZone =
            pair == null || !placeNight(now, partnerZone: pair.partner.timezone).zonesDiffer;

        final Widget body;
        if (!svc.loaded || !svc.nightsLoaded) {
          body = const _Skeleton();
        } else if (svc.nightsFailed && nights.isEmpty) {
          body = _LoadError(onRetry: svc.retryNights);
        } else if (nights.isEmpty) {
          body = Column(
            crossAxisAlignment: .stretch,
            spacing: 14,
            children: [
              patron ? _EmptyPatron(first: first, sameZone: sameZone) : _EmptyFree(first: first),
              ..._endedCards(ended, me: me, now: now, pair: pair),
            ],
          );
        } else {
          body = _Upcoming(
            nights: nights,
            ended: ended,
            me: me,
            now: now,
            pair: pair,
            patron: patron,
          );
        }

        final showPlan = svc.nightsLoaded && nights.isNotEmpty && patron;
        return PairPage(
          title: 'Date nights',
          trailing: showPlan
              ? DialogTextButton(label: 'Plan', onPressed: () => showPlanNight(context))
              : null,
          children: [body],
        );
      },
    );
  }
}

/// Nights that were cancelled or declined in the last two days, under a kicker of their own.
List<Widget> _endedCards(
  List<DateNight> ended, {
  required String me,
  required DateTime now,
  required PairInfo? pair,
}) => [
  if (ended.isNotEmpty) const PairKicker('Recently ended'),
  for (final night in ended)
    _NightCard(
      night: night,
      standing: nightStanding(now, night, me),
      partner: pair?.partner,
      now: now,
      mine: night.proposedBy == me,
    ),
];

// ------------------------------------------------------------------- states

/// The list once there is one: the soonest night first, and a way to the
/// history for the ones that are over.
class _Upcoming extends StatelessWidget {
  const _Upcoming({
    required this.nights,
    required this.ended,
    required this.me,
    required this.now,
    required this.pair,
    required this.patron,
  });

  final List<DateNight> nights;
  final List<DateNight> ended;
  final String me;
  final DateTime now;
  final PairInfo? pair;
  final bool patron;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 14,
      children: [
        PairKicker('Coming up · ${nights.length}'),
        for (final night in nights)
          _NightCard(
            night: night,
            standing: nightStanding(now, night, me),
            partner: pair?.partner,
            now: now,
            mine: night.proposedBy == me,
          ),
        ..._endedCards(ended, me: me, now: now, pair: pair),
        if (!patron && canSellPremium) const _PatronRow(),
        PTPressable(
          onTap: () => openPage(context, '/lobby/pair/streak'),
          pressedScale: 0.99,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              spacing: 10,
              children: [
                const Icon(BoothIcons.fire, size: 16, color: PTColors.fgDim),
                Expanded(
                  child: Text(
                    'Finished nights live in Streak and history',
                    style: PTText.body.copyWith(fontSize: 14, color: PTColors.fgDim),
                  ),
                ),
                const Icon(BoothIcons.chevronRight, size: 16, color: PTColors.fgMute),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// "Booked nights keep running. Planning another needs Patron": a pair that has
/// no Patron but still has a night booked. Quiet, brass-edged, never a wall.
class _PatronRow extends StatelessWidget {
  const _PatronRow();

  @override
  Widget build(BuildContext context) {
    return PairPanel(
      brass: true,
      padding: const EdgeInsets.all(14),
      child: Row(
        spacing: 12,
        children: [
          const Icon(BoothIcons.crown, size: 20, color: PTColors.premium),
          Expanded(
            child: Text(
              'Booked nights keep running. Planning another needs a Patron seat on either side.',
              style: PTText.body.copyWith(fontSize: 14, color: PTColors.fgDim, height: 1.35),
            ),
          ),
          DialogTextButton(
            label: 'See Patron',
            onPressed: () {
              Analytics.instance.track('upgrade_cta_clicked', {
                'surface': 'date_night',
                'action': 'subscribe',
              });
              openPage(context, '/lobby/subscribe?source=date_night');
            },
          ),
        ],
      ),
    );
  }
}

/// Nothing planned yet, and planning is available: the pitch, in three steps,
/// and the one amber button.
class _EmptyPatron extends StatelessWidget {
  const _EmptyPatron({required this.first, required this.sameZone});

  final String first;
  final bool sameZone;

  @override
  Widget build(BuildContext context) {
    final steps = [
      'Choose a day and a time. ${sameZone ? 'The time is shown once.' : 'Both clocks are shown.'}',
      'Attach a YouTube link or a file, or skip it.',
      '$first says yes. You get a nudge 15 minutes before.',
    ];
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 14,
      children: [
        const _GhostTicket(),
        Text(
          'Pick a night. Pick a movie.',
          style: PTText.display.copyWith(fontSize: 34, height: 1),
        ),
        Text(
          "Plan it, attach what you're watching, and on the night you both just open Our Room and press play.",
          style: PTText.body.copyWith(color: PTColors.fgSoft, height: 1.5),
        ),
        for (final (i, step) in steps.indexed)
          Row(
            crossAxisAlignment: .start,
            spacing: 12,
            children: [
              Text('0${i + 1}', style: PTText.mono.copyWith(fontSize: 12, color: PTColors.primary)),
              Expanded(
                child: Text(
                  step,
                  style: PTText.body.copyWith(fontSize: 14, color: PTColors.fgDim, height: 1.4),
                ),
              ),
            ],
          ),
        PTButton(
          label: 'Plan a date night',
          icon: BoothIcons.add,
          onPressed: () => showPlanNight(context),
        ),
      ],
    );
  }
}

/// Nothing planned and no Patron on either side: an explanation, not a wall.
/// Answering never needs Patron, which is the reassurance that matters.
class _EmptyFree extends StatelessWidget {
  const _EmptyFree({required this.first});

  final String first;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 14,
      children: [
        const _GhostTicket(),
        Text(
          'Date nights come with a Patron seat.',
          style: PTText.display.copyWith(fontSize: 34, height: 1),
        ),
        Text(
          'A Patron seat on either side gives you both video, date nights and your full history. '
          'One seat covers the two of you.',
          style: PTText.body.copyWith(color: PTColors.fgSoft, height: 1.5),
        ),
        PairPanel(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: .start,
            spacing: 10,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(BoothIcons.check, size: 16, color: PTColors.online),
              ),
              Expanded(
                child: Text(
                  'If $first plans one, you can answer it any time. Answering never needs Patron.',
                  style: PTText.body.copyWith(fontSize: 14, color: PTColors.fgDim, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        if (canSellPremium)
          PTButton(
            label: 'See Patron',
            icon: BoothIcons.crown,
            variant: .secondary,
            onPressed: () {
              Analytics.instance.track('upgrade_cta_clicked', {
                'surface': 'date_night',
                'action': 'subscribe',
              });
              openPage(context, '/lobby/subscribe?source=date_night');
            },
          ),
        Center(
          child: DialogTextButton(
            label: 'Not now',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
      ],
    );
  }
}

/// A ticket-shaped outline with nothing in it yet: Rail-dashed, never filled.
class _GhostTicket extends StatelessWidget {
  const _GhostTicket();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 112,
      child: CustomPaint(
        painter: _DashedBox(),
        child: Center(
          child: Row(
            mainAxisSize: .min,
            spacing: 10,
            children: [
              PTOpticalIcon(
                BoothIcons.reunion,
                beside: PTText.mono.copyWith(fontSize: 12),
                size: 18,
                color: PTColors.fgMute,
              ),
              Text(
                'NOTHING PLANNED',
                style: PTText.mono.copyWith(
                  fontSize: 12,
                  color: PTColors.fgMute,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBox extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = PTColors.railStrong
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final rect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(PTRadius.panel));
    final path = Path()..addRRect(rect);
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 7), paint);
        d += 12;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBox old) => false;
}

/// Three ticket-shaped blocks while the list is on its way. They breathe once
/// every 1.6 s, not shimmer, and hold still when motion is reduced.
class _Skeleton extends StatefulWidget {
  const _Skeleton();

  @override
  State<_Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<_Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reducedMotion(context)) {
      _c
        ..stop()
        ..value = 0;
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading your date nights',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: .stretch,
          spacing: 14,
          children: [
            const PairKicker('Coming up'),
            for (var i = 0; i < 3; i++)
              AnimatedBuilder(
                animation: _c,
                builder: (context, _) =>
                    Opacity(opacity: 0.55 + 0.45 * _c.value, child: const _SkeletonTicket()),
              ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonTicket extends StatelessWidget {
  const _SkeletonTicket();

  @override
  Widget build(BuildContext context) {
    Widget block(double w, double h) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: PTColors.aisle,
        borderRadius: BorderRadius.circular(PTRadius.control),
      ),
    );
    return PTTicket(
      stubWidth: 118,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 14, 18),
        child: Column(
          crossAxisAlignment: .start,
          mainAxisSize: .min,
          spacing: 10,
          children: [block(86, 9), block(150, 18), block(112, 9)],
        ),
      ),
      stub: Center(
        child: Column(mainAxisSize: .min, spacing: 8, children: [block(54, 9), block(40, 14)]),
      ),
    );
  }
}

/// The list could not be fetched. Said calmly: what you planned is safe, only
/// the list failed; the real cause went to reportNonFatal, not onto the screen.
class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 56),
      child: Column(
        spacing: 12,
        children: [
          const Icon(BoothIcons.reunion, size: 36, color: PTColors.fgMute),
          Text(
            "Couldn't load your date nights just now.",
            textAlign: TextAlign.center,
            style: PTText.cardHeading.copyWith(fontSize: 24, height: 1.1),
          ),
          Text(
            "Nights you've already planned are safe. This is only the list.",
            textAlign: TextAlign.center,
            style: PTText.body.copyWith(color: PTColors.fgSoft, height: 1.45),
          ),
          const SizedBox(height: 4),
          PTButton(label: 'Try again', variant: .secondary, expand: false, onPressed: onRetry),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------- cards

/// A night as a paper ticket: the day and your clock on the left, the countdown
/// on the stub, and beneath it what you are watching and what you can do.
class _NightCard extends StatelessWidget {
  const _NightCard({
    required this.night,
    required this.standing,
    required this.partner,
    required this.now,
    required this.mine,
  });

  final DateNight night;
  final NightStanding standing;
  final PairPartner? partner;
  final DateTime now;

  /// Whether I planned it.
  final bool mine;

  String get _first => partner?.displayName.split(' ').first ?? 'your person';

  /// The system's own add-to-calendar sheet where there is one (iOS, Android);
  /// otherwise - desktop, or access refused - a calendar file through the share
  /// sheet, which any calendar app opens. Either way the event carries the start
  /// in UTC, so it lands at the right moment in whichever zone opens it.
  Future<void> _calendar(BuildContext context) async {
    const length = Duration(hours: 2);
    final result = await calendarBridge.addEvent(
      title: 'Date night: ${night.title}',
      start: night.startsAt,
      end: night.startsAt.add(length),
      notes: 'Watching ${night.title} with $_first in Our Room.',
    );
    if (!context.mounted) return;
    switch (result) {
      case CalendarResult.added:
        showPTSnack(context, 'Added to your calendar.', kind: .success);
      case CalendarResult.opened || CalendarResult.dismissed:
        break;
      case CalendarResult.unsupported:
        await _shareIcs(context);
    }
  }

  /// The same event as a calendar file, through the share sheet: any calendar app opens it.
  Future<void> _shareIcs(BuildContext context) async {
    final ics = buildDateNightIcs(
      id: night.id,
      title: night.title,
      startsAt: night.startsAt,
      withName: _first,
      length: const Duration(hours: 2),
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
    final when = await pickNightTime(context, initial: night.startsAt.toLocal(), moving: true);
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

  bool get _over =>
      standing == NightStanding.cancelled ||
      standing == NightStanding.declined ||
      standing == NightStanding.done;

  ({String text, Color color}) _badgeFor(FileView file) {
    if (standing == NightStanding.accepted && night.hasFile) {
      return switch (file.stage) {
        FileStage.ready => (text: 'READY', color: PTColors.online),
        FileStage.stopped => (text: 'UPLOAD STOPPED', color: PTColors.danger),
        FileStage.unfinished => (text: 'STILL UPLOADING ${file.percent}%', color: PTColors.warning),
        _ => (text: 'UPLOADING ${file.percent}%', color: PTColors.primary),
      };
    }
    return _badge;
  }

  ({String text, Color color}) get _badge => switch (standing) {
    NightStanding.awaitingMe when night.movedFrom != null => (
      text: 'NEW TIME\nYOUR ANSWER',
      color: PTColors.link,
    ),
    NightStanding.awaitingMe => (text: 'YOUR ANSWER', color: PTColors.link),
    NightStanding.awaitingThem => (
      text: 'WAITING FOR ${_first.toUpperCase()}',
      color: PTColors.fgSoft,
    ),
    NightStanding.accepted when night.hasLink => (text: 'READY', color: PTColors.online),
    NightStanding.accepted => (text: 'LOCKED IN', color: PTColors.online),
    NightStanding.done => (text: 'IN YOUR HISTORY', color: PTColors.fgSoft),
    NightStanding.declined => (text: 'DECLINED', color: PTColors.fgMute),
    NightStanding.cancelled => (text: 'CANCELLED', color: PTColors.fgMute),
  };

  static final _idle = ValueNotifier<int>(0);

  @override
  Widget build(BuildContext context) {
    final live = DateNightUploader.instance.forNight(night.id);
    return ListenableBuilder(
      listenable: live ?? _idle,
      builder: (context, _) => _card(context, live),
    );
  }

  Widget _card(BuildContext context, DateNightUpload? live) {
    final placement = placeNight(night.startsAt, partnerZone: partner?.timezone);
    final imminent = isNightImminent(now, night);
    final file = fileViewOf(
      night,
      now,
      liveFraction: live != null && live.total > 0 ? live.fraction : null,
      liveStopped: live?.phase == UploadPhase.stopped ? true : null,
    );
    final badge = _badgeFor(file);
    final started = !now.isBefore(night.startsAt);
    final ink = _over ? PTColors.fgMute : PTColors.canvas;
    final moved = night.movedFrom == null
        ? null
        : placeNight(night.movedFrom!, partnerZone: partner?.timezone).mine;
    final zoneLine = placement.zonesDiffer && placement.theirs != null
        ? '$_first · ${formatClock(placement.theirs!)}'
              '${placement.theirCity.isEmpty ? '' : ' ${placement.theirCity}'}'
        : null;
    // One line under the title saying where the night stands.
    final sub = switch (standing) {
      _ when moved != null && !_over =>
        'Moved from ${formatDay(moved)} · ${mine ? 'you suggested it' : '$_first suggested it'}',
      NightStanding.accepted => '${started ? 'Starting now' : 'Locked in'} · $_first is in',
      NightStanding.declined => mine ? "$_first can't make it" : "You can't make it",
      NightStanding.cancelled => 'This night was cancelled',
      _ => zoneLine,
    };

    final actions = _actions(context);
    return PTColumn(
      spacing: 10,
      children: [
        PTTicket(
          paper: !_over,
          stubWidth: 118,
          semanticLabel: '${night.title}, ${formatMoment(placement.mine)}',
          body: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
            child: Column(
              crossAxisAlignment: .start,
              mainAxisSize: .min,
              spacing: 6,
              children: [
                Text(
                  '${formatDay(placement.mine).toUpperCase()} · YOUR TIME',
                  style: PTText.label.copyWith(
                    color: _over ? PTColors.fgMute : PTColors.liveInk,
                    letterSpacing: 1.1,
                  ),
                ),
                Text(
                  night.title,
                  maxLines: 2,
                  overflow: .ellipsis,
                  style: PTText.cardHeading.copyWith(fontSize: 19, height: 1.1, color: ink),
                ),
                Text(
                  sub ?? formatClock(placement.mine),
                  style: PTText.mono.copyWith(
                    fontSize: 11.5,
                    color: _over ? PTColors.fgMute : PTColors.canvas.withValues(alpha: 0.62),
                  ),
                ),
              ],
            ),
          ),
          stub: Padding(
            padding: const EdgeInsets.fromLTRB(6, 10, 10, 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 6,
              children: [
                _Badge(text: badge.text, color: badge.color),
                if (standing == NightStanding.accepted ||
                    standing == NightStanding.awaitingMe ||
                    standing == NightStanding.awaitingThem) ...[
                  Text(
                    'STARTS IN',
                    style: PTText.label.copyWith(
                      fontSize: 9,
                      color: PTColors.canvas.withValues(alpha: 0.55),
                    ),
                  ),
                  Text(
                    started ? 'NOW' : countdownTo(night.startsAt, now).label,
                    style: PTText.mono.copyWith(
                      fontSize: 16,
                      fontWeight: .w600,
                      color: imminent ? PTColors.liveInk : PTColors.canvas,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        // The upload's pieces come and go with its stage: they fold open and shut,
        // and the actions swap as one motion when the night's standing changes.
        PTRevealKeep(
          visible:
              !_over && (file.stage == FileStage.uploading || file.stage == FileStage.unfinished),
          child: _ProgressBar(fraction: file.fraction, warn: file.stage == FileStage.unfinished),
        ),
        PTRevealKeep(
          visible: !_over,
          child: _Attachment(night: night, mine: mine, first: _first),
        ),
        PTRevealKeep(
          visible: !_over && night.hasFile,
          child: _FileLine(file: file, mine: mine, first: _first, live: live),
        ),
        PTRevealKeep(
          visible: moved != null && !_over,
          child: Row(
            spacing: 8,
            children: [
              const Icon(BoothIcons.clock, size: 16, color: PTColors.fgDim),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: moved == null ? '' : formatMoment(moved),
                        style: const TextStyle(decoration: TextDecoration.lineThrough),
                      ),
                      TextSpan(text: ' becomes ${formatMoment(placement.mine)}'),
                    ],
                  ),
                  style: PTText.caption.copyWith(color: PTColors.fgDim, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        PTRevealKeep(
          visible: placement.lateForThem && !_over,
          child: Row(
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
        ),
        PTRevealKeep(
          visible: actions.isNotEmpty,
          child: PTPanelSwitcher(
            child: PTColumn(
              key: ValueKey(standing),
              spacing: 10,
              mainAxisSize: .min,
              children: actions,
            ),
          ),
        ),
        PTRevealKeep(
          visible: !_over && mine && file.stage == FileStage.stopped,
          child: _StoppedActions(night: night, live: live),
        ),
      ],
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
        Row(
          spacing: 10,
          children: [
            Expanded(
              child: Builder(
                builder: (buttonContext) => PTButton(
                  label: 'Add to calendar',
                  variant: .secondary,
                  icon: BoothIcons.calendar,
                  height: 44,
                  maxLines: 2,
                  onPressed: () => _calendar(buttonContext),
                ),
              ),
            ),
            Expanded(
              child: Builder(
                builder: (buttonContext) => PTButton(
                  label: 'Share .ics',
                  variant: .secondary,
                  icon: BoothIcons.share,
                  height: 44,
                  maxLines: 2,
                  onPressed: () => _shareIcs(buttonContext),
                ),
              ),
            ),
          ],
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
      NightStanding.cancelled => [
        PTButton(
          label: 'Plan another night',
          variant: .secondary,
          height: 44,
          onPressed: () => showPlanNight(context),
        ),
      ],
      NightStanding.declined => [
        Row(
          spacing: 10,
          children: [
            Expanded(
              child: PTButton(
                label: 'Suggest another time',
                variant: .secondary,
                height: 42,
                maxLines: 2,
                onPressed: () => _move(context),
              ),
            ),
            DialogTextButton(
              label: 'Cancel',
              color: PTColors.danger,
              onPressed: () => _cancel(context),
            ),
          ],
        ),
      ],
      NightStanding.done => const [],
    };
  }
}

/// What the night is for: the attached link, or "we'll choose together". Its
/// planner can change it from here for as long as the night is open.
class _Attachment extends StatelessWidget {
  const _Attachment({required this.night, required this.mine, required this.first});

  final DateNight night;
  final bool mine;
  final String first;

  @override
  Widget build(BuildContext context) {
    final link = night.hasLink;
    final file = night.hasFile;
    final text = file
        ? '${night.fileName ?? 'A file'}${night.fileSize == null ? '' : ' · ${Profile.formatBytes(night.fileSize!)}'}'
        : link
        ? (mine ? 'A YouTube link is attached.' : '$first attached a YouTube link.')
        : "We'll choose together in Our Room.";
    return Row(
      spacing: 10,
      children: [
        Icon(
          file
              ? BoothIcons.file
              : link
              ? BoothIcons.youtube
              : BoothIcons.film,
          size: 16,
          color: link || file ? PTColors.primary : PTColors.fgDim,
        ),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: .ellipsis,
            style: PTText.body.copyWith(fontSize: 13.5, color: PTColors.fgDim),
          ),
        ),
        if (mine)
          DialogTextButton(label: 'Change', onPressed: () => showChangeWatching(context, night)),
      ],
    );
  }
}

/// A thin bar under the ticket while the film is still on its way.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.fraction, required this.warn});

  final double fraction;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    return PTProgressBar(value: fraction, color: warn ? PTColors.warning : PTColors.primary);
  }
}

/// What the file is doing, in words, for whoever is looking. The planner is told
/// to keep the app open (an upload only runs while it is); the other person is
/// told how things stand and never that anything is theirs to do.
class _FileLine extends StatelessWidget {
  const _FileLine({
    required this.file,
    required this.mine,
    required this.first,
    required this.live,
  });

  final FileView file;
  final bool mine;
  final String first;
  final DateNightUpload? live;

  @override
  Widget build(BuildContext context) {
    final eta = live?.etaSeconds ?? 0;
    final minutes = (eta / 60).ceil();
    final (text, color, icon) = switch (file.stage) {
      FileStage.ready => (
        mine
            ? 'The movie is waiting. $first can already stream it.'
            : 'The movie is waiting. You can start it in Our Room.',
        PTColors.online,
        BoothIcons.check,
      ),
      FileStage.uploading => (
        mine
            ? 'Keep SyncTogether open until it says Ready.'
                  '${eta > 0 ? ' About $minutes ${minutes == 1 ? 'minute' : 'minutes'} left on this connection.' : ''}'
            : '$first is still uploading it.',
        PTColors.fgDim,
        BoothIcons.cloudUpload,
      ),
      FileStage.unfinished => (
        mine
            ? 'The room still opens. It plays for $first as soon as it lands, or pick something else.'
            : 'The room still opens. The movie plays as soon as it lands, or pick something else.',
        PTColors.warning,
        BoothIcons.clock,
      ),
      FileStage.stopped => (
        mine
            ? 'The connection dropped at ${file.percent}%. '
                  '${live != null ? 'Nothing was lost; it picks up where it left off.' : 'Choose the file again to carry on.'}'
            : 'The upload paused at ${file.percent}%. $first needs to open SyncTogether to carry on.',
        PTColors.danger,
        BoothIcons.cloudUpload,
      ),
      FileStage.none => ('', PTColors.fgDim, BoothIcons.film),
    };
    if (text.isEmpty) return const SizedBox.shrink();
    // Ready, uploading, unfinished and stopped trade places as one motion.
    return PTPanelSwitcher(
      child: Row(
        key: ValueKey(file.stage),
        crossAxisAlignment: .start,
        spacing: 8,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 16, color: color),
          ),
          Expanded(
            child: Text(text, style: PTText.caption.copyWith(color: color, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

/// A stopped upload's two ways forward: carry on, or give up on the file and
/// choose together. Only the planner sees them.
class _StoppedActions extends StatelessWidget {
  const _StoppedActions({required this.night, required this.live});

  final DateNight night;
  final DateNightUpload? live;

  Future<void> _tryAgain(BuildContext context) async {
    final uploader = DateNightUploader.instance;
    if (live != null) {
      await uploader.resume(night.id);
      return;
    }
    // No upload of ours to resume (the app was restarted): pick the file again.
    final choice = await showLocalVideoChooser(context);
    final video = choice?.video;
    if (video == null || !context.mounted) return;
    final check = fileCheckFor(
      video.sizeBytes ?? await video.uploadSource().length(),
      hasFile: true,
    );
    if (check != FileCheck.ok) {
      unawaited(video.release());
      if (context.mounted) {
        showPTSnack(
          context,
          check == FileCheck.overCap
              ? 'That file is over what your seat can share.'
              : "That file doesn't fit what's left of this week's allowance.",
          kind: .error,
        );
      }
      return;
    }
    try {
      await uploader.chooseAgain(night: night, video: video);
    } catch (e) {
      unawaited(video.release());
      if (context.mounted) {
        showPTSnack(
          context,
          e is MediaSharingException ? e.message : "Couldn't start that just now.",
          kind: .error,
        );
      }
    }
  }

  Future<void> _chooseTogether(BuildContext context) async {
    await DateNightUploader.instance.cancel(night.id);
    try {
      await PairService.instance.setNightAttachment(night.id, null);
    } catch (e) {
      if (context.mounted) {
        showPTSnack(context, "Couldn't change that just now.", kind: .error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: 10,
      children: [
        Expanded(
          child: PTButton(
            label: 'Try again',
            variant: .secondary,
            height: 42,
            onPressed: () => _tryAgain(context),
          ),
        ),
        Expanded(
          child: PTButton(
            label: 'Choose together',
            variant: .secondary,
            height: 42,
            maxLines: 2,
            onPressed: () => _chooseTogether(context),
          ),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: PTColors.canvas,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      // A long name ("WAITING FOR SAMANTHA") shrinks to fit the stub rather than
      // being cut off: the whole badge is the answer to "where does this stand".
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          text,
          maxLines: 2,
          textAlign: TextAlign.center,
          style: PTText.mono.copyWith(
            fontSize: 9.5,
            color: color,
            letterSpacing: 0.6,
            height: 1.25,
          ),
        ),
      ),
    );
  }
}
