import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../diagnostics.dart';

const _kCollapsedKey = 'pt.room.roster_collapsed';

/// How long the roster stays open after the last person clears the gate, so the
/// rings turning Cue are seen to land before the strip folds away.
const kRosterAutoCollapseDelay = Duration(milliseconds: 1400);

/// Whether the phone room's "In the room" strip is folded to its slim row.
///
/// The strip answers one question - who is here and has everyone cleared the
/// gate - and once everyone has, it only costs the chat its height. So it folds
/// by itself the first time the gate clears ([observe] -> [autoDelay] later),
/// unless the viewer already chose; their choice then holds for the rest of the
/// room ([toggle] cancels any pending fold and marks the room decided).
///
/// What carries across rooms and launches is only "I keep it folded": expanding
/// by hand clears it, because a peek at an auto-folded strip must not turn into
/// "never fold it again". A viewer convenience like `EmojiPrefs` - shared
/// preferences, every read and write guarded, failure degrades to the default.
///
/// Owned by the room (not the chat panel), which remounts when the layout class
/// changes; the fold must survive that. Not analytics: a toggle is a layout
/// preference, not a product action anyone would act on.
class RosterFold extends ChangeNotifier {
  RosterFold({this.autoDelay = kRosterAutoCollapseDelay});

  final Duration autoDelay;

  bool _collapsed = false;
  bool _decided = false;
  Future<void>? _loading;
  Timer? _timer;

  bool get collapsed => _collapsed;

  /// A choice is in force for this room (a toggle, or the remembered fold), so
  /// the gate clearing no longer folds it.
  bool get decided => _decided;

  /// Reads the remembered fold. Safe to call more than once.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_kCollapsedKey) != true || _decided) return;
      _decided = true;
      _timer?.cancel();
      _collapsed = true;
      notifyListeners();
    } catch (e, s) {
      reportNonFatal(e, s, during: 'reading the roster fold');
    }
  }

  /// Fed the room's head count whenever it changes. Never notifies directly -
  /// it runs from a widget's update - and only arms or disarms the auto fold.
  void observe({required int total, required int ready}) {
    final clear = total > 0 && ready == total;
    if (_decided || _collapsed || !clear) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer(autoDelay, _autoFold);
  }

  void _autoFold() {
    _timer = null;
    if (_decided || _collapsed) return;
    _collapsed = true;
    trace('roster folded, everyone ready', category: 'room');
    notifyListeners();
  }

  /// The viewer's own tap.
  void toggle() {
    _timer?.cancel();
    _timer = null;
    _decided = true;
    _collapsed = !_collapsed;
    trace('roster toggled', category: 'room', data: {'collapsed': _collapsed});
    notifyListeners();
    _save(_collapsed);
  }

  Future<void> _save(bool collapsed) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (collapsed) {
        await prefs.setBool(_kCollapsedKey, true);
      } else {
        await prefs.remove(_kCollapsedKey);
      }
    } catch (e, s) {
      reportNonFatal(e, s, during: 'saving the roster fold');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
