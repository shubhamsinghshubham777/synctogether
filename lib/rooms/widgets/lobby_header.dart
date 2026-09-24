import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/pt_motion.dart';
import 'package:synctogether/ui/pt_theme.dart';

/// Picks the first of [children] that fits the available width, and shows
/// only that one.
///
/// This is how the lobby header collapses progressively (full pills -> compact
/// chips -> an account menu) instead of wrapping onto a second line. The
/// thresholds are *measured*, not guessed: every candidate is laid out at its
/// natural width - which already reflects the text scale, the display name
/// and the quota string - and the widest one that fits wins. The last child is
/// the fallback and is squeezed into whatever width there is.
///
/// The chosen child is then laid out at exactly the available width, so a
/// `Row(mainAxisSize: .min)` candidate honours its `mainAxisAlignment`: `.end`
/// right-aligns the actions, `.spaceBetween` spreads a greeting and chips.
/// Only the chosen child paints, hit-tests and reports semantics.
class FirstFit extends MultiChildRenderObjectWidget {
  const FirstFit({super.key, required super.children});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderFirstFit();
}

class _FirstFitParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderFirstFit extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _FirstFitParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _FirstFitParentData> {
  RenderBox? _chosen;

  /// Wide enough to never bind, but finite: a Row with `Flexible` children
  /// asserts under an unbounded width.
  static const _measureWidth = 100000.0;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _FirstFitParentData) child.parentData = _FirstFitParentData();
  }

  @override
  void performLayout() {
    final maxWidth = constraints.maxWidth;
    final measure = BoxConstraints(maxWidth: _measureWidth, maxHeight: constraints.maxHeight);
    RenderBox? chosen;
    var child = firstChild;
    while (child != null) {
      child.layout(measure, parentUsesSize: true);
      chosen = child;
      if (child.size.width <= maxWidth) break;
      child = childAfter(child);
    }
    _chosen = chosen;
    if (chosen == null) {
      size = constraints.smallest;
      return;
    }
    final width = maxWidth.isFinite ? maxWidth : chosen.size.width;
    chosen.layout(
      BoxConstraints(minWidth: width, maxWidth: width, maxHeight: constraints.maxHeight),
      parentUsesSize: true,
    );
    size = constraints.constrain(Size(width, chosen.size.height));
    (chosen.parentData! as _FirstFitParentData).offset = Offset(
      0,
      (size.height - chosen.size.height) / 2,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final chosen = _chosen;
    if (chosen == null) return;
    context.paintChild(chosen, (chosen.parentData! as _FirstFitParentData).offset + offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final chosen = _chosen;
    if (chosen == null) return false;
    final offset = (chosen.parentData! as _FirstFitParentData).offset;
    return result.addWithPaintOffset(
      offset: offset,
      position: position,
      hitTest: (result, transformed) => chosen.hitTest(result, position: transformed),
    );
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (_chosen case final chosen?) visitor(chosen);
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    final last = lastChild;
    return last == null ? 0 : last.getMinIntrinsicWidth(height);
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    final first = firstChild;
    return first == null ? 0 : first.getMaxIntrinsicWidth(height);
  }
}

/// One row of the account menu.
class LobbyMenuItem {
  const LobbyMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.detail,
    this.color,
    this.danger = false,
  });

  final IconData icon;
  final String label;

  /// Secondary text on the right (a streak count, the quota left).
  final String? detail;

  /// Icon tint; defaults to a quiet white.
  final Color? color;
  final bool danger;
  final VoidCallback onTap;
}

/// The avatar's popover on narrow headers: whatever the header could not fit
/// (streak, quota, premium) above a divider, then profile and log out.
///
/// Anchored under [anchor] (global rect of the avatar) and right-aligned to
/// it. Motion follows the glass rule - slide and scale, never fade - since a
/// faded `GlassPanel` blurs an empty layer.
Future<void> showLobbyAccountMenu({
  required BuildContext context,
  required Rect anchor,
  required Widget header,
  required List<LobbyMenuItem> items,
  required List<LobbyMenuItem> footer,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'account menu',
    barrierColor: Colors.transparent,
    transitionDuration: PTMotion.functional(context, const Duration(milliseconds: 160)),
    pageBuilder: (dialogContext, _, _) {
      final screen = MediaQuery.sizeOf(dialogContext);
      final pad = MediaQuery.paddingOf(dialogContext);
      final width = math.min(288.0, screen.width - 24);
      final right = math.max(12.0, screen.width - anchor.right);
      final top = anchor.bottom + 10;
      return Stack(
        children: [
          Positioned(
            top: top,
            right: right,
            width: width,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: math.max(0, screen.height - top - pad.bottom - 12),
              ),
              child: Material(
                type: .transparency,
                child: _AccountMenuPanel(header: header, items: items, footer: footer),
              ),
            ),
          ),
        ],
      );
    },
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: PTMotion.enter);
      return SlideTransition(
        position: Tween(begin: const Offset(0, -0.03), end: Offset.zero).animate(curved),
        child: ScaleTransition(
          alignment: .topRight,
          scale: Tween(begin: 0.94, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _AccountMenuPanel extends StatelessWidget {
  const _AccountMenuPanel({required this.header, required this.items, required this.footer});

  final Widget header;
  final List<LobbyMenuItem> items;
  final List<LobbyMenuItem> footer;

  @override
  Widget build(BuildContext context) {
    Widget row(LobbyMenuItem item) => _MenuRow(
      item: item,
      onTap: () {
        Navigator.of(context).pop();
        item.onTap();
      },
    );
    return GlassPanel(
      radius: 20,
      opacity: 0.72,
      blur: 32,
      baseColor: PTColors.surfaceBase,
      borderColor: PTColors.white(0.14),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: [
            Padding(padding: const EdgeInsets.fromLTRB(8, 8, 8, 10), child: header),
            if (items.isNotEmpty) ...[_divider(), ...items.map(row)],
            _divider(),
            ...footer.map(row),
          ],
        ),
      ),
    );
  }

  Widget _divider() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
    child: Divider(height: 1, thickness: 1, color: PTColors.white(0.08)),
  );
}

class _MenuRow extends StatefulWidget {
  const _MenuRow({required this.item, required this.onTap});

  final LobbyMenuItem item;
  final VoidCallback onTap;

  @override
  State<_MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<_MenuRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final labelColor = item.danger ? PTColors.danger : PTColors.white(0.9);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: PTPressable(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: PTMotion.functional(context, PTMotion.hover),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          decoration: BoxDecoration(
            color: _hovered
                ? (item.danger
                      ? PTColors.dangerBorder.withValues(alpha: 0.1)
                      : PTColors.white(0.06))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            spacing: 12,
            children: [
              Icon(
                item.icon,
                size: 19,
                fill: 1,
                color: item.danger ? PTColors.danger : (item.color ?? PTColors.white(0.7)),
              ),
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: PTText.body.copyWith(fontSize: 14, color: labelColor),
                ),
              ),
              if (item.detail case final detail?)
                Text(
                  detail,
                  style: PTText.body.copyWith(
                    fontSize: 13,
                    fontWeight: .w600,
                    color: item.color ?? PTColors.white(0.55),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
