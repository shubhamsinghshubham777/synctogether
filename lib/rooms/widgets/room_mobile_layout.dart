import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:synctogether/ui/pt_motion.dart';
import 'package:synctogether/ui/pt_theme.dart';
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

  /// Drawn at all (fully or part way through a fold).
  bool painted = true;

  /// Settled and present: the only state in which it takes touches, semantics
  /// and focus. A piece folding in or out is neither.
  bool shown = true;

  /// The slot is on its way out: it folds away whatever the budget says.
  bool retiring = false;

  /// Height of the visible slice while folding, null when whole.
  double? reveal;

  /// Opacity while folding.
  double fade = 1;
}

/// Tags a child of [RoomPortraitStack] with its role.
class RoomPortraitSlot extends ParentDataWidget<_PortraitParentData> {
  const RoomPortraitSlot({
    super.key,
    required this.role,
    required super.child,
    this.retiring = false,
  });

  final RoomPortraitRole role;

  /// Folds the piece out even where it would fit; the owner unmounts it once
  /// the fold has had time to finish.
  final bool retiring;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as _PortraitParentData;
    if (data.role != role || data.retiring != retiring) {
      data.role = role;
      data.retiring = retiring;
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
class RoomPortraitStack extends StatefulWidget {
  const RoomPortraitStack({super.key, required this.chatFloor, required this.children});

  /// The least height the chat is given while anything above it can still give.
  final double chatFloor;
  final List<Widget> children;

  @override
  State<RoomPortraitStack> createState() => _RoomPortraitStackState();
}

class _RoomPortraitStackState extends State<RoomPortraitStack> with SingleTickerProviderStateMixin {
  @override
  Widget build(BuildContext context) => _PortraitStackRender(
    vsync: this,
    chatFloor: widget.chatFloor,
    duration: PTMotion.functional(context, PTMotion.state),
    children: widget.children,
  );
}

class _PortraitStackRender extends MultiChildRenderObjectWidget {
  const _PortraitStackRender({
    required this.vsync,
    required this.chatFloor,
    required this.duration,
    required super.children,
  });

  final TickerProvider vsync;
  final double chatFloor;
  final Duration duration;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderRoomPortraitStack(vsync, chatFloor, duration);

  @override
  void updateRenderObject(BuildContext context, RenderRoomPortraitStack renderObject) {
    renderObject
      ..chatFloor = chatFloor
      ..duration = duration;
  }
}

/// Eased 0..1 "how much of the piece is present" for one role.
///
/// [progress] moves linearly towards the target at 1/duration per second and
/// [eased] shapes it, so reversing mid-fold continues from where it is (no jump)
/// and a piece never moves backwards while its target holds.
class _Presence {
  double progress = 0;
  bool target = false;
  bool seeded = false;

  double get eased => PTMotion.emphasized.transform(progress);
  bool get settled => progress == (target ? 1.0 : 0.0);

  /// True when [next] differs from the target already held. The first call
  /// seeds: a piece present at mount does not animate in, one that joins a
  /// stack that has already been laid out does.
  bool retarget(bool next, {required bool animateIn}) {
    if (!seeded) {
      seeded = true;
      target = next;
      progress = next && !animateIn ? 1 : 0;
      return next && animateIn;
    }
    if (next == target) return false;
    target = next;
    return true;
  }

  void advance(double step) {
    progress = target ? math.min(1.0, progress + step) : math.max(0.0, progress - step);
  }
}

/// Extra room (px) a hidden piece needs before it is brought back, over what it
/// needs to stay. Decisions are made on target heights; this band keeps a budget
/// that hovers at a threshold (the keyboard's slide and the header's fold both
/// move it) from flipping the target back and forth.
const double kPortraitReturnMargin = 8;

class RenderRoomPortraitStack extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _PortraitParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _PortraitParentData> {
  RenderRoomPortraitStack(this._vsync, this._chatFloor, this._duration) {
    _ticker = _vsync.createTicker(_tick);
  }

  final TickerProvider _vsync;
  late final Ticker _ticker;
  Duration _duration;
  Duration _last = Duration.zero;
  bool _laidOut = false;

  /// The pieces that fold in and out, rather than appearing whole.
  final _strip = _Presence();
  final _cams = _Presence();

  double _chatFloor;
  set chatFloor(double v) {
    if (_chatFloor == v) return;
    _chatFloor = v;
    markNeedsLayout();
  }

  set duration(Duration v) {
    if (_duration == v) return;
    _duration = v;
  }

  void _tick(Duration elapsed) {
    final dt = elapsed - _last;
    _last = elapsed;
    final step = _duration.inMicroseconds <= 0 ? 1.0 : dt.inMicroseconds / _duration.inMicroseconds;
    _strip.advance(step);
    _cams.advance(step);
    if (_strip.settled && _cams.settled) _ticker.stop();
    markNeedsLayout();
  }

  void _ensureTicking() {
    if ((_strip.settled && _cams.settled) || _ticker.isActive) return;
    _last = Duration.zero;
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
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
    var semanticsChanged = false;
    void place(
      RoomPortraitRole role,
      RenderBox? box, {
      required bool shown,
      required double h,
      bool? painted,
      double? reveal,
      double fade = 1,
    }) {
      if (box == null) return;
      final data = box.parentData! as _PortraitParentData;
      if (data.shown != shown) semanticsChanged = true;
      data
        ..shown = shown
        ..painted = painted ?? shown
        ..reveal = reveal
        ..fade = fade;
      heights[role] = h;
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

    // Two budgets. The target one decides what is present (on natural heights,
    // as if every fold had finished); the live one is what is left to spend this
    // frame once the folding pieces take their eased slice, so the chat never
    // dips under its floor while one of them grows.
    var target = math.max(0.0, height - headerH - barH - _chatFloor);
    var live = target;

    // A piece that folds whole in or out. Returns its allocated height.
    void fold(RoomPortraitRole role, _Presence presence) {
      final box = _by(role);
      if (box == null) {
        // Gone: when it returns it folds in rather than appearing whole.
        presence.seeded = false;
        return;
      }
      box.layout(loose(natural), parentUsesSize: true);
      final h = box.size.height;
      final retiring = (box.parentData! as _PortraitParentData).retiring;
      final fits =
          !retiring && (presence.target ? h <= target : h + kPortraitReturnMargin <= target);
      presence.retarget(fits, animateIn: _laidOut);
      if (presence.target) target -= h;
      final e = presence.eased;
      final alloc = math.min(h * e, live);
      live -= alloc;
      final whole = alloc >= h - 0.01;
      place(
        role,
        box,
        shown: presence.target && whole,
        painted: alloc > 0 || e > 0,
        h: alloc,
        reveal: whole ? null : alloc,
        fade: e,
      );
    }

    fold(.strip, _strip);

    final video = _by(.video);
    if (video != null) {
      final ideal = width * 9 / 16;
      final h = math.min(ideal, live);
      video.layout(tight(h), parentUsesSize: true);
      target -= math.min(ideal, target);
      live -= h;
      place(.video, video, shown: true, h: h);
    }

    fold(.cams, _cams);

    final banners = _by(.banners);
    if (banners != null) {
      banners.layout(loose(live), parentUsesSize: true);
      final h = banners.size.height;
      live -= h;
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

    if (semanticsChanged) markNeedsSemanticsUpdate();
    _laidOut = true;
    _ensureTicking();
  }

  void _paintChild(PaintingContext context, RenderBox c, _PortraitParentData d, Offset origin) {
    final at = d.offset + origin;
    final reveal = d.reveal;
    if (reveal == null && d.fade >= 1) {
      context.paintChild(c, at);
      return;
    }
    void clipped(PaintingContext ctx, Offset off) {
      if (reveal == null) {
        ctx.paintChild(c, off);
      } else {
        ctx.pushClipRect(
          needsCompositing,
          off,
          Offset.zero & Size(size.width, reveal),
          (ctx, off) => ctx.paintChild(c, off),
        );
      }
    }

    if (d.fade >= 1) {
      clipped(context, at);
    } else {
      context.pushOpacity(at, (d.fade.clamp(0.0, 1.0) * 255).round(), clipped);
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    for (var c = firstChild; c != null; c = childAfter(c)) {
      final data = c.parentData! as _PortraitParentData;
      if (data.painted) _paintChild(context, c, data, offset);
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
class RoomMobilePortraitLayout extends StatefulWidget {
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
    this.chatFloorReveal,
    super.key,
  });

  /// Height the chat keeps on top of its floor: the inline emoji picker's strip
  /// while it holds the keyboard's place. Reserved here, above the chat, so the
  /// picture and strips give way exactly as they did for the keyboard.
  final double chatFloorExtra;

  /// 0..1 share of [chatFloorExtra] currently held. The picker folds its strip
  /// open and closed when there is no keyboard to trade places with, and the
  /// floor follows it, so the picture and strips ease instead of snapping. Only
  /// the stack rebuilds per frame (the slots below are built once); null = 1.
  final ValueListenable<double>? chatFloorReveal;

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
  State<RoomMobilePortraitLayout> createState() => _RoomMobilePortraitLayoutState();
}

class _RoomMobilePortraitLayoutState extends State<RoomMobilePortraitLayout> {
  /// The facecam strip as it last was. Turning cams off removes the widget at
  /// once, which would take the slot with it and pop the strip out of the
  /// stack in one frame; it is kept (retiring) while the stack folds it away.
  Widget? _lastStrip;
  Timer? _drop;

  @override
  void dispose() {
    _drop?.cancel();
    super.dispose();
  }

  void _settleStrip(Widget? strip) {
    if (strip != null) {
      _drop?.cancel();
      _drop = null;
      _lastStrip = strip;
    } else if (_lastStrip != null && _drop == null) {
      // The fold runs PTMotion.state; the margin lets its last frame land.
      final fold = PTMotion.functional(context, PTMotion.state);
      _drop = Timer(fold + const Duration(milliseconds: 80), () {
        _drop = null;
        if (mounted) setState(() => _lastStrip = null);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    _settleStrip(w.facecamStrip);
    final cams = w.facecamStrip ?? _lastStrip;
    final gutter = w.roomy ? 24.0 : (MediaQuery.sizeOf(context).width < 380 ? 10.0 : 14.0);

    // A window this short (the Flip's cover display, 360x374) cannot hold a
    // readable chat under the picture and the transport; the picture and the
    // transport win and chat is left to the big screen (board 57).
    final cover = MediaQuery.sizeOf(context).height < kCoverMaxHeight;
    final floor = cover ? 0.0 : floorScaler(context).scale(160);
    final reveal = cover ? null : w.chatFloorReveal;
    final slots = <Widget>[
      RoomPortraitSlot(
        key: const ValueKey(RoomPortraitRole.header),
        role: .header,
        child: _Collapse(collapsed: w.keyboardUp, child: w.header),
      ),
      RoomPortraitSlot(
        key: const ValueKey(RoomPortraitRole.video),
        role: .video,
        child: w.videoSurface,
      ),
      if (cams != null)
        RoomPortraitSlot(
          key: const ValueKey(RoomPortraitRole.cams),
          role: .cams,
          retiring: w.facecamStrip == null,
          child: Padding(padding: EdgeInsets.fromLTRB(gutter, 10, gutter, 6), child: cams),
        ),
      RoomPortraitSlot(
        key: const ValueKey(RoomPortraitRole.strip),
        role: .strip,
        child: Padding(padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 6), child: w.reactionStrip),
      ),
      RoomPortraitSlot(key: const ValueKey(RoomPortraitRole.bar), role: .bar, child: w.controlBar),
      RoomPortraitSlot(
        key: const ValueKey(RoomPortraitRole.banners),
        role: .banners,
        child: SingleChildScrollView(child: w.bannerStack),
      ),
      RoomPortraitSlot(
        key: const ValueKey(RoomPortraitRole.chat),
        role: .chat,
        child: cover ? const SizedBox.shrink() : w.embeddedChat,
      ),
    ];
    return SafeArea(
      child: reveal == null
          ? RoomPortraitStack(chatFloor: floor + (cover ? 0 : w.chatFloorExtra), children: slots)
          : ValueListenableBuilder<double>(
              valueListenable: reveal,
              builder: (context, t, _) =>
                  RoomPortraitStack(chatFloor: floor + w.chatFloorExtra * t, children: slots),
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

/// Splits the layout along a physical fold hinge: [first] before it, [second]
/// after it, and the hinge rect itself left empty. Each pane is a [PTPane], so
/// everything inside sees the pane's size and insets - the control bar picks
/// its form from the pane's width, `SafeArea` trims only the edges the pane
/// really shares with the window, and the hinge is not in either pane's
/// display features. Fills the window (the room's body does).
class RoomFoldSplit extends StatelessWidget {
  const RoomFoldSplit({
    required this.fold,
    required this.first,
    required this.second,
    this.liftSecond = false,
    super.key,
  });

  final PTFold fold;
  final Widget first;
  final Widget second;

  /// A horizontal fold whose lower pane the soft keyboard has covered: the
  /// second pane's rect is lifted to sit above the keyboard (over the first
  /// pane's lower part) instead of being squeezed to the sliver the keyboard
  /// leaves. Only geometry changes - the two panes stay where they are in the
  /// tree, so nothing remounts and the composer keeps its focus.
  final bool liftSecond;

  @override
  Widget build(BuildContext context) {
    final window = MediaQuery.sizeOf(context);
    final panes = panesOf(window, fold);
    if (panes.length < 2) return first;
    return LayoutBuilder(
      builder: (context, box) {
        var upper = panes.first;
        var lower = panes.last;
        if (liftSecond && fold.axis == PTFoldAxis.horizontal && box.hasBoundedHeight) {
          final lifted = math.min(
            box.maxHeight,
            math.max(kDeckLiftedMin, box.maxHeight * kDeckLiftedShare),
          );
          lower = Rect.fromLTRB(0, box.maxHeight - lifted, window.width, box.maxHeight);
          // The picture gives way instead of being covered: it letterboxes
          // (never cropped) into whatever the lifted pane leaves above it.
          upper = Rect.fromLTRB(0, 0, window.width, lower.top);
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            PTPane(rect: upper, child: first),
            // Opaque, always: lifted over the picture the pane must not let it
            // show through the messages (and a wrapper that came and went with
            // the keyboard would remount the chat).
            PTPane(
              rect: lower,
              child: ColoredBox(color: PTColors.screenBg, child: second),
            ),
          ],
        );
      },
    );
  }
}

/// The least height a lifted lower pane (see [RoomFoldSplit.liftSecond]) gets.
const kDeckLiftedMin = 180.0;

/// The share of the space above the keyboard a lifted lower pane takes; the
/// picture gets the rest, whole.
const kDeckLiftedShare = 0.5;

/// Portrait windows shorter than this are a cover display: picture and
/// transport only, no chat (board 57).
const kCoverMaxHeight = 420.0;

/// A pane or region at least this wide, and no taller than it is wide, has the
/// room for [RoomDeck] (board 54): two columns beat a phone stack there.
const kDeckMinWidth = 640.0;

/// Windows (without a fold) whose height over width is under this lay the room
/// out as picture-over-[RoomDeck] rather than a tall stack: the unfolded Fold
/// (1.25) and Pixel Fold (1.2) qualify, iPad portrait (1.33 and up) keeps the
/// stack, which has the height.
const kSquarishMaxAspect = 1.3;

/// Below this height the deck's controls column drops its header.
const kDeckHeaderMinHeight = 260.0;

/// Whether a region of [size] is a deck's shape: wide enough for two columns
/// and not a tall one.
bool deckFits(Size size) => size.width >= kDeckMinWidth && size.height <= size.width * 1.1;

/// The lower half of a tabletop, or the part of a near-square window under the
/// picture (board 54): the room's controls in one column, the room itself - the
/// roster and chat - in the other. A wide, short space used as a phone stack
/// left chat about 120 px; here it gets the whole height.
///
/// [header] and [transport] are pinned; [aside] (banners, facecams) scrolls
/// beneath them so the transport can never be pushed off. The chat panel is not
/// keyed, as everywhere else (its composer owns an overlay).
class RoomDeck extends StatelessWidget {
  const RoomDeck({
    required this.header,
    required this.transport,
    required this.aside,
    required this.chat,
    this.controlsAside = false,
    super.key,
  });

  /// The controls column steps aside (kept mounted, not laid out or painted)
  /// and the chat takes the whole width: a tabletop with the keyboard up.
  final bool controlsAside;

  final Widget header;
  final Widget transport;
  final List<Widget> aside;
  final Widget chat;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final controls = (box.maxWidth * 0.48).clamp(340.0, 440.0);
        return Row(
          children: [
            Offstage(
              offstage: controlsAside,
              child: SizedBox(
                width: controls,
                child: Column(
                  children: [
                    // Short: the room's name gives way to the transport, as the
                    // portrait stack's header does under a keyboard.
                    if (box.maxHeight >= kDeckHeaderMinHeight) header,
                    transport,
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(mainAxisSize: MainAxisSize.min, children: aside),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Offstage(
              offstage: controlsAside,
              child: const VerticalDivider(width: 1, color: PTColors.aisle),
            ),
            Expanded(child: chat),
          ],
        );
      },
    );
  }
}
