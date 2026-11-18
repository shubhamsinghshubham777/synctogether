import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:material_ui/material_ui.dart';

import '../av/camera_facing.dart';
import '../nav.dart';
import '../profile/profile_service.dart';
import '../ui/banners.dart';
import '../ui/booth_icons.g.dart';
import '../ui/buttons.dart';
import '../ui/glass.dart';
import '../ui/loader.dart';
import '../ui/progress_bar.dart';
import '../ui/pt_theme.dart';
import '../ui/responsive.dart';
import '../ui/reveal.dart';
import 'date_night_plan.dart' show showPlanNight;
import 'pair_logic.dart';
import 'pair_models.dart';
import 'pair_page.dart';
import 'pair_screen.dart' show openOurRoom;
import 'pair_service.dart';
import 'pair_widgets.dart';
import 'pre_show_check_logic.dart';
import 'pre_show_probes.dart';

/// Whether the hub card offers the check: an accepted night, from 15 minutes
/// before until a half hour after it starts. The same window the card already
/// treats as "imminent".
bool preShowCheckOffered(DateTime now, DateNight? night) =>
    night != null && night.status == DateNightStatus.accepted && isNightImminent(now, night);

/// Opens the check for [night]: a page on a phone (like plan-night), a dialog
/// on anything wider.
Future<void> showPreShowCheck(BuildContext context) async {
  if (layoutOf(context) == PTLayout.portrait) {
    openPage(context, '/lobby/pair/pre-show');
    return;
  }
  await showGlassDialog<void>(
    context: context,
    width: 460,
    sheetOnCompact: true,
    builder: (ctx) => PreShowCheckPanel(
      onDone: () => Navigator.of(ctx).pop(),
      onLeaveForPage: (path) {
        Navigator.of(ctx).pop();
        openPage(context, path);
      },
      inDialog: true,
    ),
  );
}

/// A host's own room, from the room menu: film, sound and connection. The room's
/// own bar owns the camera and microphone, so there are no rows for them here.
Future<void> showRoomCheck(BuildContext context, {required FilmCheck Function() film}) {
  return showGlassDialog<void>(
    context: context,
    width: 460,
    sheetOnCompact: true,
    builder: (ctx) => PreShowCheckPanel(
      roomFilm: film,
      onDone: () => Navigator.of(ctx).pop(),
      onLeaveForPage: (_) => Navigator.of(ctx).pop(),
      inDialog: true,
    ),
  );
}

/// The phone page behind `/lobby/pair/pre-show`.
class PreShowCheckScreen extends StatelessWidget {
  const PreShowCheckScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PreShowCheckPanel(
      onDone: () => goBack(context),
      onLeaveForPage: (path) => openPage(context, path),
    );
  }
}

/// The sheet's whole life: its controller, the lifecycle that releases the camera
/// and microphone, the night it follows, and the rows.
class PreShowCheckPanel extends StatefulWidget {
  const PreShowCheckPanel({
    super.key,
    required this.onDone,
    required this.onLeaveForPage,
    this.roomFilm,
    this.inDialog = false,
    this.probes,
  });

  final VoidCallback onDone;

  /// Leaves the sheet for another page (`/lobby/pair/nights`).
  final void Function(String path) onLeaveForPage;

  /// Set for a host's own room: its film, and no camera or microphone rows.
  final FilmCheck Function()? roomFilm;
  final bool inDialog;

  /// For tests.
  final PreShowProbes? probes;

  @override
  State<PreShowCheckPanel> createState() => _PreShowCheckPanelState();
}

class _PreShowCheckPanelState extends State<PreShowCheckPanel> with WidgetsBindingObserver {
  late final PreShowProbes _probes = widget.probes ?? DevicePreShowProbes();
  late final PreShowCheckController _c;
  Timer? _tick;
  DateTime? _firstStart;
  DateTime? _movedTo;

  bool get _room => widget.roomFilm != null;

  DateNight? get _night {
    final svc = PairService.instance;
    final now = DateTime.now().toUtc();
    final nights = svc.nights;
    if (_firstStart != null) {
      for (final n in nights) {
        if (n.id == _nightId) return n;
      }
    }
    return featuredNight(now, nights) ?? upcomingNights(now, nights).firstOrNull;
  }

  String? _nightId;

  @override
  void initState() {
    super.initState();
    final night = _room ? null : _night;
    _nightId = night?.id;
    _firstStart = night?.startsAt;
    final partner = PairService.instance.pair?.partner.displayName.split(' ').first;
    _c = PreShowCheckController(
      probes: _probes,
      includeAv: !_room,
      partner: partner ?? 'your person',
      film: () {
        if (_room) return widget.roomFilm!();
        final n = _night;
        if (n == null) return const FilmCheck(FilmKind.none);
        final me = ProfileService.instance.profile?.id;
        return FilmCheck.forNight(n, DateTime.now().toUtc(), mine: n.proposedBy == me);
      },
    );
    WidgetsBinding.instance.addObserver(this);
    unawaited(_c.start());
    // The countdown in the header: a minute is as fine as it needs to be.
    _tick = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused || AppLifecycleState.hidden:
        unawaited(_c.background());
      case AppLifecycleState.resumed:
        unawaited(_c.foreground());
      default:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    _c.dispose();
    super.dispose();
  }

  Future<void> _act(CheckRowView row, FixAction action) async {
    if (action.id == 'nights') {
      widget.onLeaveForPage('/lobby/pair/nights');
      return;
    }
    await _c.act(row.id, action.id);
  }

  Future<void> _takeSeats() async {
    await _c.releaseDevices();
    if (!mounted) return;
    if (widget.inDialog) widget.onDone();
    await openOurRoom(context);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_c, PairService.instance]),
      builder: (context, _) {
        final night = _room ? null : _night;
        if (!_room && night != null) _noticeMove(night);
        final children = _children(context, night);
        if (widget.inDialog) {
          return Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            spacing: 14,
            children: [Flexible(child: SingleChildScrollView(child: _column(children)))],
          );
        }
        return PairPage(title: _room ? 'Room check' : 'Pre-show check', children: children);
      },
    );
  }

  Widget _column(List<Widget> children) =>
      Column(crossAxisAlignment: .stretch, spacing: 14, children: children);

  /// Remembers that the night moved while the sheet was open, to say so once.
  void _noticeMove(DateNight night) {
    final first = _firstStart;
    if (first != null && night.startsAt != first && _movedTo != night.startsAt) {
      _movedTo = night.startsAt;
    }
  }

  List<Widget> _children(BuildContext context, DateNight? night) {
    final partner = _c.partner;
    final now = DateTime.now().toUtc();

    if (!_room &&
        (night == null ||
            night.status == DateNightStatus.cancelled ||
            night.status == DateNightStatus.declined)) {
      return [
        PairKicker(
          night == null ? 'No night on' : '$partner cancelled tonight',
          color: PTColors.danger,
        ),
        Text(
          night == null ? 'Nothing to check' : '${night.title} is off',
          style: PTText.screenTitle.copyWith(fontSize: 28),
        ),
        Text(
          night == null
              ? 'There is no accepted date night coming up. Plan one and the check shows here from fifteen minutes before.'
              : '$partner cancelled this date night. Your check is cleared and nothing is on for tonight.',
          style: PTText.body.copyWith(color: PTColors.fgSoft, height: 1.5),
        ),
        PTButton(
          label: 'Plan another night',
          onPressed: () {
            widget.onDone();
            unawaited(showPlanNight(context));
          },
        ),
        PTButton(label: 'Back', variant: .secondary, onPressed: widget.onDone),
        const PairNote('The camera and microphone have been released.', center: true),
      ];
    }

    final until = night?.startsAt.difference(now);
    final started = until != null && until.isNegative;
    final soon = until != null && !started && until <= const Duration(minutes: 2);
    final kicker = _room
        ? 'Room menu · any time'
        : started
        ? 'The night has started'
        : soon
        ? 'Starts in ${until.inMinutes} min ${until.inSeconds % 60} s'
        : 'Tonight · ${formatClock(night!.startsAt.toLocal())} · starts in ${_minutes(until!)}';

    return [
      PairKicker(kicker, color: soon || started ? PTColors.danger : PTColors.primary),
      // The page carries its own title; the dialog needs one.
      if (widget.inDialog)
        Text(
          _room ? 'Room check' : 'Pre-show check',
          style: PTText.screenTitle.copyWith(fontSize: 28),
        ),
      if (!_room)
        Text(
          '${night!.title} with $partner. A minute now saves the first ten of the film.',
          style: PTText.body.copyWith(color: PTColors.fgSoft, height: 1.5),
        ),
      PTRevealKeep(
        visible: _movedTo != null,
        child: PTBanner(
          kind: .info,
          icon: BoothIcons.film,
          title: night == null || _movedTo == null
              ? 'The night moved'
              : '$partner moved the night to ${formatClock(_movedTo!.toLocal())}',
          subtitle: "We've updated the countdown. Your check carries over.",
          onDismiss: () => setState(() => _movedTo = null),
        ),
      ),
      Column(
        children: [
          for (final row in _c.rows)
            _RowTile(
              key: ValueKey(row.id),
              row: row,
              controller: _c,
              preview: _preview,
              onAction: (a) => _act(row, a),
            ),
        ],
      ),
      const SizedBox(height: 2),
      if (!_c.offline)
        PTButton(
          label: _room
              ? 'Done'
              : _c.clean
              ? (started || soon ? 'Take our seats now' : 'Take our seats')
              : 'Take our seats anyway',
          variant: _room || !_c.clean ? .secondary : .primary,
          onPressed: _room ? widget.onDone : _takeSeats,
        ),
      if (!_room) PairNote('Nothing here turns your camera on for $partner yet.', center: true),
    ];
  }

  String _minutes(Duration d) {
    final m = d.inMinutes;
    if (m >= 120) return '${m ~/ 60} h ${m % 60} min';
    return '${m < 1 ? 1 : m} min';
  }

  Widget _preview() {
    final probes = _probes;
    final track = probes is DevicePreShowProbes ? probes.track : null;
    if (track == null) return const SizedBox.shrink();
    return lk.VideoTrackRenderer(
      track,
      fit: .cover,
      mirrorMode:
          shouldMirrorCamera(
            facingMode: track.currentOptions is lk.CameraCaptureOptions
                ? (track.currentOptions as lk.CameraCaptureOptions).cameraPosition.name
                : null,
          )
          ? .mirror
          : .off,
    );
  }
}

// ---------------------------------------------------------------------------
// One row
// ---------------------------------------------------------------------------

class _RowTile extends StatelessWidget {
  const _RowTile({
    super.key,
    required this.row,
    required this.controller,
    required this.preview,
    required this.onAction,
  });

  final CheckRowView row;
  final PreShowCheckController controller;
  final Widget Function() preview;
  final void Function(FixAction action) onAction;

  IconData get _icon => switch (row.id) {
    CheckId.film => BoothIcons.film,
    CheckId.camera =>
      row.tone == RowTone.ok || row.tone == RowTone.busy || row.tone == RowTone.idle
          ? BoothIcons.videocam
          : BoothIcons.videocamOff,
    CheckId.mic => row.tone == RowTone.bad ? BoothIcons.micOff : BoothIcons.mic,
    CheckId.sound => row.tone == RowTone.bad ? BoothIcons.volumeOff : BoothIcons.volume,
    CheckId.connection => BoothIcons.globe,
  };

  Color get _toneColor => switch (row.tone) {
    RowTone.ok => PTColors.online,
    RowTone.warn => PTColors.warning,
    RowTone.bad => PTColors.danger,
    _ => PTColors.fgDim,
  };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '${row.title}. ${row.subtitle}',
      child: Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: PTColors.rail)),
        ),
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                spacing: 12,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: PTColors.glassBase,
                      border: Border.all(color: PTColors.rail),
                      borderRadius: BorderRadius.circular(PTRadius.control),
                    ),
                    child: Icon(_icon, size: 18, color: PTColors.fgSoft),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: .start,
                      children: [
                        Text(row.title, style: PTText.body.copyWith(fontWeight: .w600)),
                        Text(
                          row.subtitle,
                          style: PTText.body.copyWith(fontSize: 13, color: PTColors.fgSoft),
                        ),
                      ],
                    ),
                  ),
                  _trailing(context),
                  _status(),
                ],
              ),
            ),
            PTRevealKeep(visible: row.fix != null || row.actions.isNotEmpty, child: _card()),
          ],
        ),
      ),
    );
  }

  Widget _trailing(BuildContext context) => switch (row.trail) {
    RowTrail.none => const SizedBox.shrink(),
    RowTrail.thumb => ClipRRect(
      borderRadius: BorderRadius.circular(PTRadius.control),
      child: SizedBox(width: 58, height: 40, child: preview()),
    ),
    RowTrail.meter => _Meter(levels: controller.micLevels, active: row.tone != RowTone.idle),
    RowTrail.progress => SizedBox(
      width: 46,
      child: PTProgressBar(
        value: row.progress ?? 0,
        color: row.tone == RowTone.bad ? PTColors.danger : PTColors.warning,
      ),
    ),
    RowTrail.playButton => PTButton(
      label: 'Play',
      variant: .secondary,
      height: 34,
      expand: false,
      onPressed: () => onAction(const FixAction('play', 'Play')),
    ),
  };

  Widget _status() => SizedBox(
    width: 20,
    child: Center(
      child: switch (row.tone) {
        RowTone.busy => const PTLoader(size: 16, color: PTColors.warning),
        RowTone.ok => Icon(BoothIcons.check, size: 18, color: _toneColor),
        RowTone.warn || RowTone.bad => Icon(BoothIcons.alert, size: 18, color: _toneColor),
        RowTone.idle => Icon(BoothIcons.moreHoriz, size: 18, color: _toneColor),
      },
    ),
  );

  Widget _card() => Padding(
    padding: const EdgeInsets.only(left: 48, bottom: 12),
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PTColors.glassBase,
        border: Border.all(color: PTColors.rail),
        borderRadius: BorderRadius.circular(PTRadius.panel),
      ),
      child: Column(
        crossAxisAlignment: .start,
        spacing: 10,
        children: [
          if (row.fix != null)
            Text(
              row.fix!,
              style: PTText.body.copyWith(fontSize: 13, color: PTColors.fgSoft, height: 1.5),
            ),
          if (row.actions.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in row.actions)
                  PTButton(
                    label: a.label,
                    variant: a.primary ? .primary : .secondary,
                    height: 36,
                    expand: false,
                    onPressed: () => onAction(a),
                  ),
              ],
            ),
        ],
      ),
    ),
  );
}

/// Seven segments, lit from the left as the microphone level rises. Reads its own
/// notifier so the ~30 Hz level never rebuilds the rest of the sheet.
class _Meter extends StatelessWidget {
  const _Meter({required this.levels, required this.active});

  final ValueListenable<List<double>> levels;
  final bool active;

  static const _bars = 7;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<double>>(
      valueListenable: levels,
      builder: (context, values, _) {
        final peak = values.isEmpty ? 0.0 : values.reduce((a, b) => a > b ? a : b);
        final lit = (peak * _bars).round();
        return Row(
          mainAxisSize: .min,
          crossAxisAlignment: .end,
          spacing: 3,
          children: [
            for (var i = 0; i < _bars; i++)
              Container(
                width: 4,
                height: 6.0 + i * 2,
                decoration: BoxDecoration(
                  color: active && i < lit ? PTColors.online : PTColors.rail,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
          ],
        );
      },
    );
  }
}
