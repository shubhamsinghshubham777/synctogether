import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:synctogether/ui/pt_theme.dart';

/// The room control bar's space-driven collapse (board 46).
///
/// The bar never scales, wraps or clips: it picks the first of a ladder of
/// designed *forms* whose natural width fits the slot it was given, the way
/// `FirstFit` does for the lobby header. The seek bar (with both time labels)
/// and play/pause are in every form; only the icons beside them fold, into one
/// More button, in a fixed order. This file is the decision, as pure functions
/// over plain values, so a test can drive it without a render tree.

/// Every control a room bar can carry, in the order the More list shows them.
enum BarControl {
  mic,
  camera,
  react,
  skipBack,
  skipForward,
  source,
  openFile,
  audio,
  subtitles,
  hide,
  volume,
  fullscreen,
}

/// The forms of the bar. The phone ladder is [f1] -> [f5]; the touch tablet's
/// floating bar replaces the first two with [t0] and [t1] (no F2: its SUBS key
/// and volume stay longer) and shares [f3] -> [f5] below them.
enum RoomBarForm {
  /// Two rows: seek on top, every control beneath it.
  f1(112, 552),

  /// One row; the source group and the skips have folded.
  f2(64, 484),

  /// ...and react.
  f3(64, 436),

  /// ...and the camera.
  f4(64, 388),

  /// The floor: seek, play and More.
  f5(64, 332),

  /// Tablet, full: SUBS key and the volume slider.
  t0(112, 580),

  /// Tablet, the slider folded to the volume glyph.
  t1(112, 470);

  const RoomBarForm(this.height, this.minWidth);

  /// The bar's outer height at this form, in logical pixels.
  final double height;

  /// The width this form is designed for at 1.0 text scale.
  final double minWidth;

  bool get twoRows => height > 64;

  /// What this form has folded into More. A superset across both ladders: a
  /// control the bar does not carry is simply absent.
  Set<BarControl> get folded => switch (this) {
    f1 || t0 || t1 => const {},
    f2 => _afterSource,
    f3 => {..._afterSource, BarControl.react},
    f4 => {..._afterSource, BarControl.react, BarControl.camera},
    f5 => {..._afterSource, BarControl.react, BarControl.camera, BarControl.mic},
  };

  static const _afterSource = {
    BarControl.hide,
    BarControl.source,
    BarControl.openFile,
    BarControl.audio,
    BarControl.subtitles,
    BarControl.volume,
    BarControl.fullscreen,
    BarControl.skipBack,
    BarControl.skipForward,
  };
}

/// Where the phone ladder and the tablet ladder differ.
const kPhoneLadder = [
  RoomBarForm.f1,
  RoomBarForm.f2,
  RoomBarForm.f3,
  RoomBarForm.f4,
  RoomBarForm.f5,
];
const kTabletLadder = [
  RoomBarForm.t0,
  RoomBarForm.t1,
  RoomBarForm.f3,
  RoomBarForm.f4,
  RoomBarForm.f5,
];

/// What a bar carries right now - the inputs to "which form fits".
@immutable
class RoomBarCaps {
  const RoomBarCaps({
    required this.controls,
    this.tablet = false,
    this.hourLabels = true,
    this.subsKeyLabel = 'SUBS · EN',
  });

  final Set<BarControl> controls;

  /// The touch tablet's floating bar (T0/T1 rather than F1/F2).
  final bool tablet;

  /// The media is an hour or longer, so the time labels are `h:mm:ss`.
  final bool hourLabels;

  /// The tablet's typed SUBS key, whose width follows the selected track.
  final String subsKeyLabel;

  List<RoomBarForm> get ladder => tablet ? kTabletLadder : kPhoneLadder;

  bool has(BarControl c) => controls.contains(c);
}

const _kInset = 24.0; // 1 px border + 11 px padding, either side
const _kKey = 44.0;
const _kPlay = 52.0;
const _kGap = 4.0; // between keys in a group
const _kGroupGap = 12.0; // between groups on the one-row forms
const _kSeekGap = 8.0; // time - seek - time
const _kSeekFloor = 80.0; // the narrowest the scrubber is drawn

/// The time labels' width. Both labels share the width of the *duration's*
/// format, so it is stable while the playhead crosses an hour; clamped to 1.3x
/// text like the labels themselves.
double timeLabelWidth(TextScaler scaler, {required bool hours}) {
  final painter = TextPainter(
    text: TextSpan(
      text: hours ? '0:00:00' : '00:00',
      style: PTText.mono.copyWith(fontSize: kTimeLabelSize),
    ),
    textDirection: TextDirection.ltr,
    textScaler: scaler.clamp(maxScaleFactor: 1.3),
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width.floorToDouble();
}

const kTimeLabelSize = 11.0;

/// The typed SUBS key's width: its label plus 10 px either side.
double subsKeyWidth(TextScaler scaler, String label) {
  final painter = TextPainter(
    text: TextSpan(
      text: label,
      style: PTText.mono.copyWith(fontSize: 11, letterSpacing: 11 * 0.06),
    ),
    textDirection: TextDirection.ltr,
    textScaler: scaler.clamp(maxScaleFactor: 1.3),
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return (width + 20).ceilToDouble();
}

double _group(int n, double each) => n == 0 ? 0 : n * each + (n - 1) * _kGap;

/// The width [form] needs for [caps] at [scaler]: what the board draws at 1.0
/// text, growing with the time labels (and the SUBS key) at larger text.
double naturalWidth(RoomBarForm form, RoomBarCaps caps, TextScaler scaler) {
  final labels = timeLabelWidth(scaler, hours: caps.hourLabels);
  final seek = 2 * labels + 2 * _kSeekGap + _kSeekFloor;
  final folded = form.folded;
  bool shown(BarControl c) => caps.has(c) && !folded.contains(c);
  final avCount = [BarControl.mic, BarControl.camera, BarControl.react].where(shown).length;

  if (form.twoRows) {
    final left = _group(avCount, _kKey);
    final skips = _kKey + _kPlay + _kKey + 2 * _kGap;
    final double right;
    if (caps.tablet) {
      final subs = shown(BarControl.subtitles) ? subsKeyWidth(scaler, caps.subsKeyLabel) : 0.0;
      final vol = shown(BarControl.volume)
          ? _kKey + (form == RoomBarForm.t0 ? 90 + _kGap : 0)
          : 0.0;
      final full = shown(BarControl.fullscreen) ? _kKey : 0.0;
      final parts = [subs, vol, full].where((w) => w > 0).toList();
      right = parts.fold(0.0, (a, b) => a + b) + _kGap * math.max(0, parts.length - 1);
    } else {
      right = _group(
        [
          BarControl.source,
          BarControl.openFile,
          BarControl.audio,
          BarControl.subtitles,
          BarControl.hide,
          BarControl.fullscreen,
        ].where(shown).length,
        _kKey,
      );
    }
    // Row two is left | skips | right with at least a hair between them.
    final row = left + skips + right + 4;
    return _kInset + math.max(row, seek);
  }

  final foldedAny = caps.controls.any(folded.contains);
  return _kInset +
      seek +
      _kGroupGap +
      _kPlay +
      (avCount > 0 ? _kGroupGap + _group(avCount, _kKey) : 0) +
      (foldedAny ? _kGroupGap + _kKey : 0);
}

/// The width at which [form] is first chosen: what it measures for the
/// controls the bar actually carries. A guest's bar has no mic or camera, so
/// its forms fit sooner than the board's full set. (The measured widths of F1
/// to F5 with every control are exactly the board's 552/484/436/388/332.) The
/// tablet forms keep the board's looser 580/470 where the measure is smaller.
double thresholdOf(RoomBarForm form, RoomBarCaps caps, TextScaler scaler) {
  final measured = naturalWidth(form, caps, scaler);
  return caps.tablet && form.twoRows ? math.max(form.minWidth, measured) : measured;
}

/// The first form of the ladder whose width fits [slot]; the floor, squeezed,
/// when none does.
///
/// [accepts] is the second input - height. With facecams on, a form is only
/// taken if the rail slot it leaves still holds two tiles and the +N pill. When
/// none of the forms that fit is accepted, the tallest-controls form that is
/// also short (64) wins: the rail is better served by height than by the
/// two-row form.
RoomBarForm pickBarForm({
  required double slot,
  required RoomBarCaps caps,
  required TextScaler scaler,
  bool Function(RoomBarForm form)? accepts,
}) {
  final fits = [
    for (final form in caps.ladder)
      if (thresholdOf(form, caps, scaler) <= slot + 0.5) form,
  ];
  if (fits.isEmpty) return RoomBarForm.f5;
  if (accepts == null) return fits.first;
  for (final form in fits) {
    if (accepts(form)) return form;
  }
  return fits.firstWhere((f) => !f.twoRows, orElse: () => fits.first);
}

/// The narrower of two forms of the same ladder.
RoomBarForm narrowerOf(RoomBarForm a, RoomBarForm b, RoomBarCaps caps) {
  final ladder = caps.ladder;
  final ia = ladder.indexOf(a);
  final ib = ladder.indexOf(b);
  if (ia < 0) return b;
  if (ib < 0) return a;
  return ia >= ib ? a : b;
}

/// Hands the form the layout chose (it alone knows about chat and the facecam
/// rail) to the bar below it. The bar still never draws a form wider than its
/// real width, so it stays correct while the slot animates.
class RoomBarFormScope extends InheritedWidget {
  const RoomBarFormScope({super.key, required this.form, required super.child});

  final RoomBarForm form;

  static RoomBarForm? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RoomBarFormScope>()?.form;

  @override
  bool updateShouldNotify(RoomBarFormScope old) => old.form != form;
}

// ---------------------------------------------------------------------------
// Facecam rail

/// Distance from the bottom of the layout box to the bar's bottom edge.
const double kLandscapeBarInset = 22;

/// Clearance between the rail and the bar's top edge.
const double kRailGap = 12;

/// Top of the rail slot, under the header row.
const double kRailTop = 72;

/// Space the control bar takes at the bottom of the landscape layout for
/// [form]: its inset plus its height (~134 for F1, ~86 for F2 to F5).
double landscapeControlsReserve(RoomBarForm form) => kLandscapeBarInset + form.height;

/// The rail's slot height for [form] in a layout box [boxHeight] tall.
double railSlotHeight(double boxHeight, RoomBarForm form) =>
    boxHeight - landscapeControlsReserve(form) - kRailGap - kRailTop;

/// How the facecam rail is drawn in a slot [slotHeight] tall.
@immutable
class RailPlan {
  const RailPlan({required this.large, required this.tiles});

  /// 136x77 tiles when the slot is roomy, 104x58 otherwise.
  final bool large;

  /// How many tiles the slot holds beside the +N pill.
  final int tiles;

  double get tileWidth => large ? 136 : 104;
  double get tileHeight => large ? 77 : 58;

  /// Two tiles and the pill is the least a rail is worth showing.
  bool get holdsTwo => tiles >= 2;
}

RailPlan railPlanFor(double slotHeight) {
  final large = slotHeight >= 210;
  final tile = large ? 77.0 : 58.0;
  final tiles = slotHeight.isFinite ? ((slotHeight - 44) / (tile + 6)).floor() : 0;
  return RailPlan(large: large, tiles: math.max(0, tiles));
}

// ---------------------------------------------------------------------------
// Chat beside the bar

/// The narrowest slot the bar is ever given beside an open chat.
const double kBarSlotFloor = 332;

/// The chat's own floor: narrower than this and it is not worth a column.
const double kChatColumnFloor = 180;

/// The chat column's width in phone landscape for a safe width of [safeWidth]:
/// `min(300, 38%, safeWidth - 12 - 332)`, never under [kChatColumnFloor].
double landscapeChatWidth(double safeWidth) => math.max(
  kChatColumnFloor,
  math.min(300.0, math.min(safeWidth * 0.38, safeWidth - 12 - kBarSlotFloor)),
);

/// Whether a chat column and the floor-width bar both fit beside each other.
bool landscapeChatFits(double safeWidth) => safeWidth >= kChatColumnFloor + 12 + kBarSlotFloor;
