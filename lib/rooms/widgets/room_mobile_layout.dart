import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:synctogether/ui/pt_motion.dart';
import 'package:synctogether/ui/responsive.dart';

/// Stacks children scrollably above the chat panel for in-flow layouts.
class RoomAboveChat extends StatelessWidget {
  const RoomAboveChat({required this.chat, required this.children, super.key});

  final List<Widget> children;
  final Widget chat;

  @override
  Widget build(BuildContext context) {
    final floor = MediaQuery.textScalerOf(context).scale(160);
    return LayoutBuilder(
      builder: (context, box) {
        return Column(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: math.max(0.0, box.maxHeight - floor)),
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: children),
              ),
            ),
            Expanded(child: chat),
          ],
        );
      },
    );
  }
}

/// Natural height of the portrait transport plus an open reaction strip, which
/// the keyboard-up layout reserves before sizing the picture.
const double kPortraitControlsExtent = 170;

/// The handheld and portrait tablet composition.
class RoomMobilePortraitLayout extends StatelessWidget {
  const RoomMobilePortraitLayout({
    required this.header,
    required this.videoSurface,
    required this.reactionStrip,
    required this.controlBar,
    required this.bannerStack,
    required this.embeddedChat,
    this.facecamStrip,
    this.roomy = false,
    this.keyboardUp = false,
    super.key,
  });

  /// Whether the soft keyboard is up. Passed in rather than read here: the
  /// Scaffold above consumes the bottom view inset, so by this point it is 0.
  final bool keyboardUp;

  final Widget header;
  final Widget videoSurface;
  final Widget reactionStrip;
  final Widget controlBar;
  final Widget bannerStack;
  final Widget embeddedChat;
  final Widget? facecamStrip;
  final bool roomy;

  @override
  Widget build(BuildContext context) {
    final gutter = roomy ? 24.0 : (MediaQuery.sizeOf(context).width < 380 ? 10.0 : 14.0);
    final chatFloor = MediaQuery.textScalerOf(context).scale(160);

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, box) {
          final headerHeight = keyboardUp ? 0.0 : MediaQuery.textScalerOf(context).scale(60);
          // With the keyboard up the picture is what gives: the transport and
          // the reaction strip keep their natural height (play must never
          // sit half-clipped in a scroll area), the picture shrinks to what
          // is left after them and the chat's floor.
          final controlsExtent = keyboardUp
              ? MediaQuery.textScalerOf(context).scale(kPortraitControlsExtent)
              : 0.0;
          final videoHeight = (box.maxHeight - chatFloor - headerHeight - controlsExtent).clamp(
            0.0,
            box.maxWidth * 9 / 16,
          );
          return Column(
            children: [
              if (!keyboardUp) header,
              SizedBox(height: videoHeight, child: videoSurface),
              if (facecamStrip != null)
                Padding(padding: EdgeInsets.fromLTRB(gutter, 10, gutter, 0), child: facecamStrip!),
              Expanded(
                child: RoomAboveChat(
                  chat: embeddedChat,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 0),
                      child: reactionStrip,
                    ),
                    controlBar,
                    bannerStack,
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Bottom clearance for things beside the landscape controls: the reaction
/// strip + control bar column (~130 px) above its 22 px inset, and a gap.
const double kLandscapeControlsReserve = 160;

/// The same with controls hidden: the show-controls chevron and a gap.
const double kLandscapeChevronReserve = 76;

/// The mobile landscape fullscreen video composition.
class RoomMobileLandscapeLayout extends StatelessWidget {
  const RoomMobileLandscapeLayout({
    required this.videoSurface,
    required this.topActionsBuilder,
    required this.bannerStack,
    required this.reactionStrip,
    required this.controlBar,
    required this.showControlsButton,
    required this.controlsVisible,
    required this.cursorVisible,
    required this.chatOpen,
    required this.reactOpen,
    required this.onMouseMove,
    required this.overlayControls,
    this.facecamRail,
    this.chatDisplacedOverlay,
    this.chatRevealedBuilder,
    super.key,
  });

  final Widget videoSurface;
  final Widget Function(bool keyboardMode) topActionsBuilder;
  final Widget bannerStack;
  final Widget reactionStrip;
  final Widget controlBar;
  final Widget showControlsButton;
  final bool controlsVisible;
  final bool cursorVisible;
  final bool chatOpen;
  final bool reactOpen;
  final VoidCallback onMouseMove;
  final Widget Function(Widget child, {bool fromTop}) overlayControls;
  final Widget? facecamRail;
  final Widget? chatDisplacedOverlay;
  final Widget Function(double chatWidth)? chatRevealedBuilder;

  @override
  Widget build(BuildContext context) {
    final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;
    final floor = MediaQuery.textScalerOf(context).scale(160);

    return MouseRegion(
      onHover: (_) => onMouseMove(),
      cursor: (controlsVisible || cursorVisible) ? MouseCursor.defer : SystemMouseCursors.none,
      child: Stack(
        children: [
          Positioned.fill(child: videoSurface),
          SafeArea(
            minimum: const EdgeInsets.symmetric(horizontal: 56),
            child: LayoutBuilder(
              builder: (context, box) {
                final chatWidth = math.min(300.0, box.maxWidth * 0.38);
                final bannerWidth = math.min(420.0, box.maxWidth * 0.55);
                // Chat is a column beside the controls, never over them: the
                // control bar is ~130 px tall and full width, so a panel that
                // merely stopped above it would be too short to read.
                final keyboardMode = chatOpen && (keyboardUp || box.maxHeight - 72 - 22 < floor);
                final beside = chatOpen && !keyboardMode ? chatWidth + 12 : 0.0;
                final motion = PTMotion.functional(context, PTMotion.state);
                final curve = controlsVisible ? PTMotion.enter : PTMotion.exit;

                return Stack(
                  children: [
                    Positioned(
                      top: 16,
                      left: 0,
                      right: keyboardMode ? chatWidth + 12 : 0,
                      child: overlayControls(topActionsBuilder(keyboardMode), fromTop: true),
                    ),
                    if (facecamRail != null)
                      // Bounded above the control bar (or the show-controls
                      // chevron when it is hidden); the rail fits its tiles to
                      // this slot and folds the rest into "+N".
                      Positioned(
                        top: 72,
                        right: 0,
                        bottom: controlsVisible
                            ? kLandscapeControlsReserve
                            : kLandscapeChevronReserve,
                        width: 104,
                        child: Align(alignment: Alignment.topRight, child: facecamRail!),
                      ),
                    Positioned(top: 66, left: 0, width: bannerWidth, child: bannerStack),
                    if (chatDisplacedOverlay != null)
                      AnimatedPositioned(
                        duration: PTMotion.functional(context, PTMotion.state),
                        curve: controlsVisible ? PTMotion.enter : PTMotion.exit,
                        left: 0,
                        bottom: controlsVisible ? (reactOpen ? 190.0 : 138.0) : 16.0,
                        width: chatWidth,
                        child: chatDisplacedOverlay!,
                      ),
                    if (!keyboardMode) ...[
                      AnimatedPositioned(
                        duration: motion,
                        curve: curve,
                        bottom: 22,
                        left: 0,
                        right: beside,
                        child: overlayControls(
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [reactionStrip, controlBar],
                          ),
                          fromTop: false,
                        ),
                      ),
                      AnimatedPositioned(
                        duration: motion,
                        curve: curve,
                        bottom: 22,
                        right: beside,
                        child: showControlsButton,
                      ),
                    ],
                    if (chatRevealedBuilder != null)
                      AnimatedPositioned(
                        duration: PTMotion.functional(context, PTMotion.state),
                        curve: controlsVisible ? PTMotion.enter : PTMotion.exit,
                        top: keyboardMode ? 8 : 72,
                        right: 0,
                        bottom: keyboardMode ? 8 : 22,
                        width: chatWidth,
                        child: chatRevealedBuilder!(chatWidth),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Splits the layout along a physical fold hinge.
class RoomFoldSplit extends StatelessWidget {
  const RoomFoldSplit({required this.fold, required this.first, required this.second, super.key});

  final PTFold fold;
  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final vertical = fold.axis == PTFoldAxis.vertical;
        final extent = vertical ? box.maxWidth : box.maxHeight;
        final start = (vertical ? fold.bounds.left : fold.bounds.top).clamp(0.0, extent);
        final end = (vertical ? fold.bounds.right : fold.bounds.bottom).clamp(start, extent);
        final children = [
          SizedBox(width: vertical ? start : null, height: vertical ? null : start, child: first),
          SizedBox(width: vertical ? end - start : null, height: vertical ? null : end - start),
          Expanded(child: second),
        ];
        return vertical ? Row(children: children) : Column(children: children);
      },
    );
  }
}
