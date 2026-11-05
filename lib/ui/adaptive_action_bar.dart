import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'booth_icons.g.dart';
import 'buttons.dart';
import 'glass.dart';
import 'popover.dart';
import 'pt_motion.dart';
import 'pt_theme.dart';
import 'responsive.dart';

/// One secondary control of an [AdaptiveActionBar].
///
/// It has two faces: [inline] is the control as the bar draws it while there is
/// room, and [label] / [icon] / [value] / [onTap] are its row in the "More"
/// list once there is not. Both faces must do the same thing.
class AdaptiveAction {
  const AdaptiveAction({
    required this.label,
    required this.icon,
    required this.inline,
    this.onTap,
    this.value,
    this.danger = false,
    this.priority = 0,
  });

  /// The row's title in the overflow list, and the inline form's semantics
  /// label (so a screen reader hears the same words in both places).
  final String label;
  final IconData icon;

  /// The inline form. It is built (and measured) even while folded, so it must
  /// be cheap to keep alive, and must answer intrinsic widths (no bare
  /// `LayoutBuilder`).
  final Widget inline;

  /// Fired by the overflow row. Null makes an *informational* row - a status
  /// chip or a tier tag - which shows [value] but is not tappable.
  final VoidCallback? onTap;

  /// Secondary text on the right of the overflow row (a status, a count).
  final String? value;

  /// Tints the overflow row Signal (ember) - kick, leave, delete.
  final bool danger;

  /// Higher survives longer. Folding starts at the lowest priority; ties fold
  /// the later one in the list first, so with every priority left at 0 the
  /// list order is the priority order (first = kept longest). Visual order is
  /// always the list order, so a low-priority item can sit anywhere.
  final int priority;
}

/// Marks a child of [AdaptiveActionBar.pinned] as the one that gives way: it
/// gets whatever width the other children leave, like an `Expanded`, and the
/// bar folds foldable items until it still has at least [minWidth] (a name that
/// must keep ~8 characters).
class AdaptiveFlex extends ParentDataWidget<_BarParentData> {
  const AdaptiveFlex({super.key, this.minWidth = 0, required super.child});

  /// The width the bar protects for this child before it folds anything else.
  final double minWidth;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as _BarParentData;
    var needsLayout = false;
    if (!data.flex || data.minWidth != minWidth) {
      data
        ..flex = true
        ..minWidth = minWidth;
      needsLayout = true;
    }
    if (needsLayout) renderObject.parent?.markNeedsLayout();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => AdaptiveActionBar;
}

/// A row of controls that folds, rather than wraps, shrinks or clips, when it
/// runs out of room ("Collapse, don't wrap" in `docs/agent/ui-and-av.md`).
///
/// [pinned] children are the screen's primary controls: always shown, at their
/// natural size, never folded. [foldable] actions stay inline as long as they
/// fit; when they do not, the lowest-priority ones move behind **one** More
/// button (a [showPTPopover] list), one at a time, until the rest fit. When
/// everything fits there is no More button at all.
///
/// Order, left to right: [pinned], the [foldable] inline forms, the More button
/// (only when something folded), [pinnedEnd]. At most one [pinned] child
/// should be an [AdaptiveFlex], which takes the leftover width.
///
/// It is a custom render object, not a `LayoutBuilder`: it measures each child
/// at its natural width (so text scale, long names and localized labels are
/// already reflected) and answers intrinsic sizes, so it works under
/// `IntrinsicHeight`. It fills the available width (`alignment` positions the
/// content when no child is flexible). It animates nothing: the fold set is a
/// pure function of the width, so a resize re-lays-out and that is all.
///
/// Touch: the More button and its rows keep a 44 px target, and tooltips are
/// attached on pointer input only.
class AdaptiveActionBar extends StatefulWidget {
  const AdaptiveActionBar({
    super.key,
    this.pinned = const [],
    required this.foldable,
    this.pinnedEnd = const [],
    this.spacing = 8,
    this.alignment = MainAxisAlignment.start,
    this.moreLabel = 'More',
    this.moreSize = 30,
    this.moreIconSize = 16,
    this.moreGlass = false,
  });

  final List<Widget> pinned;
  final List<AdaptiveAction> foldable;
  final List<Widget> pinnedEnd;
  final double spacing;

  /// Where the content sits when no child is [AdaptiveFlex]. Only `start`,
  /// `end` and `center` are honoured.
  final MainAxisAlignment alignment;

  /// Semantics label (and pointer tooltip) of the More button.
  final String moreLabel;
  final double moreSize;
  final double moreIconSize;
  final bool moreGlass;

  @override
  State<AdaptiveActionBar> createState() => _AdaptiveActionBarState();
}

/// How the render object tells the More button what folded, without a
/// `setState` from inside layout: a plain field the button reads on tap.
class _FoldProbe {
  List<int> folded = const [];
}

class _AdaptiveActionBarState extends State<AdaptiveActionBar> {
  final _probe = _FoldProbe();

  List<int> get _foldOrder {
    final order = List<int>.generate(widget.foldable.length, (i) => i);
    order.sort((a, b) {
      final byPriority = widget.foldable[a].priority.compareTo(widget.foldable[b].priority);
      return byPriority != 0 ? byPriority : b.compareTo(a);
    });
    return order;
  }

  @override
  Widget build(BuildContext context) {
    final actions = widget.foldable;
    return _AdaptiveBar(
      pinnedCount: widget.pinned.length,
      foldCount: actions.length,
      foldOrder: _foldOrder,
      spacing: widget.spacing,
      alignment: widget.alignment,
      probe: _probe,
      children: [
        ...widget.pinned,
        for (final action in actions)
          Semantics(
            label: action.label,
            value: action.value,
            button: action.onTap != null,
            onTap: action.onTap,
            excludeSemantics: true,
            child: action.inline,
          ),
        _MoreButton(
          label: widget.moreLabel,
          size: widget.moreSize,
          iconSize: widget.moreIconSize,
          glass: widget.moreGlass,
          actionsOf: () => [for (final i in _probe.folded) actions[i]],
        ),
        ...widget.pinnedEnd,
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Render object

class _BarParentData extends ContainerBoxParentData<RenderBox> {
  bool flex = false;
  double minWidth = 0;
  bool visible = true;
}

class _AdaptiveBar extends MultiChildRenderObjectWidget {
  const _AdaptiveBar({
    required super.children,
    required this.pinnedCount,
    required this.foldCount,
    required this.foldOrder,
    required this.spacing,
    required this.alignment,
    required this.probe,
  });

  final int pinnedCount;
  final int foldCount;
  final List<int> foldOrder;
  final double spacing;
  final MainAxisAlignment alignment;
  final _FoldProbe probe;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderAdaptiveBar(pinnedCount, foldCount, foldOrder, spacing, alignment, probe);

  @override
  void updateRenderObject(BuildContext context, _RenderAdaptiveBar renderObject) {
    renderObject
      ..pinnedCount = pinnedCount
      ..foldCount = foldCount
      ..foldOrder = foldOrder
      ..spacing = spacing
      ..alignment = alignment
      ..probe = probe;
  }
}

/// The decision, as a pure function so it can be tested without a render tree.
///
/// [fixed] is the width every pinned child needs (flexible ones at their
/// minimum) and [fixedCount] how many of them there are. Returns the indices
/// into [foldWidths] to fold, lowest priority first as given by [order].
@visibleForTesting
Set<int> planFolds({
  required double available,
  required double fixed,
  required int fixedCount,
  required List<double> foldWidths,
  required List<int> order,
  required double moreWidth,
  required double spacing,
}) {
  double total(Set<int> folded, {required bool more}) {
    var width = fixed;
    var count = fixedCount;
    for (var i = 0; i < foldWidths.length; i++) {
      if (folded.contains(i)) continue;
      width += foldWidths[i];
      count++;
    }
    if (more) {
      width += moreWidth;
      count++;
    }
    return width + spacing * math.max(0, count - 1);
  }

  final folded = <int>{};
  if (!available.isFinite || total(folded, more: false) <= available) return folded;
  for (final index in order) {
    folded.add(index);
    if (total(folded, more: true) <= available) break;
  }
  return folded;
}

class _RenderAdaptiveBar extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _BarParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _BarParentData> {
  _RenderAdaptiveBar(
    this._pinnedCount,
    this._foldCount,
    this._foldOrder,
    this._spacing,
    this._alignment,
    this._probe,
  );

  /// Wide enough to never bind, but finite (see `FirstFit`).
  static const _measureWidth = 100000.0;

  int _pinnedCount;
  int _foldCount;
  List<int> _foldOrder;
  double _spacing;
  MainAxisAlignment _alignment;
  _FoldProbe _probe;

  set pinnedCount(int v) {
    if (_pinnedCount == v) return;
    _pinnedCount = v;
    markNeedsLayout();
  }

  set foldCount(int v) {
    if (_foldCount == v) return;
    _foldCount = v;
    markNeedsLayout();
  }

  set foldOrder(List<int> v) {
    _foldOrder = v;
    markNeedsLayout();
  }

  set spacing(double v) {
    if (_spacing == v) return;
    _spacing = v;
    markNeedsLayout();
  }

  set alignment(MainAxisAlignment v) {
    if (_alignment == v) return;
    _alignment = v;
    markNeedsLayout();
  }

  set probe(_FoldProbe v) => _probe = v;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _BarParentData) child.parentData = _BarParentData();
  }

  List<RenderBox> get _kids {
    final out = <RenderBox>[];
    for (var c = firstChild; c != null; c = childAfter(c)) {
      out.add(c);
    }
    return out;
  }

  _BarParentData _data(RenderBox c) => c.parentData! as _BarParentData;

  int get _moreIndex => _pinnedCount + _foldCount;

  /// Which children show, given each one's natural width. [naturals] is in child
  /// order. Returns the visible flags and the folded indices (into the foldable
  /// list).
  ({List<bool> visible, Set<int> folded}) _plan(double available, List<double> naturals) {
    final kids = _kids;
    var fixed = 0.0;
    var fixedCount = 0;
    for (var i = 0; i < kids.length; i++) {
      if (i >= _pinnedCount && i <= _moreIndex) continue;
      final data = _data(kids[i]);
      fixed += data.flex ? data.minWidth : naturals[i];
      fixedCount++;
    }
    final folded = planFolds(
      available: available,
      fixed: fixed,
      fixedCount: fixedCount,
      foldWidths: [for (var i = 0; i < _foldCount; i++) naturals[_pinnedCount + i]],
      order: _foldOrder,
      moreWidth: naturals[_moreIndex],
      spacing: _spacing,
    );
    final visible = [
      for (var i = 0; i < kids.length; i++)
        if (i < _pinnedCount || i > _moreIndex)
          true
        else if (i == _moreIndex)
          folded.isNotEmpty
        else
          !folded.contains(i - _pinnedCount),
    ];
    return (visible: visible, folded: folded);
  }

  double _gaps(List<bool> visible) {
    final count = visible.where((v) => v).length;
    return _spacing * math.max(0, count - 1);
  }

  @override
  void performLayout() {
    final kids = _kids;
    if (kids.isEmpty) {
      size = constraints.smallest;
      return;
    }
    final maxWidth = constraints.maxWidth;
    final measure = BoxConstraints(maxWidth: _measureWidth, maxHeight: constraints.maxHeight);
    final naturals = <double>[];
    for (final kid in kids) {
      kid.layout(measure, parentUsesSize: true);
      naturals.add(kid.size.width);
    }
    final plan = _plan(maxWidth, naturals);
    _probe.folded = (plan.folded.toList()..sort());

    var fixedVisible = 0.0;
    var flexCount = 0;
    for (var i = 0; i < kids.length; i++) {
      final data = _data(kids[i])..visible = plan.visible[i];
      if (!data.visible) continue;
      if (data.flex) {
        flexCount++;
      } else {
        fixedVisible += naturals[i];
      }
    }
    final gaps = _gaps(plan.visible);
    final flexWidth = flexCount == 0 || !maxWidth.isFinite
        ? null
        : math.max(0.0, (maxWidth - fixedVisible - gaps) / flexCount);

    var height = 0.0;
    var content = gaps;
    for (var i = 0; i < kids.length; i++) {
      final data = _data(kids[i]);
      if (!data.visible) continue;
      if (data.flex && flexWidth != null) {
        kids[i].layout(
          BoxConstraints(
            minWidth: flexWidth,
            maxWidth: flexWidth,
            maxHeight: constraints.maxHeight,
          ),
          parentUsesSize: true,
        );
      }
      content += kids[i].size.width;
      height = math.max(height, kids[i].size.height);
    }
    final width = maxWidth.isFinite ? maxWidth : content;
    size = constraints.constrain(Size(width, height));

    final free = math.max(0.0, size.width - content);
    var x = switch (_alignment) {
      MainAxisAlignment.end => free,
      MainAxisAlignment.center => free / 2,
      _ => 0.0,
    };
    for (final kid in kids) {
      final data = _data(kid);
      if (!data.visible) continue;
      data.offset = Offset(x, (size.height - kid.size.height) / 2);
      x += kid.size.width + _spacing;
    }
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final width = constraints.maxWidth.isFinite ? constraints.maxWidth : _intrinsicWidth(true);
    return constraints.constrain(Size(width, _intrinsicHeight(width)));
  }

  double _intrinsicHeight(double width) {
    final kids = _kids;
    if (kids.isEmpty) return 0;
    final naturals = [for (final k in kids) k.getMaxIntrinsicWidth(double.infinity)];
    final plan = _plan(width, naturals);
    var fixedVisible = 0.0;
    var flexCount = 0;
    for (var i = 0; i < kids.length; i++) {
      if (!plan.visible[i]) continue;
      if (_data(kids[i]).flex) {
        flexCount++;
      } else {
        fixedVisible += naturals[i];
      }
    }
    final flexWidth = flexCount == 0 || !width.isFinite
        ? null
        : math.max(0.0, (width - fixedVisible - _gaps(plan.visible)) / flexCount);
    var height = 0.0;
    for (var i = 0; i < kids.length; i++) {
      if (!plan.visible[i]) continue;
      final w = _data(kids[i]).flex ? (flexWidth ?? naturals[i]) : naturals[i];
      height = math.max(height, kids[i].getMaxIntrinsicHeight(w));
    }
    return height;
  }

  /// [everythingInline] true: the widest the bar ever wants to be.
  double _intrinsicWidth(bool everythingInline) {
    final kids = _kids;
    var width = 0.0;
    var count = 0;
    for (var i = 0; i < kids.length; i++) {
      final more = i == _moreIndex;
      final foldable = i >= _pinnedCount && i < _moreIndex;
      if (everythingInline) {
        if (more) continue;
        width += kids[i].getMaxIntrinsicWidth(double.infinity);
      } else {
        if (foldable) continue;
        final data = _data(kids[i]);
        width += data.flex ? data.minWidth : kids[i].getMaxIntrinsicWidth(double.infinity);
      }
      count++;
    }
    return width + _spacing * math.max(0, count - 1);
  }

  @override
  double computeMinIntrinsicWidth(double height) => _intrinsicWidth(false);

  @override
  double computeMaxIntrinsicWidth(double height) => _intrinsicWidth(true);

  @override
  double computeMinIntrinsicHeight(double width) => _intrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) => _intrinsicHeight(width);

  @override
  void paint(PaintingContext context, Offset offset) {
    for (var c = firstChild; c != null; c = childAfter(c)) {
      final data = _data(c);
      if (data.visible) context.paintChild(c, data.offset + offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (var c = lastChild; c != null; c = childBefore(c)) {
      final data = _data(c);
      if (!data.visible) continue;
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
      if (_data(c).visible) visitor(c);
    }
  }
}

// ---------------------------------------------------------------------------
// The More button and its list

class _MoreButton extends StatefulWidget {
  const _MoreButton({
    required this.label,
    required this.size,
    required this.iconSize,
    required this.glass,
    required this.actionsOf,
  });

  final String label;
  final double size;
  final double iconSize;
  final bool glass;
  final List<AdaptiveAction> Function() actionsOf;

  @override
  State<_MoreButton> createState() => _MoreButtonState();
}

class _MoreButtonState extends State<_MoreButton> {
  PTPopoverHandle? _handle;

  @override
  void dispose() {
    _handle?.close(animate: false);
    super.dispose();
  }

  void _open() {
    if (_handle?.isOpen ?? false) {
      _handle!.close();
      return;
    }
    final actions = widget.actionsOf();
    final box = context.findRenderObject();
    if (actions.isEmpty || box is! RenderBox || !box.attached) return;
    final anchor = box.localToGlobal(Offset.zero) & box.size;
    late final PTPopoverHandle handle;
    handle = showPTPopover(
      context: context,
      builder: (popoverContext) {
        final media = MediaQuery.of(popoverContext);
        return CustomSingleChildLayout(
          delegate: _MenuDelegate(
            anchor: anchor,
            padding: media.padding.copyWith(
              bottom: math.max(media.padding.bottom, media.viewInsets.bottom),
            ),
          ),
          child: Material(
            type: .transparency,
            child: GlassPanel(
              baseColor: PTColors.surfaceBase,
              shadow: true,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(6),
                child: Column(
                  mainAxisSize: .min,
                  crossAxisAlignment: .stretch,
                  children: [
                    for (final action in actions)
                      _FoldedRow(
                        action: action,
                        onTap: action.onTap == null
                            ? null
                            : () {
                                // Start the exit, then act: a dialog the action
                                // opens lands over a menu that is already leaving.
                                handle.close();
                                action.onTap!();
                              },
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    _handle = handle;
  }

  @override
  Widget build(BuildContext context) {
    final pointer = inputOf(context) == .pointer;
    return Semantics(
      label: widget.label,
      button: true,
      onTap: _open,
      excludeSemantics: true,
      child: PTIconButton(
        icon: BoothIcons.moreHoriz,
        glass: widget.glass,
        size: widget.size,
        iconSize: widget.iconSize,
        tooltip: pointer ? widget.label : null,
        onPressed: _open,
      ),
    );
  }
}

class _MenuDelegate extends SingleChildLayoutDelegate {
  const _MenuDelegate({required this.anchor, required this.padding});

  final Rect anchor;
  final EdgeInsets padding;

  static const _gutter = 12.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => BoxConstraints(
    maxWidth: math.max(0, math.min(280, constraints.maxWidth - padding.horizontal - _gutter * 2)),
    maxHeight: math.max(0, constraints.maxHeight - padding.vertical - _gutter * 2),
  );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final minX = padding.left + _gutter;
    final maxX = math.max(minX, size.width - padding.right - _gutter - childSize.width);
    final x = (anchor.right - childSize.width).clamp(minX, maxX);
    final minY = padding.top + _gutter;
    final maxY = math.max(minY, size.height - padding.bottom - _gutter - childSize.height);
    final below = anchor.bottom + 6;
    final y = below <= maxY ? below : anchor.top - 6 - childSize.height;
    return Offset(x, y.clamp(minY, maxY));
  }

  @override
  bool shouldRelayout(_MenuDelegate old) => old.anchor != anchor || old.padding != padding;
}

class _FoldedRow extends StatefulWidget {
  const _FoldedRow({required this.action, required this.onTap});

  final AdaptiveAction action;
  final VoidCallback? onTap;

  @override
  State<_FoldedRow> createState() => _FoldedRowState();
}

class _FoldedRowState extends State<_FoldedRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    final tappable = widget.onTap != null;
    final touch = inputOf(context) == .touch;
    final ink = action.danger ? PTColors.ember : null;
    return Semantics(
      label: action.label,
      value: action.value,
      button: tappable,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: tappable ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: PTPressable(
          onTap: widget.onTap,
          enabled: tappable,
          child: AnimatedContainer(
            duration: PTMotion.functional(context, PTMotion.hover),
            constraints: BoxConstraints(minHeight: touch ? kMinTouchTarget : 38),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: _hovered && tappable
                  ? (action.danger ? PTColors.dangerBorder.withValues(alpha: 0.1) : PTColors.aisle)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(PTRadius.control),
            ),
            child: Row(
              spacing: 12,
              children: [
                Icon(action.icon, size: 19, color: ink ?? PTColors.white(0.7)),
                Expanded(
                  child: Text(action.label, style: PTText.body.copyWith(fontSize: 14, color: ink)),
                ),
                if (action.value != null)
                  Flexible(
                    child: Text(
                      action.value!,
                      textAlign: .end,
                      style: PTText.finePrint.copyWith(color: PTColors.white(0.55)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
