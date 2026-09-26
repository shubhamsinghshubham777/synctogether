import 'package:flutter/material.dart';
import '../../ui/booth_icons.g.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/inputs.dart';
import 'package:synctogether/ui/pt_motion.dart';
import 'package:synctogether/ui/pt_theme.dart';

class RoomControlBarActions {
  const RoomControlBarActions({
    required this.onPlayPause,
    required this.onSeek,
    required this.onSkip,
    required this.onMicToggle,
    required this.onCamToggle,
    this.onCamLocked,
    this.onMicDeviceSelect,
    this.onCamDeviceSelect,
    this.onAudioOutputSelect,
    this.audioOutputDisabledTooltip,
    required this.onAudioTracks,
    required this.onSubtitles,
    required this.onSwitchSource,
    required this.onOpenFile,
    this.openFileTooltip,
    required this.onVolume,
    required this.onToggleMute,
    this.onReact,
    this.onHideControls,
    this.onFullscreenToggle,
  });

  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<Duration> onSkip;
  final ValueChanged<bool> onMicToggle;
  final ValueChanged<bool> onCamToggle;
  final VoidCallback? onCamLocked;
  final void Function(BuildContext context)? onMicDeviceSelect;
  final void Function(BuildContext context)? onCamDeviceSelect;
  final void Function(BuildContext context)? onAudioOutputSelect;
  final String? audioOutputDisabledTooltip;
  final VoidCallback? onAudioTracks;
  final VoidCallback? onSubtitles;

  /// Null for members - choosing what the room watches is host-only (D1), and
  /// omitting the callback is how this kit hides an action.
  final VoidCallback? onSwitchSource;
  final VoidCallback? onOpenFile;

  /// Members get "Locate your copy of `<name>`" - their picker exists to find
  /// their own copy of the room's file, never to change what the room watches.
  final String? openFileTooltip;
  final ValueChanged<double> onVolume;
  final VoidCallback onToggleMute;
  final VoidCallback? onReact;
  final VoidCallback? onHideControls;
  final VoidCallback? onFullscreenToggle;
}

class RoomControlBar extends StatefulWidget {
  const RoomControlBar({
    super.key,
    required this.playing,
    required this.position,
    required this.duration,
    this.bufferedPosition,
    required this.volume,
    required this.micOn,
    required this.camOn,
    required this.avAvailable,
    this.camAvailable = true,
    required this.actions,
    this.compact = false,
    this.docked = false,
    this.fullscreen = false,
    this.reactOpen = false,
    this.transportEnabled = true,
    this.transportHint,
  });

  final bool playing;
  final Duration position;
  final Duration duration;
  final Duration? bufferedPosition;
  final double volume;
  final bool micOn;
  final bool camOn;
  final bool avAvailable;
  final bool camAvailable;
  final RoomControlBarActions actions;
  final bool compact;

  /// Flat, full-width, in the layout flow (the theatre layout under the
  /// video, the phone room below it) rather than a floating panel over it.
  /// With [compact] it keeps the compact rows and only loses the shell.
  final bool docked;
  final bool fullscreen;
  final bool reactOpen;

  /// Affordance only - the real enforcement lives at RoomScreen's
  /// `_playPause`/`_seek`/`_skip` choke points, which keyboard shortcuts and
  /// double-tap skip zones also go through.
  final bool transportEnabled;

  /// Why the transport is disabled, shown next to the controls.
  final String? transportHint;

  @override
  State<RoomControlBar> createState() => _RoomControlBarState();
}

/// Where the playhead should be drawn [sinceReport] after the player last
/// reported [reported], while playing.
///
/// The player reports its position a few times a second; drawing only those
/// values makes the fill tick forward in visible steps. Between reports the
/// playhead advances on the wall clock, capped at [kMaxExtrapolation] past the
/// report so a stalled player (which keeps reporting `playing`) freezes rather
/// than running away, and never past [duration].
@visibleForTesting
Duration extrapolatedPlayhead({
  required Duration reported,
  required Duration sinceReport,
  required Duration duration,
}) {
  final ahead = sinceReport > kMaxExtrapolation ? kMaxExtrapolation : sinceReport;
  final at = reported + ahead;
  return duration > Duration.zero && at > duration ? duration : at;
}

/// How far the drawn playhead may run ahead of the last report.
const kMaxExtrapolation = Duration(milliseconds: 1200);

class _RoomControlBarState extends State<RoomControlBar> with SingleTickerProviderStateMixin {
  /// The playhead as drawn. Separate from `widget.position` so the per-frame
  /// advance rebuilds only the slider and readout, never the whole bar.
  late final ValueNotifier<Duration> _playhead = ValueNotifier(widget.position);
  late final Ticker _ticker = createTicker(_onTick);
  Duration _reportedAt = Duration.zero;
  Duration _lastTick = Duration.zero;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(RoomControlBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.position != oldWidget.position) {
      _reportedAt = _ticker.isActive ? _lastTick : Duration.zero;
      // A report slightly behind what we drew is the player catching up with
      // our extrapolation - holding the drawn value hides a backwards twitch.
      // Anything larger is a seek and snaps.
      final drawn = _playhead.value;
      final behind = drawn - widget.position;
      if (!(widget.playing && behind > Duration.zero && behind < kMaxExtrapolation)) {
        _playhead.value = widget.position;
      }
    }
    if (widget.playing != oldWidget.playing) {
      if (!widget.playing) _playhead.value = widget.position;
      _syncTicker();
    }
  }

  void _syncTicker() {
    // The ticker runs only while playing: a paused room costs no frames.
    final run = widget.playing && widget.duration > Duration.zero;
    if (run && !_ticker.isActive) {
      _reportedAt = Duration.zero;
      _lastTick = Duration.zero;
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    _lastTick = elapsed;
    final next = extrapolatedPlayhead(
      reported: widget.position,
      sinceReport: elapsed - _reportedAt,
      duration: widget.duration,
    );
    if (next > _playhead.value) _playhead.value = next;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _playhead.dispose();
    super.dispose();
  }

  /// While scrubbing, the bar previews this value locally; the actual seek
  /// (and its room-wide broadcast) fires once, on release.
  double? _dragValue;

  /// Normalized 0–1 position under a hovering cursor (desktop only); drives the
  /// seek-preview chip. The chip escapes the glass panel's clip via [_sliderLink].
  double? _hoverValue;
  final _sliderLink = LayerLink();

  double _progressOf(Duration position) => widget.duration.inMilliseconds == 0
      ? 0
      : (position.inMilliseconds / widget.duration.inMilliseconds).clamp(0.0, 1.0);

  void _endScrub(double v) {
    setState(() => _dragValue = null);
    widget.actions.onSeek(Duration(milliseconds: (v * widget.duration.inMilliseconds).round()));
  }

  double? get _bufferedProgress {
    final pos = widget.bufferedPosition;
    if (pos == null || widget.duration.inMilliseconds <= 0) return null;
    return (pos.inMilliseconds / widget.duration.inMilliseconds).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact;
    final drag = _dragValue;
    final hover = _hoverValue;
    final docked = widget.docked;
    Widget shell(Widget child) => docked
        ? DecoratedBox(
            decoration: const BoxDecoration(
              color: PTColors.canvas,
              border: Border(top: BorderSide(color: PTColors.aisle)),
            ),
            child: Padding(
              padding: compact
                  ? const EdgeInsets.fromLTRB(14, 10, 14, 10)
                  : const EdgeInsets.fromLTRB(24, 12, 20, 12),
              child: child,
            ),
          )
        : GlassPanel(
            radius: compact ? 20 : 24,
            opacity: 0.6,
            blur: 32,
            baseColor: PTColors.surfaceBase,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 16 : 26,
              vertical: compact ? 14 : 18,
            ),
            child: child,
          );
    final panel = shell(
      // Two nested columns on purpose: the hint sits *outside* the spaced
      // column so its collapsed state costs nothing. As a spaced sibling, an
      // empty hint would still leave a row gap behind it.
      Column(
        mainAxisSize: .min,
        children: [
          Column(
            mainAxisSize: .min,
            spacing: docked ? 8 : (compact ? 10 : 14),
            children: [
              Row(
                spacing: compact ? 10 : 16,
                children: [
                  ValueListenableBuilder(
                    valueListenable: _playhead,
                    builder: (context, playhead, _) => _timeReadout(
                      context,
                      _fmt(drag == null ? playhead : widget.duration * drag),
                      compact: compact,
                    ),
                  ),
                  Expanded(
                    child: CompositedTransformTarget(
                      link: _sliderLink,
                      // Its own layer: the playhead repaints every frame while
                      // playing, and nothing else in the bar should.
                      child: RepaintBoundary(
                        child: ValueListenableBuilder(
                          valueListenable: _playhead,
                          builder: (context, playhead, _) => PTSlider(
                            value: drag ?? _progressOf(playhead),
                            bufferedValue: _bufferedProgress,
                            trackHeight: compact ? 4 : 5,
                            thumbRadius: compact ? 6 : 7,
                            enabled: widget.transportEnabled,
                            onChanged: (v) => setState(() => _dragValue = v),
                            onChangeEnd: _endScrub,
                            onHover: (v) => setState(() => _hoverValue = v),
                          ),
                        ),
                      ),
                    ),
                  ),
                  _timeReadout(
                    context,
                    _fmt(widget.duration),
                    compact: compact,
                    color: PTColors.white(0.5),
                  ),
                ],
              ),
              compact
                  ? _compactRow()
                  : docked
                  ? _dockedRow()
                  : _fullRow(),
            ],
          ),
          // Grows and collapses rather than appearing: the gate can flap, and
          // a bar that jumps a row height each time is worse than the hint.
          AnimatedSize(
            duration: PTMotion.functional(context, PTMotion.state),
            curve: PTMotion.enter,
            alignment: .topCenter,
            child: !widget.transportEnabled && widget.transportHint != null
                ? Padding(
                    padding: EdgeInsets.only(top: compact ? 10 : 14),
                    child: Text(
                      widget.transportHint!,
                      textAlign: .center,
                      // Media names get long; the overlay is where the full name is
                      // readable, this is only a nudge.
                      maxLines: 2,
                      overflow: .ellipsis,
                      style: PTText.finePrint.copyWith(color: PTColors.white(0.55)),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );

    // The preview chip must escape the panel's ClipRRect, so it rides a
    // CompositedTransformFollower in an unclipped outer Stack rather than
    // living inside the panel. Hidden while scrubbing (the position text
    // already previews the drag) and until a duration is known.
    final showChip = hover != null && drag == null && widget.duration.inMilliseconds > 0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        panel,
        if (showChip)
          Positioned(
            left: 0,
            top: 0,
            child: CompositedTransformFollower(
              link: _sliderLink,
              targetAnchor: Alignment.topLeft,
              followerAnchor: Alignment.bottomLeft,
              offset: Offset(hover * (_sliderLink.leaderSize?.width ?? 0), -8),
              child: FractionalTranslation(
                translation: const Offset(-0.5, 0),
                child: IgnorePointer(
                  // Rises into place on the first hover. It tracks the cursor
                  // instantly after that - the follower offset is not animated,
                  // so the chip never lags the pointer.
                  child: PTEntrance(
                    duration: PTMotion.hover,
                    offset: 6,
                    child: _previewChip(widget.duration * hover),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _previewChip(Duration position) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: PTColors.glassBase,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: PTColors.white(0.14)),
        boxShadow: [
          BoxShadow(color: PTColors.black(0.45), blurRadius: 14, offset: const Offset(0, 5)),
        ],
      ),
      child: Text(_fmt(position), style: PTText.mono.copyWith(fontSize: 12)),
    );
  }

  /// Mic, camera (or its Premium lock) and the reaction toggle.
  List<Widget> _avButtons() {
    final actions = widget.actions;
    return [
      if (widget.avAvailable) ...[
        _SplitDeviceButton(
          height: 42,
          onDropdown: actions.onMicDeviceSelect,
          dropdownTooltip: 'Select microphone',
          mainButton: PTIconButton(
            icon: BoothIcons.mic,
            active: widget.micOn,
            glass: false,
            borderRadius: BorderRadius.circular(PTRadius.control),
            size: 42,
            tooltip: widget.micOn ? 'Mute mic (D)' : 'Mic on (D)',
            onPressed: () => actions.onMicToggle(!widget.micOn),
          ),
        ),
        if (widget.camAvailable)
          _SplitDeviceButton(
            height: 42,
            onDropdown: actions.onCamDeviceSelect,
            dropdownTooltip: 'Select camera',
            mainButton: PTIconButton(
              icon: BoothIcons.videocam,
              active: widget.camOn,
              glass: false,
              borderRadius: BorderRadius.circular(PTRadius.control),
              size: 42,
              tooltip: widget.camOn ? 'Camera off (E)' : 'Camera on (E)',
              onPressed: () => actions.onCamToggle(!widget.camOn),
            ),
          )
        else if (actions.onCamLocked != null)
          Tooltip(
            message: 'Video facecams (Premium)',
            child: Stack(
              alignment: Alignment.center,
              children: [
                PTIconButton(
                  icon: BoothIcons.videocamOff,
                  active: false,
                  glass: false,
                  borderRadius: BorderRadius.circular(PTRadius.control),
                  size: 42,
                  iconSize: 20,
                  onPressed: actions.onCamLocked,
                ),
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: PTColors.raised,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: PTColors.accentBorder.withValues(alpha: 0.5),
                        width: 1,
                      ),
                    ),
                    child: const Icon(
                      BoothIcons.lock,
                      size: 9,
                      fill: 1,
                      color: PTColors.textAccent,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
      if (actions.onReact != null)
        PTIconButton(
          icon: BoothIcons.react,
          active: widget.reactOpen,
          glass: false,
          borderRadius: BorderRadius.circular(PTRadius.control),
          size: 42,
          iconSize: 22,
          tooltip: widget.reactOpen ? 'Close reactions (R)' : 'React (R)',
          onPressed: actions.onReact,
        ),
    ];
  }

  /// The local file's audio and subtitle choosers.
  List<Widget> _trackButtons() {
    final actions = widget.actions;
    return [
      if (actions.onAudioTracks != null)
        PTIconButton(
          icon: Symbols.audiotrack_rounded,
          glass: false,
          borderRadius: BorderRadius.circular(PTRadius.control),
          size: 42,
          iconSize: 22,
          tooltip: 'Audio track',
          onPressed: actions.onAudioTracks,
        ),
      if (actions.onSubtitles != null)
        PTIconButton(
          icon: BoothIcons.subtitles,
          glass: false,
          borderRadius: BorderRadius.circular(PTRadius.control),
          size: 42,
          iconSize: 22,
          tooltip: 'Subtitles',
          onPressed: actions.onSubtitles,
        ),
    ];
  }

  /// -10 s, play/pause, +10 s.
  List<Widget> _transportButtons() {
    final actions = widget.actions;
    return [
      PTIconButton(
        icon: BoothIcons.replay,
        glass: false,
        iconSize: 26,
        spinOnPress: -40,
        onPressed: widget.transportEnabled
            ? () => actions.onSkip(const Duration(seconds: -10))
            : null,
      ),
      PTPlayButton(
        playing: widget.playing,
        onPressed: widget.transportEnabled ? actions.onPlayPause : null,
      ),
      PTIconButton(
        icon: BoothIcons.forward,
        glass: false,
        iconSize: 26,
        spinOnPress: 40,
        onPressed: widget.transportEnabled
            ? () => actions.onSkip(const Duration(seconds: 10))
            : null,
      ),
    ];
  }

  /// Source and file pickers, volume (slider optional), hide and fullscreen.
  List<Widget> _outputButtons({bool slider = true}) {
    final actions = widget.actions;
    return [
      if (actions.onSwitchSource != null)
        PTIconButton(
          icon: BoothIcons.youtube,
          glass: false,
          borderRadius: BorderRadius.circular(PTRadius.control),
          size: 42,
          iconSize: 22,
          tooltip: 'Switch source',
          onPressed: actions.onSwitchSource,
        ),
      if (actions.onOpenFile != null)
        PTIconButton(
          icon: BoothIcons.file,
          glass: false,
          borderRadius: BorderRadius.circular(PTRadius.control),
          size: 42,
          iconSize: 22,
          tooltip: actions.openFileTooltip ?? 'Open file',
          onPressed: actions.onOpenFile,
        ),
      Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Row(
          spacing: 4,
          children: [
            _SplitDeviceButton(
              height: 36,
              showDropdown:
                  actions.onAudioOutputSelect != null || actions.audioOutputDisabledTooltip != null,
              onDropdown: actions.onAudioOutputSelect,
              dropdownTooltip: 'Select audio output',
              disabledDropdownTooltip: actions.audioOutputDisabledTooltip,
              mainButton: PTIconButton(
                icon: widget.volume == 0 ? BoothIcons.volumeOff : BoothIcons.volume,
                glass: false,
                size: 36,
                iconSize: 20,
                tooltip: widget.volume == 0 ? 'Unmute (M)' : 'Mute (M)',
                onPressed: actions.onToggleMute,
              ),
            ),
            if (slider)
              SizedBox(
                width: 110,
                child: PTSlider(
                  value: widget.volume,
                  trackHeight: 4,
                  thumbRadius: 5.5,
                  onChanged: actions.onVolume,
                ),
              ),
          ],
        ),
      ),
      if (actions.onHideControls != null)
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: PTIconButton(
            icon: BoothIcons.chevronDown,
            glass: false,
            borderRadius: BorderRadius.circular(PTRadius.control),
            size: 36,
            iconSize: 22,
            tooltip: 'Hide controls (H)',
            onPressed: actions.onHideControls,
          ),
        ),
      if (actions.onFullscreenToggle != null)
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: PTIconButton(
            icon: widget.fullscreen ? BoothIcons.fullscreenExit : BoothIcons.fullscreen,
            glass: false,
            borderRadius: BorderRadius.circular(PTRadius.control),
            size: 36,
            iconSize: 22,
            tooltip: widget.fullscreen ? 'Exit fullscreen (F)' : 'Fullscreen (F)',
            onPressed: actions.onFullscreenToggle,
          ),
        ),
    ];
  }

  Widget _groupDivider() => Container(
    width: 1,
    height: 26,
    margin: const EdgeInsets.symmetric(horizontal: 4),
    color: PTColors.rail,
  );

  Widget _fullRow() {
    final av = _avButtons();
    final tracks = _trackButtons();
    return Row(
      children: [
        Row(
          spacing: 8,
          children: [...av, if (av.isNotEmpty && tracks.isNotEmpty) _groupDivider(), ...tracks],
        ),
        Expanded(
          // Icon-only: shrinks rather than overflows when touch targets (44px
          // on a tablet) or extra actions crowd the row; 1:1 otherwise.
          child: FittedBox(
            fit: .scaleDown,
            child: Row(mainAxisSize: .min, spacing: 20, children: _transportButtons()),
          ),
        ),
        Row(spacing: 8, children: _outputButtons()),
      ],
    );
  }

  /// The theatre layout's bar: flat under the video, transport first (where
  /// the eye lands leaving the picture), talk and react beside it, and what
  /// you watch *with* - tracks, source, volume, fullscreen - on the far side.
  /// The volume slider is the first thing to go when the row runs short.
  Widget _dockedRow() {
    final av = _avButtons();
    return LayoutBuilder(
      builder: (context, box) {
        final slider = box.maxWidth >= 820;
        return Row(
          children: [
            Row(mainAxisSize: .min, spacing: 12, children: _transportButtons()),
            if (av.isNotEmpty) ...[
              const SizedBox(width: 8),
              _groupDivider(),
              const SizedBox(width: 8),
            ],
            Row(mainAxisSize: .min, spacing: 8, children: av),
            const Spacer(),
            Flexible(
              flex: 0,
              child: FittedBox(
                fit: .scaleDown,
                child: Row(
                  mainAxisSize: .min,
                  spacing: 8,
                  children: [
                    ..._trackButtons(),
                    ..._outputButtons(slider: slider),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _compactRow() {
    final actions = widget.actions;
    // Every fixed button is a 44px PTIconButton; the transport cluster is
    // 168 at 1:1. When everything fits, one row. When it doesn't, the source
    // controls drop to a second row instead of the whole row scaling its
    // touch targets down (the old FittedBox made a 412 phone's play button
    // a sliver). Only a slot too narrow even for the top row still scales.
    const transport = 172.0;
    final rightCount = [
      actions.onSwitchSource,
      actions.onOpenFile,
      actions.onAudioTracks,
      actions.onSubtitles,
      actions.onHideControls,
      actions.onFullscreenToggle,
    ].where((a) => a != null).length;
    final leftWidth =
        (widget.avAvailable
            ? 44.0 + (widget.camAvailable || actions.onCamLocked != null ? 48.0 : 0.0)
            : 0.0) +
        (actions.onReact != null ? 44.0 : 0.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth) return _compactRowContent();
        final width = constraints.maxWidth;
        // Nothing right of the transport (secondary controls in the menu):
        // mirror the left group so the play button sits dead centre.
        final canBalance = width - 2 * leftWidth >= transport;
        if (rightCount == 0) {
          return _compactRowContent(balance: canBalance ? leftWidth : 0);
        }
        if (width >= leftWidth + transport + rightCount * 44.0) return _compactRowContent();
        if (width >= leftWidth + transport) {
          return _compactTwoRows(balance: canBalance ? leftWidth : 0);
        }
        final min = leftWidth + transport;
        return FittedBox(
          fit: .scaleDown,
          child: SizedBox(width: min, child: _compactTwoRows(balance: 0)),
        );
      },
    );
  }

  List<Widget> _compactLeft() {
    final actions = widget.actions;
    return [
      if (widget.avAvailable)
        Row(
          // Tight: on a 320 phone this row carries every source control too.
          spacing: 4,
          children: [
            PTIconButton(
              icon: BoothIcons.mic,
              active: widget.micOn,
              glass: false,
              borderRadius: BorderRadius.circular(PTRadius.control),
              iconSize: 20,
              tooltip: widget.micOn ? 'Mute mic (D)' : 'Mic on (D)',
              onPressed: () => actions.onMicToggle(!widget.micOn),
            ),
            if (widget.camAvailable)
              PTIconButton(
                icon: BoothIcons.videocam,
                active: widget.camOn,
                glass: false,
                borderRadius: BorderRadius.circular(PTRadius.control),
                iconSize: 20,
                tooltip: widget.camOn ? 'Camera off (E)' : 'Camera on (E)',
                onPressed: () => actions.onCamToggle(!widget.camOn),
              )
            else if (actions.onCamLocked != null)
              Tooltip(
                message: 'Video facecams (Premium)',
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PTIconButton(
                      icon: BoothIcons.videocamOff,
                      active: false,
                      glass: false,
                      borderRadius: BorderRadius.circular(PTRadius.control),
                      iconSize: 18,
                      onPressed: actions.onCamLocked,
                    ),
                    Positioned(
                      bottom: 2,
                      right: 2,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: PTColors.raised,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: PTColors.accentBorder.withValues(alpha: 0.5),
                            width: 1,
                          ),
                        ),
                        child: const Icon(
                          BoothIcons.lock,
                          size: 8,
                          fill: 1,
                          color: PTColors.textAccent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      if (actions.onReact != null)
        PTIconButton(
          icon: BoothIcons.react,
          active: widget.reactOpen,
          glass: false,
          borderRadius: BorderRadius.circular(PTRadius.control),
          iconSize: 21,
          tooltip: widget.reactOpen ? 'Close reactions (R)' : 'React (R)',
          onPressed: actions.onReact,
        ),
    ];
  }

  List<Widget> _compactRight() {
    final actions = widget.actions;
    return [
      // Source controls belong here too - this row is what portrait,
      // landscape and any narrow desktop window actually render, so leaving
      // them out of it left those layouts with no way to pick anything.
      if (actions.onSwitchSource != null)
        PTIconButton(
          icon: BoothIcons.youtube,
          glass: false,
          borderRadius: BorderRadius.circular(PTRadius.control),
          iconSize: 21,
          tooltip: 'Switch source',
          onPressed: actions.onSwitchSource,
        ),
      if (actions.onOpenFile != null)
        PTIconButton(
          icon: BoothIcons.file,
          glass: false,
          borderRadius: BorderRadius.circular(PTRadius.control),
          iconSize: 21,
          tooltip: actions.openFileTooltip ?? 'Open file',
          onPressed: actions.onOpenFile,
        ),
      if (actions.onAudioTracks != null)
        PTIconButton(
          icon: Symbols.audiotrack_rounded,
          glass: false,
          borderRadius: BorderRadius.circular(PTRadius.control),
          iconSize: 21,
          tooltip: 'Audio track',
          onPressed: actions.onAudioTracks,
        ),
      if (actions.onSubtitles != null)
        PTIconButton(
          icon: BoothIcons.subtitles,
          glass: false,
          borderRadius: BorderRadius.circular(PTRadius.control),
          iconSize: 21,
          tooltip: 'Subtitles',
          onPressed: actions.onSubtitles,
        ),
      if (actions.onHideControls != null)
        PTIconButton(
          icon: BoothIcons.chevronDown,
          glass: false,
          borderRadius: BorderRadius.circular(PTRadius.control),
          iconSize: 21,
          tooltip: 'Hide controls (H)',
          onPressed: actions.onHideControls,
        ),
      if (actions.onFullscreenToggle != null)
        PTIconButton(
          icon: widget.fullscreen ? BoothIcons.fullscreenExit : BoothIcons.fullscreen,
          glass: false,
          borderRadius: BorderRadius.circular(PTRadius.control),
          iconSize: 21,
          tooltip: widget.fullscreen ? 'Exit fullscreen (F)' : 'Fullscreen (F)',
          onPressed: actions.onFullscreenToggle,
        ),
    ];
  }

  Widget _compactRowContent({double balance = 0, bool includeRight = true}) {
    final actions = widget.actions;
    return Row(
      children: [
        ..._compactLeft(),
        Expanded(
          // Icon-only, so it shrinks rather than overflows when a narrow phone
          // also carries every source control; at normal widths it is 1:1.
          child: FittedBox(
            fit: .scaleDown,
            child: Row(
              mainAxisSize: .min,
              spacing: 14,
              children: [
                PTIconButton(
                  icon: BoothIcons.replay,
                  glass: false,
                  iconSize: 24,
                  spinOnPress: -40,
                  onPressed: widget.transportEnabled
                      ? () => actions.onSkip(const Duration(seconds: -10))
                      : null,
                ),
                PTPlayButton(
                  playing: widget.playing,
                  size: 52,
                  onPressed: widget.transportEnabled ? actions.onPlayPause : null,
                ),
                PTIconButton(
                  icon: BoothIcons.forward,
                  glass: false,
                  iconSize: 24,
                  spinOnPress: 40,
                  onPressed: widget.transportEnabled
                      ? () => actions.onSkip(const Duration(seconds: 10))
                      : null,
                ),
              ],
            ),
          ),
        ),
        if (balance > 0) SizedBox(width: balance),
        if (includeRight) ..._compactRight(),
      ],
    );
  }

  /// Too narrow for one row at 1:1: transport (with mic/cam/react) keeps the
  /// top row, and the source controls move to an evenly spaced row beneath -
  /// rather than the whole bar scaling its touch targets down.
  Widget _compactTwoRows({required double balance}) {
    return Column(
      mainAxisSize: .min,
      spacing: 4,
      children: [
        _compactRowContent(balance: balance, includeRight: false),
        SizedBox(
          width: double.infinity,
          child: Wrap(alignment: WrapAlignment.spaceEvenly, children: _compactRight()),
        ),
      ],
    );
  }

  /// Sized by its content, not a fixed box - but capped at 1.3x text scale:
  /// at 2x two `1:02:03` readouts would leave the scrubber no width at all on a
  /// phone, and the scrubber is the control. Tabular figures stop the readout
  /// jittering as digits tick (JetBrains Mono is already monospaced; this keeps
  /// it true should the family ever change).
  Widget _timeReadout(BuildContext context, String text, {required bool compact, Color? color}) {
    return Text(
      text,
      maxLines: 1,
      softWrap: false,
      textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
      style: PTText.mono.copyWith(
        fontSize: compact ? 11 : 13,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

class _SplitDeviceButton extends StatelessWidget {
  const _SplitDeviceButton({
    required this.mainButton,
    required this.onDropdown,
    this.dropdownTooltip,
    this.disabledDropdownTooltip,
    this.height = 42,
    this.showDropdown = true,
  });

  final Widget mainButton;
  final void Function(BuildContext context)? onDropdown;
  final String? dropdownTooltip;
  final String? disabledDropdownTooltip;
  final double height;
  final bool showDropdown;

  @override
  Widget build(BuildContext context) {
    if (!showDropdown) return mainButton;
    final isEnabled = onDropdown != null;
    return Row(
      mainAxisSize: .min,
      spacing: 2,
      children: [
        mainButton,
        Builder(
          builder: (caretContext) => _CaretButton(
            height: height,
            tooltip: isEnabled ? dropdownTooltip : disabledDropdownTooltip,
            onPressed: isEnabled ? () => onDropdown!(caretContext) : null,
          ),
        ),
      ],
    );
  }
}

class _CaretButton extends StatefulWidget {
  const _CaretButton({required this.height, required this.onPressed, this.tooltip});

  final double height;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  State<_CaretButton> createState() => _CaretButtonState();
}

class _CaretButtonState extends State<_CaretButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    Widget btn = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: PTPressable(
        enabled: enabled,
        onTap: widget.onPressed,
        child: AnimatedOpacity(
          duration: PTMotion.functional(context, PTMotion.hover),
          opacity: enabled ? 1.0 : 0.4,
          child: AnimatedContainer(
            duration: PTMotion.functional(context, PTMotion.hover),
            width: 18,
            height: widget.height,
            decoration: BoxDecoration(
              color: _hovered && enabled ? PTColors.white(0.12) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Icon(
                BoothIcons.chevronDown,
                size: 16,
                color: PTColors.white(_hovered && enabled ? 0.95 : 0.6),
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      btn = Tooltip(message: widget.tooltip!, child: btn);
    }
    return btn;
  }
}
