import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:synctogether/diagnostics.dart';
import 'package:synctogether/ui/adaptive_action_bar.dart';
import 'package:synctogether/ui/booth_icons.g.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/popover.dart';
import 'package:synctogether/ui/pt_motion.dart';
import 'package:synctogether/ui/pt_theme.dart';
import 'package:synctogether/ui/responsive.dart';

/// The room bar's More button and the list it opens (board 46).
///
/// It is the same idea as `AdaptiveActionBar`'s More - a [showPTPopover] list
/// of the controls that folded, each row the same [AdaptiveAction] the inline
/// control came from - drawn the way the room board draws it: 44 px cells with
/// the current value under the name, two columns past five rows, anchored above
/// the button (the bar sits at the bottom of the screen) and no dim or blur.
class RoomBarMoreButton extends StatefulWidget {
  const RoomBarMoreButton({
    super.key,
    required this.rows,
    required this.live,
    required this.panelKey,
    required this.formName,
  });

  /// The folded controls, already in the list's fixed order.
  final List<AdaptiveAction> rows;

  /// A mic or camera is on while folded: a Signal dot says so on the button.
  final bool live;

  /// The bar's panel, whose top edge caps the list's height.
  final GlobalKey panelKey;

  /// For the breadcrumb only.
  final String formName;

  @override
  State<RoomBarMoreButton> createState() => _RoomBarMoreButtonState();
}

class _RoomBarMoreButtonState extends State<RoomBarMoreButton> {
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
    final box = context.findRenderObject();
    if (widget.rows.isEmpty || box is! RenderBox || !box.attached) return;
    final anchor = box.localToGlobal(Offset.zero) & box.size;
    final panel = widget.panelKey.currentContext?.findRenderObject();
    final barTop = panel is RenderBox && panel.attached
        ? panel.localToGlobal(Offset.zero).dy
        : anchor.top;
    final rows = widget.rows;
    trace(
      'room bar more opened',
      category: 'room',
      data: {'form': widget.formName, 'folded': rows.length},
    );
    late final PTPopoverHandle handle;
    handle = showPTPopover(
      context: context,
      anchor: anchor.center,
      builder: (popoverContext) {
        final media = MediaQuery.of(popoverContext);
        final origin = PTPane.originOf(popoverContext);
        return CustomSingleChildLayout(
          delegate: _AboveBarDelegate(
            anchor: anchor.shift(-origin),
            barTop: barTop - origin.dy,
            padding: media.padding,
          ),
          child: Material(
            type: .transparency,
            child: GlassPanel(
              baseColor: PTColors.surfaceBase,
              padding: const EdgeInsets.all(8),
              child: _MoreList(
                rows: rows,
                onPick: (row) {
                  // Start the exit, then act: a sheet the action opens lands
                  // over a list that is already leaving.
                  handle.close();
                  row.onTap?.call();
                },
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
      label: 'More',
      value: widget.live ? 'Mic or camera is on' : null,
      button: true,
      onTap: _open,
      excludeSemantics: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          PTIconButton(
            icon: BoothIcons.moreHoriz,
            glass: false,
            outlined: true,
            size: 44,
            iconSize: 22,
            borderRadius: BorderRadius.circular(PTRadius.control),
            tooltip: pointer ? 'More' : null,
            onPressed: _open,
          ),
          if (widget.live)
            const Positioned(
              right: 7,
              top: 7,
              child: IgnorePointer(
                child: SizedBox(
                  width: 8,
                  height: 8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: PTColors.ember, shape: BoxShape.circle),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Anchored above the bar, right-aligned to the button, never taller than the
/// room above the bar.
class _AboveBarDelegate extends SingleChildLayoutDelegate {
  const _AboveBarDelegate({required this.anchor, required this.barTop, required this.padding});

  final Rect anchor;
  final double barTop;
  final EdgeInsets padding;

  static const _gutter = 12.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => BoxConstraints(
    maxWidth: math.max(0, constraints.maxWidth - padding.horizontal - _gutter * 2),
    maxHeight: math.max(0, math.min(constraints.maxHeight, barTop) - 16 - padding.top),
  );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final minX = padding.left + _gutter;
    final maxX = math.max(minX, size.width - padding.right - _gutter - childSize.width);
    final x = (anchor.right - childSize.width).clamp(minX, maxX);
    final y = math.max(padding.top + 16, barTop - 8 - childSize.height);
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_AboveBarDelegate old) =>
      old.anchor != anchor || old.barTop != barTop || old.padding != padding;
}

class _MoreList extends StatelessWidget {
  const _MoreList({required this.rows, required this.onPick});

  final List<AdaptiveAction> rows;
  final ValueChanged<AdaptiveAction> onPick;

  static const _columnWidth = 157.0;

  @override
  Widget build(BuildContext context) {
    final columns = rows.length > 5 ? 2 : 1;
    final perColumn = (rows.length / columns).ceil();
    final screen = MediaQuery.sizeOf(context).width;
    // A narrow window shrinks the cells, whose text ellipsizes, before it
    // shrinks the list below its two columns.
    final width = math.max(120.0, math.min(_columnWidth, (screen - 16 - 48) / columns));
    Widget column(int index) => SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: .stretch,
        mainAxisSize: .min,
        children: [
          for (final row in rows.skip(index * perColumn).take(perColumn))
            _MoreRow(action: row, onTap: row.onTap == null ? null : () => onPick(row)),
        ],
      ),
    );
    return SingleChildScrollView(
      child: Row(
        crossAxisAlignment: .start,
        mainAxisSize: .min,
        children: [for (var i = 0; i < columns; i++) column(i)],
      ),
    );
  }
}

class _MoreRow extends StatefulWidget {
  const _MoreRow({required this.action, required this.onTap});

  final AdaptiveAction action;
  final VoidCallback? onTap;

  @override
  State<_MoreRow> createState() => _MoreRowState();
}

class _MoreRowState extends State<_MoreRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    final tappable = widget.onTap != null;
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
            constraints: const BoxConstraints(minHeight: kMinTouchTarget),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _hovered && tappable ? PTColors.aisle : Colors.transparent,
              borderRadius: BorderRadius.circular(PTRadius.control),
            ),
            child: Opacity(
              opacity: tappable ? 1 : 0.5,
              child: Row(
                spacing: 8,
                children: [
                  Icon(action.icon, size: 20, color: PTColors.fgDim),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: .start,
                      mainAxisSize: .min,
                      children: [
                        Text(
                          action.label,
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: PTText.body.copyWith(
                            fontSize: 13,
                            fontWeight: .w600,
                            color: PTColors.fg,
                          ),
                        ),
                        if (action.value != null)
                          Text(
                            action.value!,
                            maxLines: 1,
                            overflow: .ellipsis,
                            style: PTText.mono.copyWith(fontSize: 10, color: PTColors.fgMute),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
