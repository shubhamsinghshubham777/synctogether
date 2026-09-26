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
    this.subtitleTag,
    this.audioTag,
  });

  /// The selected tracks, tagged for the `SUBS · EN` / `AUDIO · JA 5.1` keys.
  final String? subtitleTag;
  final String? audioTag;

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
                  : const EdgeInsets.symmetric(horizontal: 24, vertical: 11),
              child: child,
            ),
          )
        : GlassPanel(
            radius: PTRadius.panel,
            baseColor: PTColors.surfaceBase,
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: compact ? 14 : 12),
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
            spacing: docked && !compact ? 12 : (compact ? 8 : 10),
            children: [
              Row(
                spacing: compact || !docked ? 10 : 12,
                children: [
                  ValueListenableBuilder(
                    valueListenable: _playhead,
                    builder: (context, playhead, _) => _timeReadout(
                      context,
                      _fmt(drag == null ? playhead : widget.duration * drag),
                      compact: compact || !docked,
                      weight: docked && !compact ? .w600 : null,
                      color: PTColors.fg,
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
                            trackHeight: 4,
                            thumbRadius: 7,
                            thumb: compact
                                ? PTSliderThumb.round
                                : docked
                                ? PTSliderThumb.bar
                                : PTSliderThumb.none,
                            glowFill: !compact,
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
                    compact: compact || !docked,
                    color: PTColors.fgMute,
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

  /// Mic, camera (or its Premium lock) and the reaction toggle, as the boards
  /// draw them: [outlined] Rail squares on the docked bar (a hot mic or camera
  /// in Signal, open reactions in Beam), bare glyphs on the floating one.
  /// Device choice rides a right-click or long-press on mic and camera.
  List<Widget> _avButtons({required double size, required bool outlined}) {
    final actions = widget.actions;
    Widget key({
      required IconData icon,
      required String tooltip,
      required VoidCallback? onPressed,
      bool active = false,
      Color? activeColor,
    }) => PTIconButton(
      icon: icon,
      active: active,
      activeColor: activeColor,
      glass: false,
      outlined: outlined,
      color: outlined || active ? null : PTColors.fgDim,
      size: size,
      iconSize: 18,
      tooltip: tooltip,
      onPressed: onPressed,
    );
    return [
      if (widget.avAvailable) ...[
        _DeviceMenu(
          onMenu: actions.onMicDeviceSelect,
          child: key(
            icon: BoothIcons.mic,
            active: widget.micOn,
            activeColor: PTColors.ember,
            tooltip: _withDeviceHint(
              widget.micOn ? 'Mute mic (D)' : 'Mic on (D)',
              actions.onMicDeviceSelect,
            ),
            onPressed: () => actions.onMicToggle(!widget.micOn),
          ),
        ),
        if (widget.camAvailable)
          _DeviceMenu(
            onMenu: actions.onCamDeviceSelect,
            child: key(
              icon: BoothIcons.videocam,
              active: widget.camOn,
              activeColor: PTColors.ember,
              tooltip: _withDeviceHint(
                widget.camOn ? 'Camera off (E)' : 'Camera on (E)',
                actions.onCamDeviceSelect,
              ),
              onPressed: () => actions.onCamToggle(!widget.camOn),
            ),
          )
        else if (actions.onCamLocked != null)
          Stack(
            alignment: Alignment.center,
            children: [
              key(
                icon: BoothIcons.videocamOff,
                tooltip: 'Video facecams (Premium)',
                onPressed: actions.onCamLocked,
              ),
              const Positioned(bottom: 4, right: 4, child: _PremiumLock()),
            ],
          ),
      ],
      if (actions.onReact != null)
        key(
          icon: BoothIcons.react,
          active: widget.reactOpen,
          tooltip: widget.reactOpen ? 'Close reactions (R)' : 'React (R)',
          onPressed: actions.onReact,
        ),
    ];
  }

  static String _withDeviceHint(String tooltip, Object? menu) =>
      menu == null ? tooltip : '$tooltip · right-click to pick a device';

  /// `SUBS · EN`, `AUDIO · JA 5.1` - the chooser buttons name what is
  /// selected, so nobody opens one just to find out.
  Widget _trackKey(String kind, String? tag, VoidCallback onPressed, {required double height}) {
    return _TextKey(
      label: tag == null ? kind : '$kind · $tag',
      tooltip: kind == 'SUBS' ? 'Subtitles' : 'Audio track',
      height: height,
      padding: height >= 40 ? 12 : 8,
      fontSize: height >= 40 ? 12 : 11,
      color: PTColors.fgDim,
      onPressed: onPressed,
    );
  }

  /// −10 s, play/pause, +10 s: typed skip keys either side of the Beam key.
  List<Widget> _transportKeys({
    required double keySize,
    required double playHeight,
    required double fontSize,
    required double iconSize,
  }) {
    final actions = widget.actions;
    final enabled = widget.transportEnabled;
    return [
      _TextKey(
        label: '−10',
        tooltip: 'Back 10 seconds',
        width: keySize,
        height: keySize,
        fontSize: fontSize,
        onPressed: enabled ? () => actions.onSkip(const Duration(seconds: -10)) : null,
      ),
      PTPlayButton(
        playing: widget.playing,
        size: 44,
        height: playHeight,
        iconSize: iconSize,
        glow: false,
        onPressed: enabled ? actions.onPlayPause : null,
      ),
      _TextKey(
        label: '+10',
        tooltip: 'Forward 10 seconds',
        width: keySize,
        height: keySize,
        fontSize: fontSize,
        onPressed: enabled ? () => actions.onSkip(const Duration(seconds: 10)) : null,
      ),
    ];
  }

  /// The volume glyph (right-click for the output device) and its slider.
  Widget _volume({required double sliderWidth, required PTSliderThumb thumb}) {
    final actions = widget.actions;
    final outputHint = actions.onAudioOutputSelect != null
        ? ' · right-click to pick an output'
        : actions.audioOutputDisabledTooltip != null
        ? ' · ${actions.audioOutputDisabledTooltip}'
        : '';
    return Row(
      mainAxisSize: .min,
      spacing: 6,
      children: [
        _DeviceMenu(
          onMenu: actions.onAudioOutputSelect,
          child: PTIconButton(
            icon: widget.volume == 0 ? BoothIcons.volumeOff : BoothIcons.volume,
            glass: false,
            color: PTColors.fgDim,
            size: 32,
            iconSize: 18,
            tooltip: (widget.volume == 0 ? 'Unmute (M)' : 'Mute (M)') + outputHint,
            onPressed: actions.onToggleMute,
          ),
        ),
        SizedBox(
          width: sliderWidth,
          child: PTSlider(
            value: widget.volume,
            trackHeight: 4,
            thumbRadius: 6,
            thumb: thumb,
            onChanged: actions.onVolume,
          ),
        ),
      ],
    );
  }

  Widget? _fullscreenKey(double size) {
    final toggle = widget.actions.onFullscreenToggle;
    if (toggle == null) return null;
    return PTIconButton(
      icon: widget.fullscreen ? BoothIcons.fullscreenExit : BoothIcons.fullscreen,
      glass: false,
      size: size,
      iconSize: 18,
      color: PTColors.fg,
      tooltip: widget.fullscreen ? 'Exit fullscreen (F)' : 'Fullscreen (F)',
      onPressed: toggle,
    );
  }

  /// The floating bar (Room at minimum window board): talk and react with
  /// the subtitle key on the left, the transport dead centre, volume and
  /// fullscreen on the right. Everything else lives in the room menu.
  Widget _fullRow() {
    final actions = widget.actions;
    final left = [
      ..._avButtons(size: 36, outlined: false),
      if (actions.onSubtitles != null)
        _trackKey('SUBS', widget.subtitleTag, actions.onSubtitles!, height: 36),
    ];
    final right = [_volume(sliderWidth: 90, thumb: PTSliderThumb.round), ?_fullscreenKey(36)];
    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: .centerLeft,
            child: FittedBox(
              fit: .scaleDown,
              child: Row(mainAxisSize: .min, spacing: 6, children: left),
            ),
          ),
        ),
        Row(
          mainAxisSize: .min,
          spacing: 6,
          children: _transportKeys(keySize: 36, playHeight: 38, fontSize: 11, iconSize: 16),
        ),
        Expanded(
          child: Align(
            alignment: .centerRight,
            child: FittedBox(
              fit: .scaleDown,
              child: Row(mainAxisSize: .min, spacing: 6, children: right),
            ),
          ),
        ),
      ],
    );
  }

  /// The theatre bar (Desktop room board): transport first, where the eye
  /// lands leaving the picture, then talk and react after a Rail rule; the
  /// track keys, volume and fullscreen sit on the far side. The volume
  /// slider is the first thing to go when the row runs short.
  Widget _dockedRow() {
    final actions = widget.actions;
    final av = _avButtons(size: 40, outlined: true);
    return LayoutBuilder(
      builder: (context, box) {
        final slider = box.maxWidth >= 820;
        return Row(
          children: [
            Row(
              mainAxisSize: .min,
              spacing: 8,
              children: _transportKeys(keySize: 40, playHeight: 40, fontSize: 12, iconSize: 18),
            ),
            if (av.isNotEmpty) ...[
              Container(
                width: 1,
                height: 24,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                color: PTColors.rail,
              ),
              Row(mainAxisSize: .min, spacing: 8, children: av),
            ],
            const Spacer(),
            Flexible(
              flex: 0,
              child: FittedBox(
                fit: .scaleDown,
                child: Row(
                  mainAxisSize: .min,
                  spacing: 8,
                  children: [
                    if (actions.onSubtitles != null)
                      _trackKey('SUBS', widget.subtitleTag, actions.onSubtitles!, height: 40),
                    if (actions.onAudioTracks != null)
                      _trackKey('AUDIO', widget.audioTag, actions.onAudioTracks!, height: 40),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: slider
                          ? _volume(sliderWidth: 80, thumb: PTSliderThumb.none)
                          : _volume(sliderWidth: 0, thumb: PTSliderThumb.none),
                    ),
                    ?_fullscreenKey(40),
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
          // The Mobile room board draws the touch bar's react key as a face;
          // the pointer bars keep the heart.
          icon: BoothIcons.mood,
          active: widget.reactOpen,
          glass: false,
          color: widget.reactOpen ? null : PTColors.fgDim,
          borderRadius: BorderRadius.circular(PTRadius.control),
          iconSize: 22,
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
  Widget _timeReadout(
    BuildContext context,
    String text, {
    required bool compact,
    Color? color,
    FontWeight? weight,
  }) {
    return Text(
      text,
      maxLines: 1,
      softWrap: false,
      textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
      style: PTText.mono.copyWith(
        fontSize: compact ? 11 : 13,
        fontWeight: weight,
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

/// Opens a device menu on right-click (pointer) or long-press (touch), so the
/// toggle itself stays a single clean square.
class _DeviceMenu extends StatelessWidget {
  const _DeviceMenu({required this.onMenu, required this.child});

  final void Function(BuildContext context)? onMenu;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final menu = onMenu;
    if (menu == null) return child;
    return GestureDetector(
      onSecondaryTap: () => menu(context),
      onLongPress: () => menu(context),
      child: child,
    );
  }
}

/// A typed key - `−10`, `SUBS · EN` - in JetBrains Mono on a bare square
/// that lights to Aisle under the pointer.
class _TextKey extends StatefulWidget {
  const _TextKey({
    required this.label,
    required this.onPressed,
    this.tooltip,
    this.width,
    required this.height,
    this.padding = 0,
    required this.fontSize,
    this.color = PTColors.fg,
  });

  final String label;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double? width;
  final double height;
  final double padding;
  final double fontSize;
  final Color color;

  @override
  State<_TextKey> createState() => _TextKeyState();
}

class _TextKeyState extends State<_TextKey> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    Widget key = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: PTPressable(
        enabled: enabled,
        onTap: widget.onPressed,
        child: AnimatedOpacity(
          duration: PTMotion.functional(context, PTMotion.hover),
          opacity: enabled ? 1 : 0.45,
          child: AnimatedContainer(
            duration: PTMotion.functional(context, PTMotion.hover),
            width: widget.width,
            height: widget.height,
            padding: EdgeInsets.symmetric(horizontal: widget.padding),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hovered && enabled ? PTColors.aisle : Colors.transparent,
              borderRadius: BorderRadius.circular(PTRadius.control),
            ),
            child: Text(
              widget.label,
              maxLines: 1,
              softWrap: false,
              textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
              style: TextStyle(
                fontFamily: PTFonts.mono,
                fontSize: widget.fontSize,
                letterSpacing: widget.padding > 0 ? widget.fontSize * 0.08 : 0,
                color: widget.color,
              ),
            ),
          ),
        ),
      ),
    );
    if (widget.tooltip != null) key = Tooltip(message: widget.tooltip!, child: key);
    return key;
  }
}

/// The Brass lock on a camera key the room's tier does not grant.
class _PremiumLock extends StatelessWidget {
  const _PremiumLock();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: PTColors.raised,
          shape: BoxShape.circle,
          border: Border.all(color: PTColors.accentBorder.withValues(alpha: 0.5)),
        ),
        child: const Icon(BoothIcons.lock, size: 9, fill: 1, color: PTColors.textAccent),
      ),
    );
  }
}
