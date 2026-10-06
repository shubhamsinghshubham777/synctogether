import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
class RoomRoomyLayout extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final isMac = defaultTargetPlatform == TargetPlatform.macOS;
    final isWindows = defaultTargetPlatform == TargetPlatform.windows;
    final topBarLeft = (isMac && !fullscreen && !touch)
        ? (CinemaMarqueeBar.macOsTrafficLightInset + 2.0)
        : 16.0;
    final showWindowsButtons = isWindows && !fullscreen && !touch;
    final topBarRight = showWindowsButtons ? 146.0 : 16.0;
    final topHiddenOffset = (fullscreen || !isMac || touch) ? 20.0 : 48.0;
    final facecamTop = controlsVisible ? 84.0 : topHiddenOffset;
    final camsPillTop = controlsVisible ? 84.0 : topHiddenOffset;
    final bannerTop = controlsVisible ? 90.0 : topHiddenOffset;
    final bannerLeft = hasAv ? 240.0 : ((isMac && !fullscreen && !touch) ? 80.0 : 24.0);

    final stack = Stack(
      children: [
        Positioned.fill(child: videoSurface),
        Positioned.fill(
          child: SafeArea(
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: PTMotion.functional(context, PTMotion.state),
                  curve: controlsVisible ? PTMotion.enter : PTMotion.exit,
                  top: 14,
                  left: topBarLeft,
                  right: topBarRight,
                  child: overlayControls(topActions, fromTop: true),
                ),
                if (showWindowsButtons)
                  Positioned(top: 0, right: 0, child: WindowsCaptionButtons(height: 48)),
                AnimatedPositioned(
                  duration: chatMotion,
                  curve: chatOpen ? Curves.easeOutCubic : Curves.easeInCubic,
                  top: bannerTop,
                  left: bannerLeft,
                  right: chatOpen ? 332 : (hasAv ? 240 : 24),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: bannerStack,
                    ),
                  ),
                ),
                if (facecamRail != null)
                  AnimatedPositioned(
                    duration: PTMotion.functional(context, PTMotion.state),
                    curve: controlsVisible ? PTMotion.enter : PTMotion.exit,
                    top: facecamTop,
                    left: 24,
                    child: facecamRail!,
                  ),
                if (showCamsPill != null)
                  AnimatedPositioned(
                    duration: PTMotion.functional(context, PTMotion.state),
                    curve: controlsVisible ? PTMotion.enter : PTMotion.exit,
                    top: camsPillTop,
                    left: 24,
                    child: showCamsPill!,
                  ),
                if (chatRevealed != null)
                  AnimatedPositioned(
                    duration: PTMotion.functional(context, PTMotion.state),
                    curve: controlsVisible ? PTMotion.enter : PTMotion.exit,
                    top: controlsVisible ? 70.0 : 20.0,
                    right: 16,
                    bottom: controlsVisible ? 84.0 : 20.0,
                    width: 300,
                    child: chatRevealed!,
                  ),
                if (chatDisplaced != null)
                  AnimatedPositioned(
                    duration: PTMotion.functional(context, PTMotion.state),
                    curve: controlsVisible ? PTMotion.enter : PTMotion.exit,
                    left: 24,
                    bottom: controlsVisible ? (reactOpen ? 224.0 : 160.0) : 24.0,
                    width: 340,
                    child: chatDisplaced!,
                  ),
                Positioned(
                  bottom: 14,
                  left: 16,
                  right: 16,
                  child: overlayControls(
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [reactionStrip, const SizedBox(height: 12), controlBar],
                    ),
                    fromTop: false,
                  ),
                ),
                Positioned(bottom: 14, right: 16, child: showControlsButton),
              ],
            ),
          ),
        ),
      ],
    );

    if (touch) return stack;
    return MouseRegion(
      onHover: (_) => onMouseMove(),
      cursor: (controlsVisible || cursorVisible) ? MouseCursor.defer : SystemMouseCursors.none,
      child: stack,
    );
  }
}
