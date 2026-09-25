import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/diagnostics.dart';
import 'package:synctogether/player/subtitles/subtitle_style.dart';

const _kStyleKey = 'pt.subtitles.style';

/// The viewer's subtitle style, per device. The `EmojiPrefs` shape: a viewer
/// convenience, so shared_preferences, every read and write wrapped, failures
/// degrade to the defaults - and cleared on sign-out and account deletion so
/// a second account on the machine starts from the default look.
class SubtitlePrefs extends ChangeNotifier {
  SubtitlePrefs();
  static final instance = SubtitlePrefs();

  SubtitleStyle _style = SubtitleStyle.defaults();
  Future<void>? _loading;

  SubtitleStyle get style => _style;

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_kStyleKey);
      if (raw != null) _style = SubtitleStyle.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'reading subtitle preferences');
    }
    notifyListeners();
  }

  /// Applies [style] at once; [persist] false is for a slider mid-drag, which
  /// saves on its drag end instead of on every tick.
  void update(SubtitleStyle style, {bool persist = true}) {
    if (style != _style) {
      _style = style;
      notifyListeners();
    }
    if (persist) _save();
  }

  void reset() => update(SubtitleStyle.defaults());

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kStyleKey, jsonEncode(_style.toJson()));
    } catch (e, s) {
      reportNonFatal(e, s, during: 'saving subtitle preferences');
    }
  }

  Future<void> clear() async {
    _style = SubtitleStyle.defaults();
    _loading = null;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).remove(_kStyleKey);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'clearing subtitle preferences');
    }
  }
}
