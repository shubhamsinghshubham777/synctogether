import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'booth_icons.g.dart';
import 'buttons.dart';
import 'glass.dart';
import 'pt_date_time_logic.dart';
import 'pt_motion.dart';
import 'reveal.dart';
import 'rolling_text.dart';
import 'pt_theme.dart';

/// Which part of the picker takes the focus first (the plan form's Day and Time
/// fields both open this picker, each on its own part).
enum PickerPart { date, time }

const _kRow = 40.0;
const _kWheelHeight = _kRow * 5;
const _kCell = 44.0;
const _kGridWidth = _kCell * 7;
const _kTimeWidth = 196.0;
const _kGapBetween = 28.0;
const _kDisabledOpacity = 0.45;
const _kPastText = "Pick a time that hasn't happened yet.";

/// Date and time, picked in a PT-styled sheet or dialog. One component for every
/// platform: wheels when the window is under 480 wide or tall (a thumb), a month
/// grid and a time field otherwise (a pointer). The OS and the input device never
/// change which.
///
/// Returns the chosen local moment (a plain date when [dateOnly]), or null when
/// cancelled.
Future<DateTime?> showPTDateTimePicker(
  BuildContext context, {
  required DateTime initial,
  required DateTime min,
  required DateTime max,
  bool dateOnly = false,
  PickerPart part = PickerPart.date,
  String? movingFrom,
  String? Function(DateTime moment)? partnerLine,
  String boundsCaption = 'A year ahead is as far as we can plan.',
}) {
  return showGlassDialog<DateTime>(
    context: context,
    width: 640,
    sheetOnCompact: true,
    builder: (_) => PTDateTimePicker(
      initial: initial,
      min: min,
      max: max,
      dateOnly: dateOnly,
      part: part,
      movingFrom: movingFrom,
      partnerLine: partnerLine,
      boundsCaption: boundsCaption,
    ),
  );
}

class PTDateTimePicker extends StatefulWidget {
  const PTDateTimePicker({
    super.key,
    required this.initial,
    required this.min,
    required this.max,
    this.dateOnly = false,
    this.part = PickerPart.date,
    this.movingFrom,
    this.partnerLine,
    this.boundsCaption = 'A year ahead is as far as we can plan.',
    this.kicker = 'WHEN',
    this.is24Hour,
    this.firstWeekday,
    this.now,
  });

  final DateTime initial;

  /// The earliest and latest moment that can be set.
  final DateTime min;
  final DateTime max;
  final bool dateOnly;
  final PickerPart part;

  /// "Moving from Sat 14 Nov, 8:07 PM": shown when an existing night is being moved.
  final String? movingFrom;

  /// One line about the other person's clock for the chosen moment, or null/empty
  /// to hide it (same time zone, or no partner).
  final String? Function(DateTime moment)? partnerLine;
  final String boundsCaption;
  final String kicker;

  /// Overrides for tests. Null follows the device and the locale.
  final bool? is24Hour;
  final int? firstWeekday;
  final DateTime? now;

  @override
  State<PTDateTimePicker> createState() => _PTDateTimePickerState();
}

class _PTDateTimePickerState extends State<PTDateTimePicker> {
  late DateTime _day;
  late int _hour;
  late int _minute;
  late DateTime _view;
  final _gridFocus = FocusNode(debugLabel: 'picker grid');
  final _hourFocus = FocusNode(debugLabel: 'picker hour');
  final _minuteFocus = FocusNode(debugLabel: 'picker minute');
  String _typed = '';
  Timer? _typedTimer;

  // The last caption and partner line, kept so they can fade out with their words.
  _Note? _lastCaption;
  String? _lastPartner;

  // Which way each value last moved (1 forward / up, -1 back / down), so a changed
  // value slides the way it went.
  int _dayDir = 1;
  int _monthDir = 1;
  int _hourDir = 1;
  int _minDir = 1;
  int _clockDir = 1;

  DateTime get _min => minuteFloor(widget.min);
  DateTime get _max => minuteFloor(widget.max);
  DateTime get _minDay => dateOnly(_min);
  DateTime get _maxDay => dateOnly(_max);
  DateTime get _today => dateOnly(widget.now ?? DateTime.now());

  @override
  void initState() {
    super.initState();
    final v = clampMoment(widget.initial, min: _min, max: _max);
    _day = dateOnly(v);
    _hour = widget.dateOnly ? 0 : v.hour;
    _minute = widget.dateOnly ? 0 : v.minute;
    _view = DateTime(_day.year, _day.month);
    _gridFocus.addListener(_refresh);
    _hourFocus.addListener(_refresh);
    _minuteFocus.addListener(_refresh);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.part == PickerPart.time && !widget.dateOnly) {
        _hourFocus.requestFocus();
      } else {
        _gridFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _typedTimer?.cancel();
    _gridFocus.dispose();
    _hourFocus.dispose();
    _minuteFocus.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  bool _is24(BuildContext context) =>
      widget.is24Hour ?? MediaQuery.alwaysUse24HourFormatOf(context);

  int _firstWeekday(BuildContext context) {
    final override = widget.firstWeekday;
    if (override != null) return override;
    final index = MaterialLocalizations.of(context).firstDayOfWeekIndex; // 0 = Sunday
    return index == 0 ? DateTime.sunday : index;
  }

  ResolvedMoment get _resolved => resolveMoment(_day.year, _day.month, _day.day, _hour, _minute);

  DateTime get _moment => widget.dateOnly ? _day : _resolved.moment;

  MomentCheck get _check {
    if (widget.dateOnly) {
      if (_day.isBefore(_minDay)) return MomentCheck.past;
      if (_day.isAfter(_maxDay)) return MomentCheck.tooFar;
      return MomentCheck.ok;
    }
    return checkMoment(_moment, min: _min, max: _max);
  }

  void _setDay(DateTime d) {
    final lo = _minDay;
    final hi = _maxDay;
    final clamped = d.isBefore(lo) ? lo : (d.isAfter(hi) ? hi : dateOnly(d));
    final month = DateTime(clamped.year, clamped.month);
    setState(() {
      if (clamped != _day) _dayDir = clamped.isAfter(_day) ? 1 : -1;
      if (month != _view) _monthDir = month.isAfter(_view) ? 1 : -1;
      _day = clamped;
      _view = month;
    });
  }

  /// +1 if [to] is the shorter way forward from [from] on a dial of [size] steps,
  /// -1 if backward, [keep] if nothing moved (59 to 0 is forward).
  static int _wrapDir(int from, int to, int size, int keep) {
    final d = ((to - from) % size + size) % size;
    if (d == 0) return keep;
    return d * 2 <= size ? 1 : -1;
  }

  void _setTime(int hour, int minute) => setState(() {
    _hourDir = _wrapDir(_hour, hour, 24, _hourDir);
    _minDir = _wrapDir(_minute, minute, 60, _minDir);
    _clockDir = _wrapDir(_hour * 60 + _minute, hour * 60 + minute, 1440, _clockDir);
    _hour = hour;
    _minute = minute;
  });

  void _confirm() {
    if (_check != MomentCheck.ok) return;
    Navigator.of(context).pop(_moment);
  }

  bool _pastTime(int h, int m) =>
      !widget.dateOnly &&
      _day == _minDay &&
      DateTime(_day.year, _day.month, _day.day, h, m).isBefore(_min);

  // ---- keyboard ----------------------------------------------------------

  KeyEventResult _gridKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final DayKey? move = switch (key) {
      LogicalKeyboardKey.arrowLeft => .left,
      LogicalKeyboardKey.arrowRight => .right,
      LogicalKeyboardKey.arrowUp => .up,
      LogicalKeyboardKey.arrowDown => .down,
      LogicalKeyboardKey.pageUp => .pageUp,
      LogicalKeyboardKey.pageDown => .pageDown,
      LogicalKeyboardKey.home => .home,
      LogicalKeyboardKey.end => .end,
      _ => null,
    };
    if (move != null) {
      _setDay(
        moveSelectedDay(_day, move, min: _min, max: _max, firstWeekday: _firstWeekday(context)),
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      _confirm();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _timeKey(FocusNode node, KeyEvent event, {required bool isHour}) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final is24 = _is24(context);
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
      final d = key == LogicalKeyboardKey.arrowUp ? 1 : -1;
      if (isHour) {
        _setTime(wrapStep(_hour, d, 24), _minute);
      } else {
        _setTime(_hour, wrapStep(_minute, d, 60));
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) {
      (isHour ? _minuteFocus : _hourFocus).requestFocus();
      _typed = '';
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      _confirm();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace) {
      if (_typed.isNotEmpty) _typed = _typed.substring(0, _typed.length - 1);
      _applyTyped(is24);
      return KeyEventResult.handled;
    }
    final ch = event.character;
    if (ch != null && RegExp(r'^[0-9apmAPM:. ]$').hasMatch(ch)) {
      _typed += ch;
      _applyTyped(is24);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _applyTyped(bool is24) {
    _typedTimer?.cancel();
    _typedTimer = Timer(const Duration(milliseconds: 1500), () => _typed = '');
    final t = parseTypedTime(_typed, is24Hour: is24);
    if (t == null) return;
    final hour = t.needsMeridiem ? t.hour + (_hour >= 12 ? 12 : 0) : t.hour;
    _setTime(hour, t.minute);
  }

  // ---- build -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final wheels = size.width < 480 || size.height < 480;
    final sheet = size.width < kGlassSheetBreakpoint;
    final compactRows = size.height < 680;
    final is24 = _is24(context);
    final check = _check;
    final resolved = widget.dateOnly ? null : _resolved;
    final partner = widget.partnerLine?.call(_moment);

    final String? captionText;
    var captionKind = _CaptionKind.info;
    if (check == MomentCheck.past) {
      captionText = _kPastText;
      captionKind = .error;
    } else if (check == MomentCheck.tooFar) {
      captionText = widget.boundsCaption;
    } else if (resolved != null && resolved.movedForGap) {
      captionText =
          "${clockText(_hour, _minute, is24Hour: is24)} doesn't exist that night, the clocks jump "
          "forward. We'll use ${clockText(resolved.moment.hour, resolved.moment.minute, is24Hour: is24)}.";
      captionKind = .warning;
    } else if (_day == _maxDay) {
      captionText = widget.boundsCaption;
    } else {
      captionText = null;
    }

    final body = wheels
        ? _wheels(is24, check != MomentCheck.ok)
        : _grid(context, is24, compactRows, check != MomentCheck.ok);

    final gap = sheet ? 14.0 : 16.0;
    final note = captionText == null ? null : (kind: captionKind, text: captionText);
    if (note != null) _lastCaption = note;
    final partnerText = partner != null && partner.isNotEmpty ? partner : null;
    if (partnerText != null) _lastPartner = partnerText;

    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: [
        _header(sheet, is24),
        SizedBox(height: gap),
        body,
        // These come and go: they fold open and shut rather than shoving the
        // buttons by their whole height in one frame.
        PTReveal(
          visible: partnerText != null,
          child: Padding(
            padding: EdgeInsets.only(top: gap),
            child: _PartnerLine(text: _lastPartner ?? ''),
          ),
        ),
        PTReveal(
          visible: note != null,
          child: Padding(
            padding: EdgeInsets.only(top: gap),
            child: _Caption(
              kind: (_lastCaption ?? (kind: _CaptionKind.info, text: '')).kind,
              text: (_lastCaption ?? (kind: _CaptionKind.info, text: '')).text,
            ),
          ),
        ),
        SizedBox(height: gap),
        PTButtonBar(
          alignEnd: !sheet,
          buttons: [
            PTButton(
              label: 'Cancel',
              variant: .secondary,
              height: sheet ? 50 : 46,
              expand: sheet,
              onPressed: () => Navigator.of(context).pop(),
            ),
            PTButton(
              label: 'Set',
              height: sheet ? 50 : 46,
              expand: sheet,
              onPressed: check == MomentCheck.ok ? _confirm : null,
            ),
          ],
        ),
      ],
    );
  }

  Widget _header(bool sheet, bool is24) {
    final isToday = _day == _today;
    final moving = widget.movingFrom != null;
    final headStyle = sheet ? PTText.cardHeading : PTText.screenTitle;
    return Row(
      crossAxisAlignment: .start,
      spacing: 12,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: .start,
            spacing: 4,
            children: [
              // "WHEN" stays; " · TODAY" unfolds beside it only while today is picked.
              // The moving kicker is long and static, so it wraps like any text.
              if (moving)
                Text('${widget.kicker} · MOVING THE NIGHT', style: PTText.label)
              else
                Row(
                  mainAxisSize: .min,
                  children: [
                    Text(widget.kicker, style: PTText.label),
                    PTReveal(
                      visible: isToday,
                      axis: Axis.horizontal,
                      alignment: Alignment.centerLeft,
                      child: Text(' · TODAY', style: PTText.label, maxLines: 1, softWrap: false),
                    ),
                  ],
                ),
              PTRollingText(pickerHeadline(_day, _today), style: headStyle, dir: _dayDir),
              if (!widget.dateOnly)
                PTRollingText(
                  clockText(_resolved.moment.hour, _resolved.moment.minute, is24Hour: is24),
                  style: PTText.body.copyWith(color: PTColors.fgDim),
                  dir: _clockDir,
                ),
              if (widget.movingFrom != null)
                Text(widget.movingFrom!, style: PTText.caption.copyWith(color: PTColors.fgMute)),
            ],
          ),
        ),
        if (!_today.isBefore(_minDay) && !_today.isAfter(_maxDay))
          _TodayChip(selected: isToday, onTap: () => _setDay(_today)),
      ],
    );
  }

  // ---- wheels ------------------------------------------------------------

  Widget _wheels(bool is24, bool invalid) {
    final pm = _hour >= 12;
    final columns = <Widget>[];
    if (widget.dateOnly) {
      final minY = _minDay.year;
      final maxY = _maxDay.year;
      columns.addAll([
        Expanded(
          flex: 2,
          child: _Wheel(
            label: 'Month',
            count: 12,
            index: _day.month - 1,
            text: (i) => monthLong(i + 1),
            onChanged: (i) => _setDay(_dateOf(_day.year, i + 1, _day.day)),
          ),
        ),
        Expanded(
          child: _Wheel(
            label: 'Day',
            count: daysInMonth(_day.year, _day.month),
            index: _day.day - 1,
            text: (i) => '${i + 1}',
            greyed: (i) {
              final d = DateTime(_day.year, _day.month, i + 1);
              return d.isBefore(_minDay) || d.isAfter(_maxDay);
            },
            onChanged: (i) => _setDay(DateTime(_day.year, _day.month, i + 1)),
          ),
        ),
        Expanded(
          flex: 2,
          child: _Wheel(
            label: 'Year',
            count: maxY - minY + 1,
            index: _day.year - minY,
            text: (i) => '${minY + i}',
            onChanged: (i) => _setDay(_dateOf(minY + i, _day.month, _day.day)),
          ),
        ),
      ]);
    } else {
      columns.addAll([
        Expanded(
          flex: 21,
          child: _Wheel(
            label: 'Day',
            count: daysBetween(_minDay, _maxDay) + 1,
            index: daysBetween(_minDay, _day),
            text: (i) => dayRowLabel(DateTime(_minDay.year, _minDay.month, _minDay.day + i)),
            onChanged: (i) => _setDay(DateTime(_minDay.year, _minDay.month, _minDay.day + i)),
          ),
        ),
        Expanded(
          flex: 10,
          child: _Wheel(
            label: 'Hour',
            count: is24 ? 24 : 12,
            index: is24 ? _hour : (_hour + 11) % 12,
            text: (i) => is24 ? i.toString().padLeft(2, '0') : '${i + 1}',
            greyed: (i) => _pastTime(is24 ? i : (i + 1) % 12 + (pm ? 12 : 0), 59),
            invalid: invalid,
            onChanged: (i) => _setTime(is24 ? i : (i + 1) % 12 + (pm ? 12 : 0), _minute),
          ),
        ),
        Expanded(
          flex: 10,
          child: _Wheel(
            label: 'Minute',
            count: 60,
            index: _minute,
            text: (i) => i.toString().padLeft(2, '0'),
            greyed: (i) => _pastTime(_hour, i),
            invalid: invalid,
            onChanged: (i) => _setTime(_hour, i),
          ),
        ),
        if (!is24)
          Expanded(
            flex: 10,
            child: _Wheel(
              label: 'AM or PM',
              count: 2,
              index: pm ? 1 : 0,
              text: (i) => i == 0 ? 'AM' : 'PM',
              invalid: invalid,
              onChanged: (i) => _setTime(_hour % 12 + (i == 1 ? 12 : 0), _minute),
            ),
          ),
      ]);
    }
    return SizedBox(
      height: _kWheelHeight,
      child: Stack(
        children: [
          Row(spacing: 6, children: columns),
          // The selected row: two Rail hairlines, nothing else.
          const IgnorePointer(
            child: Column(
              children: [
                SizedBox(height: _kRow * 2),
                _Hairline(),
                SizedBox(height: _kRow - 2),
                _Hairline(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// A date in [year]/[month], with the day kept where the month has it.
  DateTime _dateOf(int year, int month, int day) {
    final last = daysInMonth(year, month);
    return DateTime(year, month, day > last ? last : day);
  }

  // ---- grid and time field -----------------------------------------------

  Widget _grid(BuildContext context, bool is24, bool compactRows, bool invalid) {
    final first = _firstWeekday(context);
    final grid = _MonthGrid(
      view: _view,
      selected: _day,
      today: _today,
      min: _minDay,
      max: _maxDay,
      firstWeekday: first,
      compact: compactRows,
      focused: _keyboardFocused(_gridFocus),
      focusNode: _gridFocus,
      onKey: _gridKey,
      onPick: (d) {
        _gridFocus.requestFocus();
        _setDay(d);
      },
      dir: _monthDir,
      onMonth: (delta) => setState(() {
        _monthDir = delta.sign;
        _view = DateTime(_view.year, _view.month + delta);
      }),
    );
    if (widget.dateOnly) return Center(child: grid);
    final time = _TimeColumn(
      hour: _hour,
      minute: _minute,
      is24: is24,
      invalid: invalid,
      hourDir: _hourDir,
      minuteDir: _minDir,
      hourFocus: _hourFocus,
      minuteFocus: _minuteFocus,
      onHourKey: (n, e) => _timeKey(n, e, isHour: true),
      onMinuteKey: (n, e) => _timeKey(n, e, isHour: false),
      onHour: (d) => _setTime(wrapStep(_hour, d, 24), _minute),
      onMinute: (d) => _setTime(_hour, wrapStep(_minute, d, 60)),
      onMeridiem: (pm) => _setTime(_hour % 12 + (pm ? 12 : 0), _minute),
    );
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth >= _kGridWidth + _kGapBetween + _kTimeWidth) {
          return Row(
            mainAxisAlignment: .center,
            crossAxisAlignment: .start,
            spacing: _kGapBetween,
            children: [grid, time],
          );
        }
        return Column(spacing: 16, children: [grid, time]);
      },
    );
  }
}

// ---- pieces ----------------------------------------------------------------

/// The focus ring is for the keyboard: a mouse or a finger that opened the picker
/// does not get one.
bool _keyboardFocused(FocusNode node) =>
    node.hasFocus && FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 1,
    child: ColoredBox(
      color: PTColors.rail,
      child: SizedBox(width: double.infinity),
    ),
  );
}

enum _CaptionKind { info, warning, error }

typedef _Note = ({_CaptionKind kind, String text});

/// "April 2027": the month's name slides as a word the way the month went, and the
/// year only moves when the year does.
class _MonthTitle extends StatelessWidget {
  const _MonthTitle({required this.view, required this.dir});

  final DateTime view;
  final int dir;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: .min,
      spacing: 6,
      children: [
        PTShift(
          keyValue: view.month,
          axis: Axis.horizontal,
          dir: dir,
          distance: 0.3,
          align: Alignment.centerLeft,
          child: Text(monthLong(view.month), style: PTText.panelHeading, maxLines: 1),
        ),
        PTRollingText(
          '${view.year}',
          style: PTText.panelHeading,
          axis: Axis.horizontal,
          dir: dir,
          distance: 0.3,
        ),
      ],
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption({required this.kind, required this.text});

  final _CaptionKind kind;
  final String text;

  @override
  Widget build(BuildContext context) {
    final (fg, bg, icon) = switch (kind) {
      .info => (PTColors.fgDim, PTColors.well, BoothIcons.info),
      .warning => (PTColors.warning, PTColors.pillWarning, BoothIcons.alert),
      .error => (PTColors.danger, PTColors.dangerSurface, BoothIcons.alert),
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(PTRadius.control)),
        child: Row(
          crossAxisAlignment: .start,
          spacing: 10,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 16, color: fg),
            ),
            Expanded(
              child: Text(
                text,
                style: PTText.caption.copyWith(color: fg, height: 18 / 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PartnerLine extends StatelessWidget {
  const _PartnerLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Row(
    spacing: 8,
    children: [
      const Icon(BoothIcons.globe, size: 16, color: PTColors.fgMute),
      Expanded(
        child: Text(text, style: PTText.caption.copyWith(color: PTColors.fgDim)),
      ),
    ],
  );
}

/// Rebuilds [builder] with whether the pointer is over it. Mouse only; a finger
/// never hovers.
class _Hover extends StatefulWidget {
  const _Hover({required this.builder, this.enabled = true});

  final Widget Function(BuildContext context, bool hovered) builder;
  final bool enabled;

  @override
  State<_Hover> createState() => _HoverState();
}

class _HoverState extends State<_Hover> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: widget.enabled ? SystemMouseCursors.click : MouseCursor.defer,
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: widget.builder(context, _hovered && widget.enabled),
  );
}

class _TodayChip extends StatelessWidget {
  const _TodayChip({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Today',
      excludeSemantics: true,
      child: PTPressable(
        onTap: onTap,
        child: _Hover(
          builder: (context, hovered) => AnimatedContainer(
            duration: PTMotion.functional(context, PTMotion.hover),
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: hovered ? PTColors.white(0.06) : Colors.transparent,
              borderRadius: BorderRadius.circular(PTRadius.control),
              border: Border.all(color: selected ? PTColors.primary : PTColors.railStrong),
            ),
            child: AnimatedSize(
              duration: PTMotion.functional(context, PTMotion.state),
              curve: PTMotion.enter,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: .min,
                spacing: 6,
                children: [
                  if (selected) const Icon(BoothIcons.check, size: 14, color: PTColors.primary),
                  Text(
                    'Today',
                    style: PTText.caption.copyWith(
                      color: selected ? PTColors.primary : PTColors.fg,
                      fontWeight: .w500,
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

/// One wheel column. Reports a row only when the finger settles on it (and ticks
/// the haptic motor on touch platforms); a change from outside is followed by
/// animating, or by jumping under reduce-motion.
class _Wheel extends StatefulWidget {
  const _Wheel({
    required this.label,
    required this.count,
    required this.index,
    required this.text,
    required this.onChanged,
    this.greyed,
    this.invalid = false,
  });

  final String label;
  final int count;
  final int index;
  final String Function(int index) text;
  final bool Function(int index)? greyed;
  final bool invalid;
  final ValueChanged<int> onChanged;

  @override
  State<_Wheel> createState() => _WheelState();
}

class _WheelState extends State<_Wheel> {
  late final FixedExtentScrollController _controller;
  late int _shown;
  bool _programmatic = false;

  @override
  void initState() {
    super.initState();
    _shown = widget.index;
    _controller = FixedExtentScrollController(initialItem: widget.index);
  }

  @override
  void didUpdateWidget(_Wheel old) {
    super.didUpdateWidget(old);
    if (widget.index != _shown) {
      _shown = widget.index;
      _goTo(widget.index);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int i) {
    if (!_controller.hasClients) return;
    _programmatic = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.jumpToItem(i);
      _programmatic = false;
    } else {
      _controller
          .animateToItem(i, duration: PTMotion.state, curve: PTMotion.enter)
          .whenComplete(() => _programmatic = false);
    }
  }

  void _settled(int i) {
    if (_programmatic) return;
    if (i == _shown) return;
    setState(() => _shown = i);
    if (defaultTargetPlatform == .iOS || defaultTargetPlatform == .android) {
      HapticFeedback.selectionClick();
    }
    widget.onChanged(i);
  }

  TextStyle _style(int distance, bool greyed) {
    final base = switch (distance) {
      0 => PTText.buttonLabel.copyWith(color: widget.invalid ? PTColors.danger : PTColors.primary),
      1 => PTText.body.copyWith(color: PTColors.fgDim),
      _ => PTText.body.copyWith(color: PTColors.fgMute),
    };
    return greyed && distance != 0
        ? base.copyWith(color: base.color!.withValues(alpha: _kDisabledOpacity))
        : base;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.label,
      value: widget.text(widget.index.clamp(0, widget.count - 1)),
      increasedValue: widget.index + 1 < widget.count ? widget.text(widget.index + 1) : null,
      decreasedValue: widget.index > 0 ? widget.text(widget.index - 1) : null,
      onIncrease: widget.index + 1 < widget.count ? () => widget.onChanged(widget.index + 1) : null,
      onDecrease: widget.index > 0 ? () => widget.onChanged(widget.index - 1) : null,
      child: ExcludeSemantics(
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            scrollbars: false,
            dragDevices: {
              PointerDeviceKind.touch,
              PointerDeviceKind.mouse,
              PointerDeviceKind.trackpad,
              PointerDeviceKind.stylus,
            },
          ),
          child: ListWheelScrollView.useDelegate(
            controller: _controller,
            itemExtent: _kRow,
            diameterRatio: 6,
            perspective: 0.001,
            overAndUnderCenterOpacity: 1,
            physics: const FixedExtentScrollPhysics(),
            onSelectedItemChanged: _settled,
            childDelegate: ListWheelChildBuilderDelegate(
              childCount: widget.count,
              builder: (context, i) {
                final greyed = widget.greyed?.call(i) ?? false;
                final selected = i == _shown;
                return Center(
                  child: Opacity(
                    opacity: greyed && selected ? _kDisabledOpacity : 1,
                    // The row you land on eases into the selected look.
                    child: AnimatedDefaultTextStyle(
                      duration: PTMotion.functional(context, PTMotion.hover),
                      style: _style((i - _shown).abs(), greyed),
                      maxLines: 1,
                      child: Text(widget.text(i)),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.view,
    required this.selected,
    required this.today,
    required this.min,
    required this.max,
    required this.firstWeekday,
    required this.compact,
    required this.focused,
    required this.focusNode,
    required this.onKey,
    required this.onPick,
    required this.onMonth,
    required this.dir,
  });

  /// Which way the month last moved: the grid slides in from that side.
  final int dir;
  final DateTime view;
  final DateTime selected;
  final DateTime today;
  final DateTime min;
  final DateTime max;
  final int firstWeekday;
  final bool compact;
  final bool focused;
  final FocusNode focusNode;
  final KeyEventResult Function(FocusNode, KeyEvent) onKey;
  final ValueChanged<DateTime> onPick;
  final ValueChanged<int> onMonth;

  @override
  Widget build(BuildContext context) {
    // Always six rows, so the dialog is the same height in every month; a month
    // that needs five leaves the last row empty.
    final month = monthCells(view.year, view.month, firstWeekday: firstWeekday);
    final cells = [...month, ...List<DateTime?>.filled(42 - month.length, null)];
    final rowHeight = compact ? 32.0 : 40.0;
    final before = hasMonthBefore(view.year, view.month, min);
    final after = hasMonthAfter(view.year, view.month, max);
    return Focus(
      focusNode: focusNode,
      onKeyEvent: onKey,
      child: SizedBox(
        width: _kGridWidth,
        child: Column(
          mainAxisSize: .min,
          children: [
            SizedBox(
              height: 40,
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _MonthTitle(view: view, dir: dir),
                    ),
                  ),
                  _IconStep(
                    icon: BoothIcons.chevronLeft,
                    label: 'Previous month',
                    onTap: before ? () => onMonth(-1) : null,
                  ),
                  _IconStep(
                    icon: BoothIcons.chevronRight,
                    label: 'Next month',
                    onTap: after ? () => onMonth(1) : null,
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 28,
              child: Row(
                children: [
                  for (final w in weekdayOrder(firstWeekday))
                    SizedBox(
                      width: _kCell,
                      child: Center(
                        child: Text(
                          weekdayShort(w).substring(0, 1).toUpperCase(),
                          style: PTText.label,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // A month with five rows beside one with six: the grid folds to the new
            // height as one motion instead of the dialog jumping.
            PTShift(
              keyValue: view,
              axis: Axis.horizontal,
              dir: dir,
              distance: 0.12,
              child: Padding(
                // Room for the keyboard ring around a day in the first or last row.
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  mainAxisSize: .min,
                  children: [
                    for (var r = 0; r < cells.length ~/ 7; r++)
                      Row(
                        children: [
                          for (var c = 0; c < 7; c++)
                            _DayCell(
                              day: cells[r * 7 + c],
                              height: rowHeight,
                              selected: cells[r * 7 + c] == selected,
                              isToday: cells[r * 7 + c] == today,
                              enabled:
                                  cells[r * 7 + c] != null &&
                                  !cells[r * 7 + c]!.isBefore(min) &&
                                  !cells[r * 7 + c]!.isAfter(max),
                              ring: focused && cells[r * 7 + c] == selected,
                              onTap: onPick,
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.height,
    required this.selected,
    required this.isToday,
    required this.enabled,
    required this.ring,
    required this.onTap,
  });

  final DateTime? day;
  final double height;
  final bool selected;
  final bool isToday;
  final bool enabled;
  final bool ring;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final d = day;
    if (d == null) return SizedBox(width: _kCell, height: height);
    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: '${monthLong(d.month)} ${d.day}',
      excludeSemantics: true,
      child: _Hover(
        enabled: enabled,
        builder: (context, hovered) => PTPressable(
          enabled: enabled,
          onTap: () => onTap(d),
          child: SizedBox(
            width: _kCell,
            height: height,
            child: Center(
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  if (ring)
                    Positioned(
                      left: -4,
                      right: -4,
                      top: -4,
                      bottom: -4,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(PTRadius.control + 2),
                          border: Border.all(color: PTColors.primary, width: 2),
                        ),
                      ),
                    ),
                  AnimatedContainer(
                    duration: PTMotion.functional(context, PTMotion.hover),
                    width: 36,
                    height: height - 4,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected
                          ? (hovered ? PTColors.accentSoft : PTColors.primary)
                          : (hovered ? PTColors.white(0.06) : Colors.transparent),
                      borderRadius: BorderRadius.circular(PTRadius.control),
                      border: isToday && !selected ? Border.all(color: PTColors.railStrong) : null,
                    ),
                    child: Opacity(
                      opacity: enabled ? 1 : _kDisabledOpacity,
                      child: Text(
                        '${d.day}',
                        style: PTText.body.copyWith(
                          color: selected
                              ? PTColors.onAccent
                              : (enabled ? PTColors.fg : PTColors.fgMute),
                          fontWeight: selected ? .w600 : .w400,
                        ),
                      ),
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

/// A small icon button (36 x 36, hover fill, the PT press scale).
class _IconStep extends StatelessWidget {
  const _IconStep({required this.icon, required this.label, required this.onTap, this.width = 36});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: _Hover(
        enabled: enabled,
        builder: (context, hovered) => PTPressable(
          enabled: enabled,
          onTap: onTap,
          child: AnimatedContainer(
            duration: PTMotion.functional(context, PTMotion.hover),
            width: width,
            height: width == 36 ? 36 : 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: hovered ? PTColors.white(0.06) : Colors.transparent,
              borderRadius: BorderRadius.circular(PTRadius.control),
            ),
            child: Opacity(
              opacity: enabled ? 1 : _kDisabledOpacity,
              child: Icon(icon, size: 18, color: PTColors.fgDim),
            ),
          ),
        ),
      ),
    );
  }
}

class _TimeColumn extends StatelessWidget {
  const _TimeColumn({
    required this.hour,
    required this.minute,
    required this.is24,
    required this.invalid,
    required this.hourDir,
    required this.minuteDir,
    required this.hourFocus,
    required this.minuteFocus,
    required this.onHourKey,
    required this.onMinuteKey,
    required this.onHour,
    required this.onMinute,
    required this.onMeridiem,
  });

  final int hour;
  final int minute;
  final bool is24;
  final bool invalid;
  final int hourDir;
  final int minuteDir;
  final FocusNode hourFocus;
  final FocusNode minuteFocus;
  final KeyEventResult Function(FocusNode, KeyEvent) onHourKey;
  final KeyEventResult Function(FocusNode, KeyEvent) onMinuteKey;
  final ValueChanged<int> onHour;
  final ValueChanged<int> onMinute;
  final ValueChanged<bool> onMeridiem;

  @override
  Widget build(BuildContext context) {
    final pm = hour >= 12;
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    return SizedBox(
      width: _kTimeWidth,
      child: Column(
        crossAxisAlignment: .start,
        spacing: 8,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('TIME', style: PTText.label),
          ),
          Row(
            mainAxisAlignment: .center,
            crossAxisAlignment: .center,
            spacing: 4,
            children: [
              _Segment(
                value: is24 ? hour.toString().padLeft(2, '0') : '$h12',
                moreLabel: 'More hours',
                lessLabel: 'Less hours',
                focusNode: hourFocus,
                onKey: onHourKey,
                invalid: invalid,
                dir: hourDir,
                onStep: onHour,
              ),
              Text(':', style: PTText.mono.copyWith(fontSize: 18, color: PTColors.fgMute)),
              _Segment(
                value: minute.toString().padLeft(2, '0'),
                moreLabel: 'More minutes',
                lessLabel: 'Less minutes',
                focusNode: minuteFocus,
                onKey: onMinuteKey,
                invalid: invalid,
                dir: minuteDir,
                onStep: onMinute,
              ),
            ],
          ),
          if (!is24)
            Row(
              mainAxisAlignment: .center,
              spacing: 6,
              children: [
                _MeridiemButton(label: 'AM', selected: !pm, onTap: () => onMeridiem(false)),
                _MeridiemButton(label: 'PM', selected: pm, onTap: () => onMeridiem(true)),
              ],
            ),
          Text('Type a time, or use the Up and Down arrow keys.', style: PTText.finePrint),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.value,
    required this.moreLabel,
    required this.lessLabel,
    required this.focusNode,
    required this.onKey,
    required this.invalid,
    required this.dir,
    required this.onStep,
  });

  final String value;
  final String moreLabel;
  final String lessLabel;
  final FocusNode focusNode;
  final KeyEventResult Function(FocusNode, KeyEvent) onKey;
  final bool invalid;
  final int dir;
  final ValueChanged<int> onStep;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      children: [
        _IconStep(icon: BoothIcons.chevronUp, label: moreLabel, width: 64, onTap: () => onStep(1)),
        Focus(
          focusNode: focusNode,
          onKeyEvent: onKey,
          child: Builder(
            builder: (context) {
              final focused = _keyboardFocused(focusNode);
              return GestureDetector(
                onTap: focusNode.requestFocus,
                child: Container(
                  width: 64,
                  height: 46,
                  alignment: Alignment.center,
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  decoration: BoxDecoration(
                    color: PTColors.well,
                    borderRadius: BorderRadius.circular(PTRadius.control),
                    border: Border.all(
                      color: focused ? PTColors.primary : PTColors.rail,
                      width: focused ? 2 : 1,
                    ),
                  ),
                  child: Semantics(
                    label: 'Time',
                    value: value,
                    child: PTRollingText(
                      value,
                      dir: dir,
                      align: Alignment.center,
                      style: PTText.mono.copyWith(
                        fontSize: 18,
                        fontWeight: .w600,
                        color: invalid ? PTColors.danger : PTColors.fg,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        _IconStep(
          icon: BoothIcons.chevronDown,
          label: lessLabel,
          width: 64,
          onTap: () => onStep(-1),
        ),
      ],
    );
  }
}

class _MeridiemButton extends StatelessWidget {
  const _MeridiemButton({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: PTPressable(
        onTap: onTap,
        child: _Hover(
          builder: (context, hovered) => AnimatedContainer(
            duration: PTMotion.functional(context, PTMotion.hover),
            width: 56,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: hovered ? PTColors.white(0.06) : Colors.transparent,
              borderRadius: BorderRadius.circular(PTRadius.control),
              border: Border.all(color: selected ? PTColors.primary : PTColors.railStrong),
            ),
            child: Text(
              label,
              style: PTText.caption.copyWith(
                color: selected ? PTColors.primary : PTColors.fgDim,
                fontWeight: .w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
