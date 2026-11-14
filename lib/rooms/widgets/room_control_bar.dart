import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../ui/booth_icons.g.dart';
import '../../ui/coach_target.dart';

import 'package:flutter/scheduler.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:synctogether/ui/adaptive_action_bar.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/inputs.dart';
import 'package:synctogether/ui/pt_motion.dart';
import 'package:synctogether/ui/pt_theme.dart';

import 'room_bar_form.dart';
import 'room_bar_more.dart';

class RoomControlBarActions {
  const RoomControlBarActions({
    required this.onPlayPause,
    required this.onSeek,
    required this.onSkip,
    required this.onMicToggle,
    required this.onCamToggle,
    this.onCamLocked,
    this.onVoiceLocked,
    this.voiceLockedTooltip,
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

  /// A room whose host's tier grants no AV (a guest's) draws a locked mic in
  /// place of the voice keys, so the room says what it is missing and why.
  final VoidCallback? onVoiceLocked;
  final String? voiceLockedTooltip;
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

/// The locked camera key teaches rather than labels: video is the host's
/// tier, so this says what Premium changes and for whom.
/// For a signed-in viewer; RoomScreen passes guest-specific copy.
const kVoiceLockedTooltip =
    'This is a guest room, so voice chat is off. Rooms hosted from a free '
    'account get voice, and Premium hosts add video.';

const kCamLockedTooltip =
    'Video facecams are a Premium perk. Host with Premium and everyone in '
    'your room can turn their camera on.';

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
    this.camTrialMinutes,
    required this.actions,
    this.compact = false,
    this.docked = false,
    this.fullscreen = false,
    this.reactOpen = false,
    this.transportEnabled = true,
    this.transportHint,
    this.subtitleTag,
    this.audioTag,
    this.sourceTag,
  });

  /// A free room's untouched video trial: the camera key offers it with a
  /// small Beam tag ("10M") and pressing it starts the trial (board 32).
  final int? camTrialMinutes;

  /// The selected tracks, tagged for the `SUBS · EN` / `AUDIO · JA 5.1` keys.
  final String? subtitleTag;
  final String? audioTag;

  /// What the room is watching, for the Source row of the More list.
  final String? sourceTag;

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

  /// The phone bar. It collapses through the F1-F5 form ladder; every other
  /// bar is the tablet's floating one or the docked theatre bar.
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

  /// What this bar carries, for choosing its form (see `room_bar_form.dart`).
  /// The phone bar has the source group; the touch tablet's floating bar has
  /// the SUBS key and the volume instead.
  RoomBarCaps get caps {
    final a = actions;
    final tablet = !compact;
    return RoomBarCaps(
      tablet: tablet,
      hourLabels: duration >= const Duration(hours: 1),
      subsKeyLabel: subtitleTag == null ? 'SUBS' : 'SUBS · $subtitleTag',
      controls: {
        if (avAvailable || a.onVoiceLocked != null) BarControl.mic,
        if (avAvailable && (camAvailable || a.onCamLocked != null)) BarControl.camera,
        if (a.onReact != null) BarControl.react,
        BarControl.skipBack,
        BarControl.skipForward,
        if (tablet) ...[
          if (a.onSubtitles != null) BarControl.subtitles,
          BarControl.volume,
          if (a.onFullscreenToggle != null) BarControl.fullscreen,
        ] else ...[
          if (a.onSwitchSource != null) BarControl.source,
          if (a.onOpenFile != null) BarControl.openFile,
          if (a.onAudioTracks != null) BarControl.audio,
          if (a.onSubtitles != null) BarControl.subtitles,
          if (a.onHideControls != null) BarControl.hide,
          if (a.onFullscreenToggle != null) BarControl.fullscreen,
        ],
      },
    );
  }

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

/// Floating bars at least this wide lay out like the docked theatre bar.
const kFloatingBoardWidth = 1000.0;

class _RoomControlBarState extends State<RoomControlBar> with SingleTickerProviderStateMixin {
  String get _camTooltip => widget.camTrialMinutes != null
      ? 'Try video free for ${widget.camTrialMinutes} minutes (E)'
      : widget.camOn
      ? 'Camera off (E)'
      : 'Camera on (E)';

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
  /// seek-preview chip. The chip escapes the control panel's clip via [_sliderLink].
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

  final _panelKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        // Phone bars, and the touch tablet's floating bar while it is narrower
        // than the theatre bar, collapse through the form ladder. The wide
        // floating bar and the docked theatre bar fold through
        // `AdaptiveActionBar` instead.
        final ladder = widget.compact || (!widget.docked && width - 32 < kFloatingBoardWidth);
        return _withPreview(ladder ? _ladderPanel(context, width) : _classicPanel(context));
      },
    );
  }

  /// The scrub preview chip must escape the panel's clip, so it rides a
  /// CompositedTransformFollower in an unclipped outer Stack rather than living
  /// inside the panel. Hidden while scrubbing (the position text already
  /// previews the drag) and until a duration is known.
  Widget _withPreview(Widget panel) {
    final hover = _hoverValue;
    final showChip = hover != null && _dragValue == null && widget.duration.inMilliseconds > 0;
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

  /// The scrubber. Its own layer: the playhead repaints every frame while
  /// playing, and nothing else in the bar should.
  Widget _scrubber({required PTSliderThumb thumb, required bool glow}) {
    return CompositedTransformTarget(
      link: _sliderLink,
      child: RepaintBoundary(
        child: ValueListenableBuilder(
          valueListenable: _playhead,
          builder: (context, playhead, _) => PTSlider(
            value: _dragValue ?? _progressOf(playhead),
            bufferedValue: _bufferedProgress,
            trackHeight: 4,
            thumbRadius: 7,
            thumb: thumb,
            glowFill: glow,
            enabled: widget.transportEnabled,
            onChanged: (v) => setState(() => _dragValue = v),
            onChangeEnd: _endScrub,
            onHover: (v) => setState(() => _hoverValue = v),
          ),
        ),
      ),
    );
  }

  /// Grows and collapses rather than appearing: the gate can flap, and a bar
  /// that jumps a row height each time is worse than the hint.
  Widget _hint({required double gap}) {
    return AnimatedSize(
      duration: PTMotion.functional(context, PTMotion.state),
      curve: PTMotion.enter,
      alignment: .topCenter,
      child: !widget.transportEnabled && widget.transportHint != null
          ? Padding(
              padding: EdgeInsets.only(top: gap),
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
    );
  }

  /// The theatre bar and the wide floating bar: one row under the scrubber.
  Widget _classicPanel(BuildContext context) {
    final docked = widget.docked;
    final drag = _dragValue;
    Widget shell(Widget child) => docked
        ? DecoratedBox(
            decoration: const BoxDecoration(
              color: PTColors.canvas,
              border: Border(top: BorderSide(color: PTColors.aisle)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 11),
              child: child,
            ),
          )
        : GlassPanel(
            radius: PTRadius.panel,
            baseColor: PTColors.surfaceBase,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: child,
          );
    return shell(
      // Two nested columns on purpose: the hint sits *outside* the spaced
      // column so its collapsed state costs nothing. As a spaced sibling, an
      // empty hint would still leave a row gap behind it.
      Column(
        mainAxisSize: .min,
        children: [
          Column(
            mainAxisSize: .min,
            spacing: docked ? 12 : 10,
            children: [
              Row(
                spacing: docked ? 12 : 10,
                children: [
                  ValueListenableBuilder(
                    valueListenable: _playhead,
                    builder: (context, playhead, _) => _timeReadout(
                      context,
                      _fmt(drag == null ? playhead : widget.duration * drag),
                      compact: !docked,
                      weight: docked ? .w600 : null,
                      color: PTColors.fg,
                    ),
                  ),
                  Expanded(
                    child: _scrubber(
                      thumb: docked ? PTSliderThumb.bar : PTSliderThumb.none,
                      glow: true,
                    ),
                  ),
                  _timeReadout(
                    context,
                    _fmt(widget.duration),
                    compact: !docked,
                    color: PTColors.fgMute,
                  ),
                ],
              ),
              _dockedRow(),
            ],
          ),
          _hint(gap: 14),
        ],
      ),
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
              tooltip: _withDeviceHint(_camTooltip, actions.onCamDeviceSelect),
              onPressed: () => actions.onCamToggle(!widget.camOn),
            ),
          ).withTrialTag(widget.camTrialMinutes)
        else if (actions.onCamLocked != null)
          Stack(
            alignment: Alignment.center,
            children: [
              key(
                icon: BoothIcons.videocamOff,
                tooltip: kCamLockedTooltip,
                onPressed: actions.onCamLocked,
              ),
              const Positioned(bottom: 4, right: 4, child: _PremiumLock()),
            ],
          ),
      ] else if (actions.onVoiceLocked != null)
        Stack(
          alignment: Alignment.center,
          children: [
            key(
              icon: BoothIcons.micOff,
              tooltip: actions.voiceLockedTooltip ?? kVoiceLockedTooltip,
              onPressed: actions.onVoiceLocked,
            ),
            const Positioned(bottom: 4, right: 4, child: _PremiumLock()),
          ],
        ),
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
      CoachTarget(
        id: .play,
        child: PTPlayButton(
          playing: widget.playing,
          size: 44,
          height: playHeight,
          iconSize: iconSize,
          glow: false,
          onPressed: enabled ? actions.onPlayPause : null,
        ),
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

  /// The theatre bar (Desktop room board): transport first, where the eye
  /// lands leaving the picture, then talk and react after a Rail rule; the
  /// track keys, volume and fullscreen sit on the far side. When the row runs
  /// short nothing scales: AUDIO, then SUBS, then the volume fold into the
  /// bar's More list (`AdaptiveActionBar`), and the slider is the first thing
  /// to go before any of them.
  Widget _dockedRow() {
    final actions = widget.actions;
    final av = _avButtons(size: 40, outlined: true);
    return LayoutBuilder(
      builder: (context, box) {
        final slider = box.maxWidth >= 820;
        final muted = widget.volume == 0;
        return AdaptiveActionBar(
          spacing: 8,
          moreSize: 40,
          moreIconSize: 18,
          pinned: [
            Row(
              mainAxisSize: .min,
              spacing: 8,
              children: _transportKeys(keySize: 40, playHeight: 40, fontSize: 12, iconSize: 18),
            ),
            if (av.isNotEmpty) ...[
              Container(
                width: 1,
                height: 24,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                color: PTColors.rail,
              ),
              Row(mainAxisSize: .min, spacing: 8, children: av),
            ],
            // Whatever the left group leaves; pushes the rest to the far edge.
            const AdaptiveFlex(child: SizedBox.shrink()),
          ],
          foldable: [
            if (actions.onSubtitles != null)
              AdaptiveAction(
                label: 'Subtitles',
                icon: BoothIcons.subtitles,
                value: widget.subtitleTag ?? 'Off',
                priority: 2,
                onTap: actions.onSubtitles,
                inline: _trackKey('SUBS', widget.subtitleTag, actions.onSubtitles!, height: 40),
              ),
            if (actions.onAudioTracks != null)
              AdaptiveAction(
                label: 'Audio track',
                icon: Symbols.audiotrack_rounded,
                value: widget.audioTag ?? 'Default',
                priority: 1,
                onTap: actions.onAudioTracks,
                inline: _trackKey('AUDIO', widget.audioTag, actions.onAudioTracks!, height: 40),
              ),
            AdaptiveAction(
              label: 'Volume',
              icon: muted ? BoothIcons.volumeOff : BoothIcons.volume,
              value: muted ? 'Muted' : '${(widget.volume * 100).round()}%',
              priority: 3,
              onTap: actions.onToggleMute,
              inline: slider
                  ? _volume(sliderWidth: 80, thumb: PTSliderThumb.none)
                  : _volume(sliderWidth: 0, thumb: PTSliderThumb.none),
            ),
          ],
          pinnedEnd: [?_fullscreenKey(40)],
        );
      },
    );
  }

  // -------------------------------------------------------------------------
  // The form ladder (board 46)

  /// Every control this bar carries, built once in both of its faces: the
  /// inline key and the More row. [form] only matters to the tablet volume,
  /// whose inline face is the glyph alone once the slider has folded.
  Map<BarControl, _Ctl> _controls(RoomBarForm form) {
    final a = widget.actions;
    final enabled = widget.transportEnabled;
    final control = BorderRadius.circular(PTRadius.control);
    final out = <BarControl, _Ctl>{};

    Widget key({
      required IconData icon,
      required String tooltip,
      required VoidCallback? onPressed,
      bool active = false,
      Color? activeColor,
      double iconSize = 22,
      double spin = 0,
      bool outlined = false,
    }) => PTIconButton(
      icon: icon,
      active: active,
      activeColor: activeColor,
      glass: false,
      outlined: outlined,
      color: active ? null : PTColors.fgDim,
      borderRadius: control,
      iconSize: iconSize,
      spinOnPress: spin,
      tooltip: tooltip,
      onPressed: onPressed,
    );

    Widget locked(IconData icon, String tooltip, VoidCallback? onPressed) => Stack(
      alignment: Alignment.center,
      children: [
        key(icon: icon, tooltip: tooltip, onPressed: onPressed, outlined: true),
        const Positioned(bottom: 6, right: 6, child: _PremiumLock()),
      ],
    );

    void add(
      BarControl id, {
      required Widget inline,
      required String label,
      required IconData icon,
      String? value,
      VoidCallback? onTap,
      bool live = false,
    }) => out[id] = _Ctl(
      inline,
      AdaptiveAction(label: label, icon: icon, value: value, onTap: onTap, inline: inline),
      live: live,
    );

    if (widget.avAvailable) {
      final on = widget.micOn;
      add(
        .mic,
        label: 'Microphone',
        icon: BoothIcons.mic,
        value: on ? 'On air' : 'Off',
        onTap: () => a.onMicToggle(!on),
        live: on,
        inline: _DeviceMenu(
          onMenu: a.onMicDeviceSelect,
          child: key(
            outlined: true,
            icon: BoothIcons.mic,
            active: on,
            activeColor: PTColors.ember,
            tooltip: _withDeviceHint(on ? 'Mute mic (D)' : 'Mic on (D)', a.onMicDeviceSelect),
            onPressed: () => a.onMicToggle(!on),
          ),
        ),
      );
      if (widget.camAvailable) {
        final on = widget.camOn;
        add(
          .camera,
          label: 'Camera',
          icon: BoothIcons.videocam,
          value: on
              ? 'On air'
              : widget.camTrialMinutes != null
              ? 'Try free for ${widget.camTrialMinutes} min'
              : 'Off',
          onTap: () => a.onCamToggle(!on),
          live: on,
          inline: _DeviceMenu(
            onMenu: a.onCamDeviceSelect,
            child: key(
              outlined: true,
              icon: BoothIcons.videocam,
              active: on,
              activeColor: PTColors.ember,
              tooltip: _withDeviceHint(_camTooltip, a.onCamDeviceSelect),
              onPressed: () => a.onCamToggle(!on),
            ),
          ).withTrialTag(widget.camTrialMinutes),
        );
      } else if (a.onCamLocked != null) {
        add(
          .camera,
          label: 'Camera',
          icon: BoothIcons.videocamOff,
          value: 'Premium',
          onTap: a.onCamLocked,
          inline: locked(BoothIcons.videocamOff, kCamLockedTooltip, a.onCamLocked),
        );
      }
    } else if (a.onVoiceLocked != null) {
      add(
        .mic,
        label: 'Microphone',
        icon: BoothIcons.micOff,
        value: 'Locked',
        onTap: a.onVoiceLocked,
        inline: locked(
          BoothIcons.micOff,
          a.voiceLockedTooltip ?? kVoiceLockedTooltip,
          a.onVoiceLocked,
        ),
      );
    }
    if (a.onReact != null) {
      add(
        .react,
        label: 'React',
        icon: BoothIcons.mood,
        value: widget.reactOpen ? 'Close strip' : 'Open strip',
        onTap: a.onReact,
        // The Mobile room board draws the touch bar's react key as a face;
        // the pointer bars keep the heart.
        inline: key(
          outlined: true,
          icon: BoothIcons.mood,
          active: widget.reactOpen,
          tooltip: widget.reactOpen ? 'Close reactions (R)' : 'React (R)',
          onPressed: a.onReact,
        ),
      );
    }
    final back = enabled ? () => a.onSkip(const Duration(seconds: -10)) : null;
    final ahead = enabled ? () => a.onSkip(const Duration(seconds: 10)) : null;
    add(
      .skipBack,
      label: 'Back 10 s',
      icon: BoothIcons.replay,
      value: 'Same as double-tap',
      onTap: back,
      inline: key(
        icon: BoothIcons.replay,
        tooltip: 'Back 10 seconds',
        onPressed: back,
        iconSize: 24,
        spin: -40,
      ),
    );
    add(
      .skipForward,
      label: 'Forward 10 s',
      icon: BoothIcons.forward,
      value: 'Same as double-tap',
      onTap: ahead,
      inline: key(
        icon: BoothIcons.forward,
        tooltip: 'Forward 10 seconds',
        onPressed: ahead,
        iconSize: 24,
        spin: 40,
      ),
    );

    if (widget.caps.tablet) {
      if (a.onSubtitles != null) {
        add(
          .subtitles,
          label: 'Subtitles',
          icon: BoothIcons.subtitles,
          value: widget.subtitleTag ?? 'Off',
          onTap: a.onSubtitles,
          inline: _TextKey(
            label: widget.caps.subsKeyLabel,
            height: 44,
            padding: 10,
            fontSize: 11,
            color: PTColors.fgDim,
            onPressed: a.onSubtitles,
          ),
        );
      }
      final muted = widget.volume == 0;
      final outputHint = a.onAudioOutputSelect != null
          ? ' · right-click to pick an output'
          : a.audioOutputDisabledTooltip != null
          ? ' · ${a.audioOutputDisabledTooltip}'
          : '';
      add(
        .volume,
        label: 'Volume',
        icon: muted ? BoothIcons.volumeOff : BoothIcons.volume,
        value: muted ? 'Muted' : '${(widget.volume * 100).round()}%',
        onTap: a.onToggleMute,
        inline: Row(
          mainAxisSize: .min,
          spacing: 4,
          children: [
            if (form == RoomBarForm.t0)
              SizedBox(
                width: 90,
                child: PTSlider(
                  value: widget.volume,
                  trackHeight: 4,
                  thumbRadius: 6,
                  thumb: PTSliderThumb.none,
                  onChanged: a.onVolume,
                ),
              ),
            _DeviceMenu(
              onMenu: a.onAudioOutputSelect,
              child: key(
                icon: muted ? BoothIcons.volumeOff : BoothIcons.volume,
                tooltip: (muted ? 'Unmute (M)' : 'Mute (M)') + outputHint,
                onPressed: a.onToggleMute,
              ),
            ),
          ],
        ),
      );
    } else {
      if (a.onSwitchSource != null) {
        add(
          .source,
          label: 'Source',
          icon: BoothIcons.youtube,
          value: widget.sourceTag,
          onTap: a.onSwitchSource,
          inline: key(
            icon: BoothIcons.youtube,
            tooltip: 'Switch source',
            onPressed: a.onSwitchSource,
          ),
        );
      }
      if (a.onOpenFile != null) {
        add(
          .openFile,
          label: 'Open file',
          icon: BoothIcons.file,
          value: a.openFileTooltip == null ? 'Pick another' : 'Find your copy',
          onTap: a.onOpenFile,
          inline: key(
            icon: BoothIcons.file,
            tooltip: a.openFileTooltip ?? 'Open file',
            onPressed: a.onOpenFile,
          ),
        );
      }
      if (a.onAudioTracks != null) {
        add(
          .audio,
          label: 'Audio track',
          icon: Symbols.audiotrack_rounded,
          value: widget.audioTag ?? 'Default',
          onTap: a.onAudioTracks,
          inline: key(
            icon: Symbols.audiotrack_rounded,
            tooltip: 'Audio track',
            onPressed: a.onAudioTracks,
          ),
        );
      }
      if (a.onSubtitles != null) {
        add(
          .subtitles,
          label: 'Subtitles',
          icon: BoothIcons.subtitles,
          value: widget.subtitleTag ?? 'Off',
          onTap: a.onSubtitles,
          inline: key(icon: BoothIcons.subtitles, tooltip: 'Subtitles', onPressed: a.onSubtitles),
        );
      }
      if (a.onHideControls != null) {
        add(
          .hide,
          label: 'Hide controls',
          icon: BoothIcons.chevronDown,
          value: 'Tap to bring back',
          onTap: a.onHideControls,
          inline: key(
            icon: BoothIcons.chevronDown,
            tooltip: 'Hide controls (H)',
            onPressed: a.onHideControls,
          ),
        );
      }
    }
    // Fullscreen is the far key of whichever ladder carries it.
    if (a.onFullscreenToggle != null) {
      add(
        .fullscreen,
        label: widget.fullscreen ? 'Exit fullscreen' : 'Fullscreen',
        icon: widget.fullscreen ? BoothIcons.fullscreenExit : BoothIcons.fullscreen,
        // A phone's fullscreen is a turn, not a window: say so.
        value: widget.compact ? 'Turn to landscape' : null,
        onTap: a.onFullscreenToggle,
        inline: key(
          icon: widget.fullscreen ? BoothIcons.fullscreenExit : BoothIcons.fullscreen,
          tooltip: widget.fullscreen ? 'Exit fullscreen (F)' : 'Fullscreen (F)',
          onPressed: a.onFullscreenToggle,
        ),
      );
    }
    return out;
  }

  Widget _timeLabel(String text, double width, {required Color color, required bool end}) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        overflow: .visible,
        textAlign: end ? .end : .start,
        textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
        style: PTText.mono.copyWith(
          fontSize: kTimeLabelSize,
          color: color,
          fontWeight: end ? null : .w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  /// Position, scrubber, duration: the part of every form that never folds.
  Widget _seekGroup(double labelWidth) {
    final drag = _dragValue;
    return Row(
      spacing: 8,
      children: [
        ValueListenableBuilder(
          valueListenable: _playhead,
          builder: (context, playhead, _) => _timeLabel(
            _fmt(drag == null ? playhead : widget.duration * drag),
            labelWidth,
            color: PTColors.fg,
            end: false,
          ),
        ),
        Expanded(child: _scrubber(thumb: .round, glow: false)),
        _timeLabel(_fmt(widget.duration), labelWidth, color: PTColors.fgMute, end: true),
      ],
    );
  }

  Widget _ladderPanel(BuildContext context, double width) {
    final scaler = MediaQuery.textScalerOf(context);
    final caps = widget.caps;
    var form = pickBarForm(slot: width, caps: caps, scaler: scaler);
    // The layout knows about the facecam rail and the chat; the bar knows its
    // real width. Take the narrower, so a slot that is still animating never
    // asks a form for room it has not got yet.
    final chosen = caps.tablet ? null : RoomBarFormScope.maybeOf(context);
    if (chosen != null) form = narrowerOf(form, chosen, caps);

    final controls = _controls(form);
    final folded = <_Ctl>[
      for (final id in BarControl.values)
        if (form.folded.contains(id) && controls.containsKey(id)) controls[id]!,
    ];
    Iterable<Widget> shown(List<BarControl> ids) => [
      for (final id in ids)
        if (!form.folded.contains(id) && controls.containsKey(id)) controls[id]!.inline,
    ];
    Widget group(Iterable<Widget> keys, {double gap = 4}) =>
        Row(mainAxisSize: .min, spacing: gap, children: keys.toList());

    final labelWidth = timeLabelWidth(scaler, hours: caps.hourLabels);
    final play = CoachTarget(
      id: .play,
      child: PTPlayButton(
        playing: widget.playing,
        size: 52,
        onPressed: widget.transportEnabled ? widget.actions.onPlayPause : null,
      ),
    );
    // Two rows draw mic, camera, react; one row draws react first so the
    // camera and then the mic are the last of the group to fold (board 46).
    final av = shown(
      form.twoRows
          ? const [BarControl.mic, BarControl.camera, BarControl.react]
          : const [BarControl.react, BarControl.mic, BarControl.camera],
    );
    final more = folded.isEmpty
        ? null
        : RoomBarMoreButton(
            rows: [for (final c in folded) c.row],
            live: folded.any((c) => c.live),
            panelKey: _panelKey,
            formName: form.name,
          );

    final Widget content;
    if (form.twoRows) {
      final right = caps.tablet
          ? shown(const [BarControl.subtitles, BarControl.volume, BarControl.fullscreen])
          : shown(const [
              BarControl.source,
              BarControl.openFile,
              BarControl.audio,
              BarControl.subtitles,
              BarControl.hide,
              BarControl.fullscreen,
            ]);
      content = Column(
        mainAxisAlignment: .spaceBetween,
        children: [
          SizedBox(height: 44, child: _seekGroup(labelWidth)),
          _ThreeUp(
            height: 52,
            left: group(av, gap: kAvKeyGap),
            center: group([
              ...shown(const [BarControl.skipBack]),
              play,
              ...shown(const [BarControl.skipForward]),
            ]),
            right: group(right),
          ),
        ],
      );
    } else {
      content = Row(
        spacing: 12,
        children: [
          Expanded(child: _seekGroup(labelWidth)),
          play,
          if (av.isNotEmpty) group(av, gap: kAvKeyGap),
          ?more,
        ],
      );
    }

    final inner = widget.docked
        ? Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: form.twoRows ? 7 : 0),
            child: SizedBox(height: form.height - 1 - (form.twoRows ? 14 : 0), child: content),
          )
        : Padding(
            padding: EdgeInsets.symmetric(horizontal: 11, vertical: form.twoRows ? 7 : 0),
            child: SizedBox(height: form.height - 2 - (form.twoRows ? 14 : 0), child: content),
          );
    final body = Column(mainAxisSize: .min, children: [inner, _hint(gap: 6)]);
    final shell = widget.docked
        ? DecoratedBox(
            key: _panelKey,
            decoration: const BoxDecoration(
              color: PTColors.canvas,
              border: Border(top: BorderSide(color: PTColors.aisle)),
            ),
            child: body,
          )
        : GlassPanel(
            key: _panelKey,
            radius: PTRadius.panel,
            baseColor: PTColors.surfaceBase,
            child: body,
          );
    // The form steps down when the slot narrows; the panel's height follows it
    // rather than jumping.
    return AnimatedSize(
      duration: PTMotion.functional(context, PTMotion.state),
      curve: PTMotion.enter,
      alignment: .bottomCenter,
      child: shell,
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
            decoration: BoxDecoration(
              color: _hovered && enabled ? PTColors.aisle : Colors.transparent,
              borderRadius: BorderRadius.circular(PTRadius.control),
            ),
            // `widthFactor: 1` keeps a key with no fixed width at its text's
            // width: a bare `alignment` fills whatever it is offered, which
            // an adaptive row measures as 100000 px.
            child: Center(
              widthFactor: widget.width == null ? 1 : null,
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
      ),
    );
    if (widget.tooltip != null) key = Tooltip(message: widget.tooltip!, child: key);
    return key;
  }
}

/// The Brass lock on a camera key the room's tier does not grant.
extension on Widget {
  Widget withTrialTag(int? minutes) => minutes == null
      ? this
      : Stack(
          clipBehavior: Clip.none,
          children: [
            this,
            Positioned(top: -6, right: -8, child: _TrialTag(minutes: minutes)),
          ],
        );
}

/// "10M" on the camera key while a free room's video trial is on offer.
class _TrialTag extends StatelessWidget {
  const _TrialTag({required this.minutes});

  final int minutes;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(color: PTColors.primary, borderRadius: BorderRadius.circular(2)),
        child: Text(
          '${minutes}M',
          textScaler: TextScaler.noScaling,
          style: PTText.label.copyWith(
            fontSize: 9,
            letterSpacing: 0,
            fontWeight: .w600,
            color: PTColors.onAccent,
          ),
        ),
      ),
    );
  }
}

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

/// One control in both of its faces: the inline key, and its row in More.
class _Ctl {
  const _Ctl(this.inline, this.row, {this.live = false});

  final Widget inline;
  final AdaptiveAction row;

  /// A hot mic or camera: Signal on the More button while it is folded.
  final bool live;
}

/// Row two of the two-row forms: a group at each end and the transport between
/// them, dead centre whenever neither end group reaches it and nudged aside
/// just far enough when one does (an ordinary `Row` with two `Expanded` ends
/// would give both ends the same width and overflow the longer group).
class _ThreeUp extends StatelessWidget {
  const _ThreeUp({
    required this.height,
    required this.left,
    required this.center,
    required this.right,
  });

  final double height;
  final Widget left;
  final Widget center;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: CustomMultiChildLayout(
        delegate: _ThreeUpDelegate(),
        children: [
          LayoutId(id: #left, child: left),
          LayoutId(id: #center, child: center),
          LayoutId(id: #right, child: right),
        ],
      ),
    );
  }
}

class _ThreeUpDelegate extends MultiChildLayoutDelegate {
  @override
  void performLayout(Size size) {
    final loose = BoxConstraints.loose(size);
    final l = layoutChild(#left, loose);
    final c = layoutChild(#center, loose);
    final r = layoutChild(#right, loose);
    double y(Size s) => (size.height - s.height) / 2;
    positionChild(#left, Offset(0, y(l)));
    positionChild(#right, Offset(size.width - r.width, y(r)));
    final lo = l.width;
    final hi = math.max(lo, size.width - r.width - c.width);
    positionChild(#center, Offset((size.width / 2 - c.width / 2).clamp(lo, hi), y(c)));
  }

  @override
  bool shouldRelayout(_ThreeUpDelegate old) => false;
}
