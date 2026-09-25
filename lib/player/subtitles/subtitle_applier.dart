import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:synctogether/diagnostics.dart';
import 'package:synctogether/player/subtitles/subtitle_prefs.dart';
import 'package:synctogether/player/subtitles/subtitle_style.dart';
import 'package:synctogether/player/subtitles/system_fonts.dart';

/// The font bundled for libass on Android, which cannot see system fonts.
/// Droid Sans Fallback: wide CJK/Unicode coverage.
const kAndroidSubtitleFontAsset = 'assets/subfont.ttf';
const kAndroidSubtitleFontName = 'Droid Sans Fallback';

/// Keeps one [Player]'s mpv `sub-*` options in step with [SubtitlePrefs].
///
/// mpv keeps these options across `open()`, so they are applied once and then
/// only on change, and only the keys that changed are written. Changes apply
/// as they happen - a slider drag moves the subtitles live - and ticks that
/// land while a write is in flight coalesce into one follow-up write of the
/// latest style, so the rate is bounded by mpv, never queued behind it.
class SubtitleStyleApplier {
  SubtitleStyleApplier(this.player, {SubtitlePrefs? prefs})
    : _prefs = prefs ?? SubtitlePrefs.instance {
    _prefs.addListener(_schedule);
    unawaited(_prefs.load().then((_) => _schedule()));
  }

  final Player player;
  final SubtitlePrefs _prefs;
  Map<String, String> _applied = const {};
  bool _running = false, _again = false, _disposed = false, _traced = false;
  String? _androidFontsDir;
  String? _androidFontFile;

  void _schedule() {
    if (!_disposed) unawaited(_apply());
  }

  Future<void> _apply() async {
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        await _applyOnce(_prefs.style);
      } while (_again && !_disposed);
    } finally {
      _running = false;
    }
  }

  Future<void> _applyOnce(SubtitleStyle style) async {
    final native = player.platform;
    if (_disposed || native is! NativePlayer) return;
    final (:font, :bold, :italic, :fontsChanged) = await _resolveFont(style);
    final wanted = toMpvProperties(style, font: font, bold: bold, italic: italic);
    final changed = {
      for (final e in wanted.entries)
        if (_applied[e.key] != e.value) e.key: e.value,
    };
    for (final e in changed.entries) {
      if (_disposed) return;
      try {
        await native.setProperty(e.key, e.value);
      } catch (e2, s) {
        reportNonFatal(e2, s, during: 'setting subtitle option ${e.key}');
      }
    }
    _applied = wanted;
    // A new fonts dir is only read when a subtitle track initialises.
    if (fontsChanged) await _reloadSubtitleTrack(native);
    if (!_traced && !_disposed) {
      _traced = true;
      final d = SubtitleStyle.defaults().toJson();
      trace(
        'subtitle style applied',
        category: 'media',
        data: {
          for (final e in style.toJson().entries)
            if (d[e.key] != e.value) e.key: e.value,
        },
      );
    }
  }

  Future<({String font, bool bold, bool italic, bool fontsChanged})> _resolveFont(
    SubtitleStyle style,
  ) async {
    final wantsBold = style.weight >= 600;
    final fallback = Platform.isAndroid ? kAndroidSubtitleFontName : 'sans-serif';
    final familyName = style.fontFamily;
    final family = familyName == null ? null : await SystemFonts.find(familyName);
    final face = family == null ? null : resolveFace(family, style.weight, style.italic);
    if (face == null) {
      // No such family any more (uninstalled, or a generic name): the name
      // itself, with synthesised weight and slant.
      return (
        font: familyName ?? fallback,
        bold: wantsBold,
        italic: style.italic,
        fontsChanged: false,
      );
    }
    // A named face already carries its weight and slant; synthesise only what
    // the nearest one lacks.
    final bold = wantsBold && face.weight < 600;
    final italic = style.italic && !face.italic;
    if (!Platform.isAndroid || face.path == null) {
      return (font: face.name, bold: bold, italic: italic, fontsChanged: false);
    }
    try {
      final (name, changed) = await _stageAndroidFont(face.path!);
      return (font: name ?? fallback, bold: bold, italic: italic, fontsChanged: changed);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'staging an Android subtitle font');
      return (font: fallback, bold: wantsBold, italic: style.italic, fontsChanged: false);
    }
  }

  /// libass on Android only reads fonts from `sub-fonts-dir`, so the chosen
  /// system font is copied into a directory of our own beside the bundled
  /// fallback, and libass is asked for it by the name *inside* the file.
  Future<(String?, bool)> _stageAndroidFont(String source) async {
    final native = player.platform as NativePlayer;
    var changed = false;
    var dir = _androidFontsDir;
    if (dir == null) {
      dir = p.join((await getApplicationSupportDirectory()).path, 'subtitle_fonts');
      await Directory(dir).create(recursive: true);
      final bundled = File(p.join(dir, p.basename(kAndroidSubtitleFontAsset)));
      if (!await bundled.exists()) {
        final data = await rootBundle.load(kAndroidSubtitleFontAsset);
        await bundled.writeAsBytes(data.buffer.asUint8List(), flush: true);
      }
      await native.setProperty('sub-fonts-dir', dir);
      _androidFontsDir = dir;
      changed = true;
    }
    final target = File(p.join(dir, 'chosen_${p.basename(source)}'));
    if (_androidFontFile != target.path) {
      // One chosen font at a time; the directory is rescanned per track.
      await for (final f in Directory(dir).list()) {
        if (f is File && p.basename(f.path).startsWith('chosen_') && f.path != target.path) {
          await f.delete();
        }
      }
      if (!await target.exists()) await File(source).copy(target.path);
      _androidFontFile = target.path;
      changed = true;
    }
    final names = readFontNames(await target.readAsBytes());
    return (names?.full ?? names?.family, changed);
  }

  Future<void> _reloadSubtitleTrack(NativePlayer native) async {
    try {
      final sid = await native.getProperty('sid');
      if (sid.isEmpty || sid == 'no') return;
      await native.setProperty('sid', 'no');
      await native.setProperty('sid', sid);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'reloading the subtitle track for a new font');
    }
  }

  void dispose() {
    _disposed = true;
    _prefs.removeListener(_schedule);
  }
}
