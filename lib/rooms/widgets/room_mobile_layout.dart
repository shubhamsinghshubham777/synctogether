import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:synctogether/ui/pt_motion.dart';
import 'package:synctogether/ui/responsive.dart';

import 'room_bar_form.dart';

/// The text scale the layouts size their floors with. A floor that followed
/// the full 2x pushed the transport out of a 568 px phone; the text itself
/// still scales, the room reserved for it stops growing here.
TextScaler floorScaler(BuildContext context) =>
    MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);

/// Stacks children scrollably above the chat panel for in-flow layouts.
class RoomAboveChat extends StatelessWidget {
  const RoomAboveChat({required this.chat, required this.children, super.key});

  final List<Widget> children;
  final Widget chat;

  @override
  Widget build(BuildContext context) {
    final floor = floorScaler(context).scale(160);
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

/// Where a child sits in [RoomPortraitStack], top to bottom.
enum RoomPortraitRole { header, video, cams, strip, bar, banners, chat }

class _PortraitParentData extends ContainerBoxParentData<RenderBox> {
  RoomPortraitRole? role;
  bool shown = true;
}

/// Tags a child of [RoomPortraitStack] with its role.
class RoomPortraitSlot extends ParentDataWidget<_PortraitParentData> {
  const RoomPortraitSlot({super.key, required this.role, required super.child});

  final RoomPortraitRole role;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as _PortraitParentData;
    if (data.role != role) {
      data.role = role;
      renderObject.parent?.markNeedsLayout();
    }
  }

  @override
  Type get debugTypicalAncestorWidgetClass => RoomPortraitStack;
}

/// The portrait room, stacked by priority rather than by order.
///
/// A plain `Column` hands every non-flex child its natural height and leaves
/// the rest to whoever is `Expanded`, so at 2x text on a 568 px phone the
/// transport was the thing that ran out of room. Here the budget is spent in
/// the order of what matters: the header, then the **transport bar** (never
/// squeezed, never scrolled away), then the reaction strip, then the picture
/// (up to 16:9, shrinking first), and the chat keeps [chatFloor] before the
/// roster strip and the banners get anything. A roster strip or reaction strip
/// that does not fit whole is hidden, not clipped; banners scroll in what is
/// left. Only when the window cannot hold the header and the bar plus the
/// chat floor does the chat give way - the bar still does not.
class RoomPortraitStack extends MultiChildRenderObjectWidget {
  const RoomPortraitStack({super.key, required this.chatFloor, required super.children});

  /// The least height the chat is given while anything above it can still give.
  final double chatFloor;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderRoomPortraitStack(chatFloor);

  @override
  void updateRenderObject(BuildContext context, RenderRoomPortraitStack renderObject) {
    renderObject.chatFloor = chatFloor;
  }
}

class RenderRoomPortraitStack extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _PortraitParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _PortraitParentData> {
  RenderRoomPortraitStack(this._chatFloor);

  double _chatFloor;
  set chatFloor(double v) {
    if (_chatFloor == v) return;
    _chatFloor = v;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _PortraitParentData) child.parentData = _PortraitParentData();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  RenderBox? _by(RoomPortraitRole role) {
    for (var c = firstChild; c != null; c = childAfter(c)) {
      if ((c.parentData! as _PortraitParentData).role == role) return c;
    }
    return null;
  }

  @override
  void performLayout() {
    final width = size.width;
    final height = size.height;
    BoxConstraints loose(double maxH) =>
        BoxConstraints(minWidth: width, maxWidth: width, maxHeight: math.max(0, maxH));
    BoxConstraints tight(double h) => BoxConstraints.tightFor(width: width, height: math.max(0, h));
    const natural = double.infinity;

    final heights = <RoomPortraitRole, double>{};
    void place(RoomPortraitRole role, RenderBox? box, {required bool shown, required double h}) {
      if (box == null) return;
      (box.parentData! as _PortraitParentData).shown = shown;
      heights[role] = shown ? h : 0;
    }

    final header = _by(.header);
    final bar = _by(.bar);
    var headerH = 0.0;
    if (header != null) {
      // Natural height, like a Column's non-flex child: a header whose inner
      // Column is `max` would otherwise fill whatever height it is offered.
      header.layout(loose(natural), parentUsesSize: true);
      headerH = header.size.height;
    }
    var barH = 0.0;
    if (bar != null) {
      bar.layout(loose(natural), parentUsesSize: true);
      barH = bar.size.height;
    }
    place(.header, header, shown: true, h: headerH);
    place(.bar, bar, shown: true, h: barH);

    // What the chat can spare: everything under the header and the bar, minus
    // the chat's own floor.
    var budget = math.max(0.0, height - headerH - barH - _chatFloor);

    // A piece that must show whole or not at all.
    void wholeOrHidden(RoomPortraitRole role) {
      final box = _by(role);
      if (box == null) return;
      box.layout(loose(natural), parentUsesSize: true);
      final fits = box.size.height <= budget;
      if (fits) budget -= box.size.height;
      place(role, box, shown: fits, h: box.size.height);
    }

    wholeOrHidden(.strip);

    final video = _by(.video);
    if (video != null) {
      final ideal = width * 9 / 16;
      final h = math.min(ideal, budget);
      video.layout(tight(h), parentUsesSize: true);
      budget -= h;
      place(.video, video, shown: true, h: h);
    }

    wholeOrHidden(.cams);

    final banners = _by(.banners);
    if (banners != null) {
      banners.layout(loose(budget), parentUsesSize: true);
      final h = banners.size.height;
      budget -= h;
      place(.banners, banners, shown: h > 0, h: h);
    }

    final used = heights.values.fold(0.0, (a, b) => a + b);
    final chat = _by(.chat);
    if (chat != null) {
      final h = math.max(0.0, height - used);
      chat.layout(tight(h), parentUsesSize: true);
      place(.chat, chat, shown: true, h: h);
    }

    var y = 0.0;
    for (final role in RoomPortraitRole.values) {
      final box = _by(role);
      if (box == null) continue;
      (box.parentData! as _PortraitParentData).offset = Offset(0, y);
      y += heights[role] ?? 0;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    for (var c = firstChild; c != null; c = childAfter(c)) {
      final data = c.parentData! as _PortraitParentData;
      if (data.shown) context.paintChild(c, data.offset + offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (var c = lastChild; c != null; c = childBefore(c)) {
      final data = c.parentData! as _PortraitParentData;
      if (!data.shown) continue;
      final hit = result.addWithPaintOffset(
        offset: data.offset,
        position: position,
        hitTest: (result, transformed) => c!.hitTest(result, position: transformed),
      );
      if (hit) return true;
    }
    return false;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    for (var c = firstChild; c != null; c = childAfter(c)) {
      if ((c.parentData! as _PortraitParentData).shown) visitor(c);
    }
  }
}

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
    this.chatFloorExtra = 0,
    super.key,
  });

  /// Height the chat keeps on top of its floor: the inline emoji picker's strip
  /// while it holds the keyboard's place. Reserved here, above the chat, so the
  /// picture and strips give way exactly as they did for the keyboard.
  final double chatFloorExtra;

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

    return SafeArea(
      child: RoomPortraitStack(
        chatFloor: floorScaler(context).scale(160) + chatFloorExtra,
        children: [
          RoomPortraitSlot(
            role: .header,
            child: _Collapse(collapsed: keyboardUp, child: header),
          ),
          RoomPortraitSlot(role: .video, child: videoSurface),
          if (facecamStrip != null)
            RoomPortraitSlot(
              role: .cams,
              child: Padding(
                padding: EdgeInsets.fromLTRB(gutter, 10, gutter, 6),
                child: facecamStrip!,
              ),
            ),
          RoomPortraitSlot(
            role: .strip,
            child: Padding(
              padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 6),
              child: reactionStrip,
            ),
          ),
          RoomPortraitSlot(role: .bar, child: controlBar),
          RoomPortraitSlot(
            role: .banners,
            child: SingleChildScrollView(child: bannerStack),
          ),
          RoomPortraitSlot(role: .chat, child: embeddedChat),
        ],
      ),
    );
  }
}

/// Folds [child] away to nothing (and back) over [PTMotion.state].
///
/// The portrait room hides its header while the soft keyboard or the inline
/// emoji picker holds the lower half. Removing it outright moved everything
/// beneath it by its whole height in a single frame, on top of the keyboard's
/// own slide; folding it makes one continuous motion of it. The header stays
/// mounted (a mounted subtree costs nothing here - no per-frame work, one
/// animation only when the state flips), but while folded it is out of focus,
/// out of semantics and, being zero tall, out of hit testing.
class _Collapse extends StatelessWidget {
  const _Collapse({required this.collapsed, required this.child});

  final bool collapsed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: collapsed ? 0.0 : 1.0),
      duration: PTMotion.functional(context, PTMotion.state),
      curve: PTMotion.enter,
      child: child,
      builder: (context, t, child) => ExcludeFocus(
        excluding: t < 0.01,
        child: ExcludeSemantics(
          excluding: t < 0.01,
          child: ClipRect(
            child: Align(alignment: .topCenter, heightFactor: t, child: child),
          ),
        ),
      ),
    );
  }
}

/// Bottom clearance for things beside the landscape controls when the show-
/// controls chevron is all that is left: the chevron and a gap.
const double kLandscapeChevronReserve = 76;

/// The mobile landscape fullscreen video composition.
class RoomMobileLandscapeLayout extends StatelessWidget {
  const RoomMobileLandscapeLayout({
    required this.videoSurface,
    required this.topActionsBuilder,
    required this.bannerStack,
    required this.reactionStrip,
    required this.controlBar,
    required this.barCaps,
    required this.showControlsButton,
    required this.controlsVisible,
    required this.cursorVisible,
    required this.chatOpen,
    required this.reactOpen,
    required this.onMouseMove,
    required this.overlayControls,
    this.facecamRailBuilder,
    this.chatDisplacedOverlay,
    this.chatRevealedBuilder,
    super.key,
  });

  final Widget videoSurface;
  final Widget Function(bool keyboardMode) topActionsBuilder;
  final Widget bannerStack;
  final Widget reactionStrip;
  final Widget controlBar;

  /// What the bar carries, so the layout can choose its form before the bar is
  /// built: the form decides the bar's height, which decides the rail's slot.
  final RoomBarCaps barCaps;
  final Widget showControlsButton;
  final bool controlsVisible;
  final bool cursorVisible;
  final bool chatOpen;
  final bool reactOpen;
  final VoidCallback onMouseMove;
  final Widget Function(Widget child, {bool fromTop}) overlayControls;

  /// The facecam rail, built for the tile size and count its slot holds.
  final Widget Function(RailPlan plan)? facecamRailBuilder;
  final Widget? chatDisplacedOverlay;
  final Widget Function(double chatWidth)? chatRevealedBuilder;

  @override
  Widget build(BuildContext context) {
    final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;
    // The chat panel's own need: it scales with the text, so this floor does too.
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
                final safeWidth = box.maxWidth;
                // Chat is a column beside the controls, never over them. The
                // bar's slot never drops under 332, so chat gives way first;
                // where even its own floor will not fit it takes the keyboard
                // slot over the bar instead.
                final chatWidth = landscapeChatWidth(safeWidth);
                final bannerWidth = math.min(420.0, safeWidth * 0.55);
                // A short window gives the chat the whole right-hand column
                // (the pill row steps aside for it); the bar stays beside it.
                // Only the soft keyboard, or a window too narrow for a chat
                // column and the bar's floor at once, lets the chat take the
                // bar's slot.
                final barHidden = chatOpen && (keyboardUp || !landscapeChatFits(safeWidth));
                final tallChat = barHidden || (chatOpen && box.maxHeight - 72 - 22 < floor);
                final beside = chatOpen && !barHidden ? chatWidth + 12 : 0.0;
                final motion = PTMotion.functional(context, PTMotion.state);
                final curve = controlsVisible ? PTMotion.enter : PTMotion.exit;

                // Form: the first that fits the slot beside the chat and, with
                // facecams on, leaves a rail slot that holds two tiles and +N.
                final scaler = MediaQuery.textScalerOf(context);
                final form = pickBarForm(
                  slot: safeWidth - beside,
                  caps: barCaps,
                  scaler: scaler,
                  accepts: facecamRailBuilder == null
                      ? null
                      : (f) => railPlanFor(railSlotHeight(box.maxHeight, f)).holdsTwo,
                );
                final railBottom = barHidden
                    ? 16.0
                    : controlsVisible
                    ? landscapeControlsReserve(form) + kRailGap
                    : kLandscapeChevronReserve;
                final plan = railPlanFor(box.maxHeight - railBottom - kRailTop);
                // Beside the chat, never under it.
                final railRight = chatOpen ? chatWidth + 12 : 0.0;

                return Stack(
                  children: [
                    Positioned(
                      top: 16,
                      left: 0,
                      right: tallChat ? chatWidth + 12 : 0,
                      child: overlayControls(topActionsBuilder(tallChat), fromTop: true),
                    ),
                    if (facecamRailBuilder != null)
                      // Bounded above the control bar (or the show-controls
                      // chevron when it is hidden); the rail fits its tiles to
                      // this slot and folds the rest into "+N".
                      AnimatedPositioned(
                        duration: motion,
                        curve: curve,
                        top: kRailTop,
                        right: railRight,
                        bottom: railBottom,
                        width: plan.tileWidth,
                        child: Align(alignment: .topRight, child: facecamRailBuilder!(plan)),
                      ),
                    Positioned(top: 66, left: 0, width: bannerWidth, child: bannerStack),
                    if (chatDisplacedOverlay != null)
                      AnimatedPositioned(
                        duration: motion,
                        curve: curve,
                        left: 0,
                        bottom: controlsVisible
                            ? landscapeControlsReserve(form) + 4 + (reactOpen ? 52 : 0)
                            : 16.0,
                        width: chatWidth,
                        child: chatDisplacedOverlay!,
                      ),
                    if (!barHidden) ...[
                      AnimatedPositioned(
                        duration: motion,
                        curve: curve,
                        bottom: kLandscapeBarInset,
                        left: 0,
                        right: beside,
                        child: overlayControls(
                          RoomBarFormScope(
                            form: form,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [reactionStrip, controlBar],
                            ),
                          ),
                          fromTop: false,
                        ),
                      ),
                      AnimatedPositioned(
                        duration: motion,
                        curve: curve,
                        bottom: kLandscapeBarInset,
                        right: beside,
                        child: showControlsButton,
                      ),
                    ],
                    if (chatRevealedBuilder != null)
                      AnimatedPositioned(
                        duration: motion,
                        curve: curve,
                        top: tallChat ? 8 : 72,
                        right: 0,
                        bottom: tallChat ? 8 : 22,
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
