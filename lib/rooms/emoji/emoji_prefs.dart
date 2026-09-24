import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../diagnostics.dart';
import 'emoji_logic.dart';

const _kRecentKey = 'pt.emoji.recent';
const _kToneKey = 'pt.emoji.skin_tone';
const _kUsageKey = 'pt.emoji.usage';
const _kPinsKey = 'pt.emoji.pins';

/// The picker's per-device memory: recents, the remembered skin tone, the
/// usage scores behind the quick bar and its pinned slots.
///
/// A viewer convenience, never state anything depends on - so it is
/// shared_preferences, every read and write is wrapped, and a failure degrades
/// to the defaults. It does not follow the account across devices, and it is
/// cleared on sign-out beside `UnlockLog` so a second account on the machine
/// does not inherit the first one's favourites.
class EmojiPrefs extends ChangeNotifier {
  EmojiPrefs();
  static final instance = EmojiPrefs();

  bool _loaded = false;
  Future<void>? _loading;
  List<String> _recent = const [];
  int _tone = 0;
  Map<String, EmojiUsage> _usage = const {};
  List<String?> _pins = List.filled(kQuickSlotCount, null);

  bool get loaded => _loaded;
  List<String> get recent => _recent;
  int get tone => _tone;
  Map<String, EmojiUsage> get usage => _usage;
  List<String?> get pins => List.unmodifiable(_pins);

  /// Snapshot of the bar as of now. Callers decide *when* to take one - the
  /// panel only re-reads at open and after a send, so a slot never moves under
  /// the pointer.
  List<QuickSlot> quickSlots() =>
      quickBarSlots(pins: _pins, usage: _usage, now: clock.now(), tone: _tone);

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _recent = prefs.getStringList(_kRecentKey) ?? const [];
      _tone = (prefs.getInt(_kToneKey) ?? 0).clamp(0, 5);
      final usage = prefs.getString(_kUsageKey);
      if (usage != null) {
        _usage = {
          for (final MapEntry(:key, :value) in (jsonDecode(usage) as Map<String, dynamic>).entries)
            key: EmojiUsage(
              (value[0] as num).toDouble(),
              DateTime.fromMillisecondsSinceEpoch(value[1] as int),
            ),
        };
      }
      final pins = prefs.getStringList(_kPinsKey);
      if (pins != null) {
        _pins = [
          for (var i = 0; i < kQuickSlotCount; i++)
            i < pins.length && pins[i].isNotEmpty ? pins[i] : null,
        ];
      }
    } catch (e, s) {
      reportNonFatal(e, s, during: 'reading emoji preferences');
    }
    _loaded = true;
    notifyListeners();
  }

  void notePicked(String emoji) {
    _recent = pushRecent(_recent, emoji);
    notifyListeners();
    _save((prefs) => prefs.setStringList(_kRecentKey, _recent));
  }

  void noteSent(String text) {
    final sent = emojiIn(text);
    if (sent.isEmpty) return;
    _usage = recordEmojiUse(_usage, sent, clock.now());
    // No notify: the bar re-reads on its own schedule (see [quickSlots]).
    final encoded = jsonEncode({
      for (final MapEntry(:key, :value) in _usage.entries)
        key: [value.score, value.at.millisecondsSinceEpoch],
    });
    _save((prefs) => prefs.setString(_kUsageKey, encoded));
  }

  void setTone(int tone) {
    if (tone == _tone) return;
    _tone = tone.clamp(0, 5);
    notifyListeners();
    _save((prefs) => prefs.setInt(_kToneKey, _tone));
  }

  void setPin(int slot, String? emoji) {
    if (slot < 0 || slot >= kQuickSlotCount) return;
    _pins = [..._pins]..[slot] = emoji;
    notifyListeners();
    _savePins();
  }

  /// Pins the whole bar as currently shown, then swaps two slots - how the
  /// editor's reorder works without an "empty" slot ever appearing.
  void swapSlots(int a, int b, List<QuickSlot> shown) {
    if (a == b) return;
    final next = [
      for (var i = 0; i < kQuickSlotCount; i++) _pins[i] ?? shown.elementAtOrNull(i)?.emoji,
    ];
    final moved = next[a];
    next[a] = next[b];
    next[b] = moved;
    _pins = next;
    notifyListeners();
    _savePins();
  }

  void resetQuickBar() {
    _pins = List.filled(kQuickSlotCount, null);
    _usage = const {};
    notifyListeners();
    _save((prefs) async {
      await prefs.remove(_kPinsKey);
      await prefs.remove(_kUsageKey);
      return true;
    });
  }

  void _savePins() =>
      _save((prefs) => prefs.setStringList(_kPinsKey, [for (final p in _pins) p ?? '']));

  Future<void> clear() async {
    _recent = const [];
    _tone = 0;
    _usage = const {};
    _pins = List.filled(kQuickSlotCount, null);
    notifyListeners();
    await _save((prefs) async {
      for (final key in [_kRecentKey, _kToneKey, _kUsageKey, _kPinsKey]) {
        await prefs.remove(key);
      }
      return true;
    });
  }

  Future<void> _save(Future<bool> Function(SharedPreferences prefs) write) async {
    try {
      await write(await SharedPreferences.getInstance());
    } catch (e, s) {
      reportNonFatal(e, s, during: 'saving emoji preferences');
    }
  }
}
