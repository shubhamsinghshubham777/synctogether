import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:synctogether/ui/cinema_marquee_bar.dart';
import 'package:synctogether/ui/pt_motion.dart';

/// The docked chat column's width in the theatre layout.
const kTheaterChatWidth = 360.0;

/// The chat column never takes more than this share of the window, so a
/// 900 px window still leaves the picture most of the width.
const kTheaterChatShare = 0.32;

/// The docked desktop theatre. Nothing floats over anything:
///
///     +------------------------------------------+
///     | marquee bar (traffic lights, name, ...)  |   full width
///     +--------------------------------+---------+
///     |                                |  chat   |
///     |  stage (video, cams, banners)  |  column |
///     +--------------------------------+  (full  |
///     |  control bar                   |  height)|
///     +--------------------------------+---------+
///
/// The marquee bar carries the window controls, so in a window it never
/// collapses. In fullscreen, where there are none, it and the control bar
/// collapse together (H or a click on the picture) and the picture grows.
class RoomTheaterLayout extends StatelessWidget {
  const RoomTheaterLayout({
    required this.videoSurface,
    required this.topBar,
    required this.controlBar,
    required this.reactionStrip,
    required this.bannerStack,
    required this.showControlsButton,
    required this.fullscreen,
    required this.controlsVisible,
    required this.cursorVisible,
    required this.reactOpen,
    required this.chatCurve,
    required this.chatAnim,
    required this.onMouseMove,
    this.facecamRail,
    this.showCamsPill,
    this.overlayChat,
    this.chatPanel,
    super.key,
  });

  final Widget videoSurface;
  final Widget topBar;
  final Widget controlBar;
  final Widget reactionStrip;
  final Widget bannerStack;
  final Widget showControlsButton;
  final bool fullscreen;
  final bool controlsVisible;
  final bool cursorVisible;
  final bool reactOpen;
  final Animation<double> chatCurve;
  final Animation<double> chatAnim;
  final VoidCallback onMouseMove;
  final Widget? facecamRail;
  final Widget? showCamsPill;
  final Widget? overlayChat;
  final Widget? chatPanel;

  @override
  Widget build(BuildContext context) {
    final camsUp = facecamRail != null || showCamsPill != null;

    final stage = Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        Positioned.fill(
          child: ColoredBox(color: Colors.black, child: videoSurface),
        ),
        Positioned(
          top: 20,
          left: camsUp ? 216 : 20,
          right: camsUp ? 216 : 20,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: bannerStack,
            ),
          ),
        ),
        if (facecamRail != null) Positioned(top: 20, left: 20, child: facecamRail!),
        if (showCamsPill != null) Positioned(top: 20, left: 20, child: showCamsPill!),
        if (overlayChat != null)
          Positioned(left: 20, bottom: reactOpen ? 88 : 20, width: 340, child: overlayChat!),
        Positioned(left: 20, right: 20, bottom: 16, child: Center(child: reactionStrip)),
        Positioned(bottom: 14, right: 16, child: showControlsButton),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CollapsibleBar(shown: controlsVisible || !fullscreen, fromTop: true, child: topBar),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              final chatWidth = (box.maxWidth * kTheaterChatShare).clamp(280.0, kTheaterChatWidth);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: MouseRegion(
                            onHover: (_) => onMouseMove(),
                            cursor: (controlsVisible || cursorVisible)
                                ? MouseCursor.defer
                                : SystemMouseCursors.none,
                            child: stage,
                          ),
                        ),
                        _CollapsibleBar(shown: controlsVisible, fromTop: false, child: controlBar),
                      ],
                    ),
                  ),
                  if (chatPanel != null)
                    // The column opens by width, so the picture re-centres as
                    // the chat arrives rather than being covered by it. It
                    // unmounts at rest: its composer owns an OverlayPortal.
                    AnimatedBuilder(
                      animation: chatCurve,
                      child: chatPanel,
                      builder: (context, child) {
                        final t = chatCurve.value;
                        if (t == 0) return const SizedBox.shrink();
                        return IgnorePointer(
                          ignoring: chatAnim.status == AnimationStatus.reverse,
                          child: ClipRect(
                            child: SizedBox(
                              width: chatWidth * t,
                              child: OverflowBox(
                                alignment: Alignment.centerLeft,
                                minWidth: chatWidth,
                                maxWidth: chatWidth,
                                child: child,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Slides a bar's slot shut (and stops it taking clicks) rather than fading it
/// over the picture: the picture is resized by it, not covered.
///
/// It clips only while moving. At rest and open the bar must be free to draw
/// outside its slot - the scrub preview chip rises above the control bar into
/// the picture's area, and a standing clip cut it off. While sliding, the clip
/// stops a half-collapsed bar (whose child keeps its full height) from
/// painting over the picture.
class _CollapsibleBar extends StatefulWidget {
  const _CollapsibleBar({required this.shown, required this.fromTop, required this.child});

  final bool shown;
  final bool fromTop;
  final Widget child;

  @override
  State<_CollapsibleBar> createState() => _CollapsibleBarState();
}

class _CollapsibleBarState extends State<_CollapsibleBar> {
  late bool _settledOpen = widget.shown;

  @override
  void didUpdateWidget(_CollapsibleBar old) {
    super.didUpdateWidget(old);
    if (old.shown != widget.shown) _settledOpen = false;
  }

  void _onEnd() {
    if (widget.shown && !_settledOpen) setState(() => _settledOpen = true);
  }

  @override
  Widget build(BuildContext context) {
    final shown = widget.shown;
    return IgnorePointer(
      ignoring: !shown,
      child: ClipRect(
        clipBehavior: _settledOpen && shown ? Clip.none : Clip.hardEdge,
        child: AnimatedAlign(
          duration: PTMotion.functional(context, PTMotion.state),
          curve: shown ? PTMotion.enter : PTMotion.exit,
          alignment: widget.fromTop ? Alignment.topCenter : Alignment.bottomCenter,
          heightFactor: shown ? 1.0 : 0.0,
          onEnd: _onEnd,
          child: widget.child,
        ),
      ),
    );
  }
}

/// The desktop and landscape tablet roomy layout: full-bleed video, floating chrome, docked chat.
/// The facecam rail's footprint from the window's left edge: 24 in, 200 wide,
/// and a 16 gap.
const kRailReserve = 24.0 + 200.0 + 16.0;

/// How much of the left of a [box] the picture must give up to stay clear of
/// the facecam rail (touch roomy layouts). Zero when a 16:9 picture centred in
/// [box] already leaves the rail's column free (tall windows, tablets);
/// otherwise just enough to push the picture's left edge to the rail's, up to
/// the whole column. Continuous in [box], so a resize never snaps the picture.
double railClearance(Size box) {
  final picture = math.min(box.width, box.height * 16 / 9);
  return (2 * kRailReserve - (box.width - picture)).clamp(0.0, kRailReserve);
}

class RoomRoomyLayout extends StatefulWidget {
  const RoomRoomyLayout({
    required this.videoSurface,
    required this.topActions,
    required this.bannerStack,
    required this.reactionStrip,
    required this.controlBar,
    required this.showControlsButton,
    required this.chatOpen,
    required this.chatMotion,
    required this.controlsVisible,
    required this.cursorVisible,
    required this.reactOpen,
    required this.hasAv,
    required this.touch,
    required this.onMouseMove,
    required this.overlayControls,
    this.facecamRail,
    this.showCamsPill,
    this.chatRevealed,
    this.chatDisplaced,
    this.fullscreen = false,
    super.key,
  });

  final Widget videoSurface;
  final Widget topActions;
  final Widget bannerStack;
  final Widget reactionStrip;
  final Widget controlBar;
  final Widget showControlsButton;
  final bool chatOpen;
  final Duration chatMotion;
  final bool controlsVisible;
  final bool cursorVisible;
  final bool reactOpen;
  final bool hasAv;
  final bool touch;
  final VoidCallback onMouseMove;
  final Widget Function(Widget child, {bool fromTop}) overlayControls;
  final Widget? facecamRail;
  final Widget? showCamsPill;
  final Widget? chatRevealed;
  final Widget? chatDisplaced;
  final bool fullscreen;

  @override
  State<RoomRoomyLayout> createState() => _RoomRoomyLayoutState();
}

class _RoomRoomyLayoutState extends State<RoomRoomyLayout> {
  final _stackKey = GlobalKey();

  /// Height of the reaction strip + control bar stack. On touch the bar is
  /// taller than the desktop one (44px targets), so the docked chat sizes its
  /// bottom inset from this instead of a fixed number.
  double _stackHeight = 0;

  void _measureStack() {
    final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    if ((box.size.height - _stackHeight).abs() > 0.5 && mounted) {
      setState(() => _stackHeight = box.size.height);
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureStack());
    final isMac = defaultTargetPlatform == TargetPlatform.macOS;
    final isWindows = defaultTargetPlatform == TargetPlatform.windows;
    final topBarLeft = (isMac && !widget.fullscreen && !widget.touch)
        ? (CinemaMarqueeBar.macOsTrafficLightInset + 2.0)
        : 16.0;
    final showWindowsButtons = isWindows && !widget.fullscreen && !widget.touch;
    final topBarRight = showWindowsButtons ? 146.0 : 16.0;
    final topHiddenOffset = (widget.fullscreen || !isMac || widget.touch) ? 20.0 : 48.0;
    final facecamTop = widget.controlsVisible ? 84.0 : topHiddenOffset;
    final camsPillTop = widget.controlsVisible ? 84.0 : topHiddenOffset;
    final bannerTop = widget.controlsVisible ? 90.0 : topHiddenOffset;
    final bannerLeft = widget.hasAv
        ? 240.0
        : ((isMac && !widget.fullscreen && !widget.touch) ? 80.0 : 24.0);

    final stack = Stack(
      children: [
        // On touch the facecam rail's column is the rail's, not the picture's:
        // the surface gives up exactly as much as the picture would otherwise
        // run under it. The wrapper chain is the same either way, so the video
        // never remounts when cams come and go.
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, box) => AnimatedPadding(
              duration: PTMotion.functional(context, PTMotion.state),
              curve: PTMotion.enter,
              padding: EdgeInsets.only(
                left: widget.touch && widget.facecamRail != null ? railClearance(box.biggest) : 0,
              ),
              child: widget.videoSurface,
            ),
          ),
        ),
        Positioned.fill(
          child: SafeArea(
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: PTMotion.functional(context, PTMotion.state),
                  curve: widget.controlsVisible ? PTMotion.enter : PTMotion.exit,
                  top: 14,
                  left: topBarLeft,
                  right: topBarRight,
                  child: widget.overlayControls(widget.topActions, fromTop: true),
                ),
                if (showWindowsButtons)
                  Positioned(top: 0, right: 0, child: WindowsCaptionButtons(height: 48)),
                AnimatedPositioned(
                  duration: widget.chatMotion,
                  curve: widget.chatOpen ? Curves.easeOutCubic : Curves.easeInCubic,
                  top: bannerTop,
                  left: bannerLeft,
                  right: widget.chatOpen ? 332 : (widget.hasAv ? 240 : 24),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: widget.bannerStack,
                    ),
                  ),
                ),
                if (widget.facecamRail != null)
                  AnimatedPositioned(
                    duration: PTMotion.functional(context, PTMotion.state),
                    curve: widget.controlsVisible ? PTMotion.enter : PTMotion.exit,
                    top: facecamTop,
                    left: 24,
                    // On touch the column ends where the floating control bar
                    // begins (a gap above it), so no tile is parked behind the
                    // bar and a roster too long for the column scrolls inside
                    // it. Align keeps the rail as short as its tiles: only the
                    // tiles take touches, not the empty column under them.
                    bottom: widget.touch
                        ? (widget.controlsVisible ? math.max(20.0, 14 + _stackHeight + 12) : 20.0)
                        : null,
                    child: widget.touch
                        ? Align(alignment: Alignment.topLeft, child: widget.facecamRail!)
                        : widget.facecamRail!,
                  ),
                if (widget.showCamsPill != null)
                  AnimatedPositioned(
                    duration: PTMotion.functional(context, PTMotion.state),
                    curve: widget.controlsVisible ? PTMotion.enter : PTMotion.exit,
                    top: camsPillTop,
                    left: 24,
                    child: widget.showCamsPill!,
                  ),
                if (widget.chatRevealed != null)
                  AnimatedPositioned(
                    duration: PTMotion.functional(context, PTMotion.state),
                    curve: widget.controlsVisible ? PTMotion.enter : PTMotion.exit,
                    top: widget.controlsVisible ? 70.0 : 20.0,
                    right: 16,
                    bottom: widget.controlsVisible
                        ? (widget.touch ? math.max(84.0, 14 + _stackHeight + 12) : 84.0)
                        : 20.0,
                    width: 300,
                    child: widget.chatRevealed!,
                  ),
                if (widget.chatDisplaced != null)
                  AnimatedPositioned(
                    duration: PTMotion.functional(context, PTMotion.state),
                    curve: widget.controlsVisible ? PTMotion.enter : PTMotion.exit,
                    left: 24,
                    bottom: widget.controlsVisible ? (widget.reactOpen ? 224.0 : 160.0) : 24.0,
                    width: 340,
                    child: widget.chatDisplaced!,
                  ),
                Positioned(
                  bottom: 14,
                  left: 16,
                  right: 16,
                  child: widget.overlayControls(
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      key: _stackKey,
                      children: [
                        widget.reactionStrip,
                        const SizedBox(height: 12),
                        widget.controlBar,
                      ],
                    ),
                    fromTop: false,
                  ),
                ),
                Positioned(bottom: 14, right: 16, child: widget.showControlsButton),
              ],
            ),
          ),
        ),
      ],
    );

    if (widget.touch) return stack;
    return MouseRegion(
      onHover: (_) => widget.onMouseMove(),
      cursor: (widget.controlsVisible || widget.cursorVisible)
          ? MouseCursor.defer
          : SystemMouseCursors.none,
      child: stack,
    );
  }
}
