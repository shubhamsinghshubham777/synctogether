import 'dart:math' as math;
import '../../ui/booth_icons.g.dart';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:synctogether/rooms/emoji/emoji_logic.dart';
import 'package:synctogether/rooms/emoji/emoji_prefs.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/pt_theme.dart';
import 'package:synctogether/ui/responsive.dart';

import 'emoji_picker.dart';

/// Seven one-tap emoji above the composer. Tapping one *inserts* it - it never
/// sends, which is what keeps a slot next to the field from firing off a
/// message mid-sentence.
///
/// [slots] is a snapshot the caller takes (see [EmojiPrefs.quickSlots]) rather
/// than a live read, so a slot never reorders under the pointer.
class EmojiQuickBar extends StatelessWidget {
  static const _minExtent = 36.0;

  const EmojiQuickBar({
    super.key,
    required this.slots,
    required this.onPick,
    required this.onCustomize,
  });

  final List<QuickSlot> slots;
  final ValueChanged<String> onPick;

  /// Right-click / long-press on a slot: opens the editor on that slot.
  final ValueChanged<int> onCustomize;

  @override
  Widget build(BuildContext context) {
    final extent = inputOf(context) == PTInput.touch ? 44.0 : 34.0;
    // A narrow panel shows fewer slots rather than squeezing seven - the
    // leading ones are the pinned-first, highest-ranked ones anyway.
    return LayoutBuilder(
      builder: (context, constraints) {
        // Cells shrink toward [_minExtent] before a slot is dropped, so all
        // seven fit beside a phone's send button.
        final fit = (constraints.maxWidth ~/ _minExtent).clamp(0, slots.length);
        final cell = fit == 0 ? extent : math.min(extent, constraints.maxWidth / fit);
        // Spread across the field's width; a narrow one shows fewer slots.
        return Row(
          mainAxisAlignment: .spaceBetween,
          children: [
            for (var i = 0; i < fit; i++)
              Stack(
                clipBehavior: .none,
                children: [
                  EmojiCell(
                    emoji: slots[i].emoji,
                    extent: cell,
                    label: emojiEntryOf(slots[i].emoji)?.name,
                    onTap: () => onPick(slots[i].emoji),
                    onHold: () => onCustomize(i),
                  ),
                  // Why this slot never changes.
                  if (slots[i].pinned)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: IgnorePointer(
                        child: Container(
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(
                            color: PTColors.textAccent,
                            shape: .circle,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}

/// The quick-bar editor: pick a slot, then an emoji for it (which pins it);
/// unpin, move, or reset the whole bar. Sheet on compact widths.
Future<void> showQuickBarEditor(BuildContext context, {int initialSlot = 0, EmojiPrefs? prefs}) {
  return showGlassDialog<void>(
    context: context,
    width: 420,
    sheetOnCompact: true,
    scrollable: false,
    builder: (context) =>
        _QuickBarEditor(prefs: prefs ?? EmojiPrefs.instance, initialSlot: initialSlot),
  );
}

class _QuickBarEditor extends StatefulWidget {
  const _QuickBarEditor({required this.prefs, required this.initialSlot});

  final EmojiPrefs prefs;
  final int initialSlot;

  @override
  State<_QuickBarEditor> createState() => _QuickBarEditorState();
}

class _QuickBarEditorState extends State<_QuickBarEditor> {
  late int _slot = widget.initialSlot.clamp(0, kQuickSlotCount - 1);

  @override
  void initState() {
    super.initState();
    widget.prefs.addListener(_changed);
  }

  @override
  void dispose() {
    widget.prefs.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // The editor is the one place the bar is allowed to change while looked
    // at - that is what it is for.
    final slots = widget.prefs.quickSlots();
    final pinned = _slot < slots.length && slots[_slot].pinned;
    final height = MediaQuery.sizeOf(context).height;
    return LayoutBuilder(
      builder: (context, box) {
        // Short screen (landscape phone, keyboard up, large text): the
        // subtitle goes and Reset/Done join the slot controls as icons, so the
        // grid keeps what height there is. Never a scroll around the grid -
        // nested, the grid's last row can end up unreachable.
        final compact = box.maxHeight < 560;
        // Shorter still - a landscape phone with the keyboard up - the header
        // goes too (Done closes) and slots and controls share one row; with
        // the width for it, that row is used whenever the editor is compact.
        final bare = box.maxHeight < 320;
        final inline = bare || (compact && box.maxWidth >= 520);
        final slotRow = LayoutBuilder(
          builder: (context, box) {
            final extent = math.min(
              48.0,
              (box.maxWidth - 6 * (kQuickSlotCount - 1)) / kQuickSlotCount,
            );
            return Row(
              mainAxisAlignment: .center,
              spacing: 6,
              children: [
                for (var i = 0; i < slots.length; i++)
                  Stack(
                    clipBehavior: .none,
                    children: [
                      EmojiCell(
                        emoji: slots[i].emoji,
                        extent: extent,
                        selected: i == _slot,
                        label: 'Slot ${i + 1}${slots[i].pinned ? ', pinned' : ''}',
                        onTap: () => setState(() => _slot = i),
                      ),
                      if (slots[i].pinned)
                        Positioned(
                          right: 2,
                          top: 2,
                          child: IgnorePointer(
                            child: Icon(
                              Symbols.push_pin_rounded,
                              size: 12,
                              fill: 1,
                              color: PTColors.textAccent,
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            );
          },
        );
        final controls = Row(
          mainAxisAlignment: .center,
          mainAxisSize: .min,
          children: [
            PTIconButton(
              icon: BoothIcons.chevronLeft,
              size: 36,
              iconSize: 18,
              tooltip: 'Move left',
              onPressed: _slot == 0 ? null : () => _move(-1, slots),
            ),
            PTIconButton(
              icon: pinned ? Symbols.keep_off_rounded : Symbols.keep_rounded,
              size: 36,
              iconSize: 18,
              tooltip: pinned ? 'Unpin' : 'Pin here',
              onPressed: () => widget.prefs.setPin(_slot, pinned ? null : slots[_slot].emoji),
            ),
            PTIconButton(
              icon: BoothIcons.chevronRight,
              size: 36,
              iconSize: 18,
              tooltip: 'Move right',
              onPressed: _slot == kQuickSlotCount - 1 ? null : () => _move(1, slots),
            ),
            if (compact) ...[
              PTIconButton(
                icon: BoothIcons.restore,
                size: 36,
                iconSize: 18,
                tooltip: 'Reset to defaults',
                onPressed: widget.prefs.resetQuickBar,
              ),
              PTIconButton(
                icon: BoothIcons.check,
                size: 36,
                iconSize: 18,
                active: true,
                tooltip: 'Done',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ],
        );
        final grid = DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: PTColors.rail),
            borderRadius: BorderRadius.circular(PTRadius.panel),
          ),
          child: EmojiPicker(
            prefs: widget.prefs,
            onPick: (emoji) => widget.prefs.setPin(_slot, emoji),
          ),
        );
        final column = Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: [
            if (!bare)
              GlassDialogHeader(
                onClose: () => Navigator.of(context).pop(),
                eyebrow: compact ? null : 'Chat',
                title: 'Quick emoji',
                subtitle: compact
                    ? null
                    : 'Pick a slot, then an emoji to pin there. Unpinned slots fill with your most used.',
              ),
            if (!bare) SizedBox(height: compact ? 8 : 14),
            if (inline)
              Row(
                children: [
                  Expanded(child: slotRow),
                  controls,
                ],
              )
            else ...[
              slotRow,
              const SizedBox(height: 8),
              controls,
            ],
            SizedBox(height: compact ? 6 : 10),
            // Loose: the grid gives way before the controls do.
            Flexible(
              child: SizedBox(height: (height * 0.42).clamp(220.0, 340.0), child: grid),
            ),
            if (!compact) ...[
              const SizedBox(height: 14),
              PTButtonBar(
                buttons: [
                  PTButton(
                    label: 'Reset to defaults',
                    variant: .secondary,
                    onPressed: widget.prefs.resetQuickBar,
                  ),
                  PTButton(label: 'Done', onPressed: () => Navigator.of(context).pop()),
                ],
              ),
            ],
          ],
        );
        return column;
      },
    );
  }

  void _move(int delta, List<QuickSlot> slots) {
    final to = _slot + delta;
    widget.prefs.swapSlots(_slot, to, slots);
    setState(() => _slot = to);
  }
}
