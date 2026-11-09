import 'package:flutter/widgets.dart';

import 'pt_motion.dart';

/// Swaps what it shows for a new keyed child by sliding the old one out and the
/// new one in along [axis], in the direction the value went ([dir]: 1 is forward
/// or up, -1 back or down), both fading as they move and clipped to the box.
/// Under reduce-motion it is a plain, shorter fade.
///
/// The child's key decides when a swap happens: give it [keyValue], and change
/// that only when what is shown has really changed.
class PTShift extends StatelessWidget {
  const PTShift({
    super.key,
    required this.keyValue,
    required this.child,
    required this.dir,
    this.axis = Axis.vertical,
    this.distance = 0.6,
    this.align = Alignment.center,
  });

  final Object keyValue;
  final Widget child;
  final int dir;
  final Axis axis;

  /// How far it travels, as a fraction of its own size along [axis].
  final double distance;
  final Alignment align;

  @override
  Widget build(BuildContext context) {
    final current = ValueKey(keyValue);
    final calm = reducedMotion(context);
    // The box eases from the old child's size to the new one's the moment the swap
    // starts (and clips what slides past its edge), so whatever sits beside it
    // glides to its new place instead of snapping when the slide ends. The leaving
    // child is taken out of layout so only the arriving one sizes the box.
    return AnimatedSize(
      duration: PTMotion.functional(context, PTMotion.state),
      curve: PTMotion.enter,
      alignment: align,
      child: AnimatedSwitcher(
        duration: PTMotion.functional(context, PTMotion.state),
        switchInCurve: PTMotion.enter,
        switchOutCurve: PTMotion.exit,
        layoutBuilder: (now, before) => Stack(
          alignment: align,
          children: [
            for (final old in before)
              Positioned.fill(
                child: OverflowBox(
                  alignment: align,
                  minWidth: 0,
                  maxWidth: double.infinity,
                  minHeight: 0,
                  maxHeight: double.infinity,
                  child: old,
                ),
              ),
            ?now,
          ],
        ),
        transitionBuilder: (child, animation) {
          // The incoming child arrives from the side the value is heading
          // towards; the outgoing one leaves the opposite way.
          final isNew = child.key == current;
          final sign = isNew ? dir : -dir;
          final from = axis == Axis.vertical
              ? Offset(0, distance * sign)
              : Offset(distance * sign, 0);
          return FadeTransition(
            opacity: animation,
            child: calm
                ? child
                : SlideTransition(
                    position: Tween(begin: from, end: Offset.zero).animate(animation),
                    child: child,
                  ),
          );
        },
        child: KeyedSubtree(key: current, child: child),
      ),
    );
  }
}

/// A single line of text in which only the characters that changed animate: a
/// minute going from 8:58 to 8:59 rolls one digit, AM to PM rolls two letters, and
/// the rest of the line stays put. Each changed character slides vertically the way
/// the value went ([dir]: 1 up or forward, -1 down or back) while it fades.
///
/// Characters are matched from the END of the line, so a value gaining or losing a
/// leading digit (9:59 to 10:00, "9 November" to "10 November") keeps the stable
/// tail where it is. The line's width follows the change (a new digit unfolds, a
/// lost one folds away) instead of snapping.
///
/// For short, single-line values: times, dates, counters. It never wraps; a line
/// that is too wide for its box scales down to fit. Not for prose or for scripts
/// that join letters. Screen readers get the whole string, not the slots.
class PTRollingText extends StatefulWidget {
  const PTRollingText(
    this.text, {
    super.key,
    required this.style,
    this.dir = 1,
    this.axis = Axis.vertical,
    this.align = Alignment.centerLeft,
    this.distance = 0.6,
  });

  final String text;
  final TextStyle style;
  final int dir;

  /// Vertical for values that count up and down, horizontal for ones that page
  /// forward and back (a year in a calendar header).
  final Axis axis;
  final Alignment align;
  final double distance;

  @override
  State<PTRollingText> createState() => _PTRollingTextState();
}

class _PTRollingTextState extends State<PTRollingText> {
  // Slots are counted from the end and never removed, so a character that goes
  // away fades out in its slot (zero width once empty) rather than vanishing.
  int _slots = 0;
  bool _first = true;

  @override
  Widget build(BuildContext context) {
    final chars = widget.text.runes.map(String.fromCharCode).toList();
    if (chars.length > _slots) _slots = chars.length;
    final fresh = !_first;
    _first = false;
    // Tabular figures keep a digit as wide as the one it replaces where the font
    // has them, so the line barely moves as numbers change.
    final style = widget.style.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    return Semantics(
      label: widget.text,
      excludeSemantics: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: widget.align,
        child: Row(
          mainAxisSize: .min,
          textDirection: TextDirection.ltr,
          children: [
            for (var i = _slots - 1; i >= 0; i--)
              _CharSlot(
                key: ValueKey(i),
                char: i < chars.length ? chars[chars.length - 1 - i] : '',
                style: style,
                dir: widget.dir,
                axis: widget.axis,
                distance: widget.distance,
                animateIn: fresh,
              ),
          ],
        ),
      ),
    );
  }
}

class _CharSlot extends StatefulWidget {
  const _CharSlot({
    super.key,
    required this.char,
    required this.style,
    required this.dir,
    required this.axis,
    required this.distance,
    required this.animateIn,
  });

  final String char;
  final TextStyle style;
  final int dir;
  final Axis axis;
  final double distance;

  /// A slot that appears after the line was first drawn (a new leading digit)
  /// starts empty and takes its character a frame later, so it animates in.
  final bool animateIn;

  @override
  State<_CharSlot> createState() => _CharSlotState();
}

class _CharSlotState extends State<_CharSlot> {
  late String _shown = widget.animateIn && widget.char.isNotEmpty ? '' : widget.char;

  @override
  void initState() {
    super.initState();
    if (_shown != widget.char) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _shown = widget.char);
      });
    }
  }

  @override
  void didUpdateWidget(_CharSlot old) {
    super.didUpdateWidget(old);
    if (widget.char != old.char) _shown = widget.char;
  }

  @override
  Widget build(BuildContext context) {
    return PTShift(
      keyValue: _shown,
      dir: widget.dir,
      axis: widget.axis,
      distance: widget.distance,
      child: _shown.isEmpty
          ? const SizedBox.shrink()
          : Text(_shown, style: widget.style, maxLines: 1, softWrap: false),
    );
  }
}
