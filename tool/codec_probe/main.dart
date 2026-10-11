// Codec conformance probe: opens every clip in PROBE_DIR (made by
// tool/codec_samples.sh) in a real media_kit Player on this platform and writes
// PROBE_OUT/codec_probe.json. A clip passes when it decodes video (if it has
// any), decodes audio (if it has any), advances in time, and mpv reports no
// decoder failure. `known_gap_*` clips are reported but never fail the run. Run it on every platform: parity is what this proves.
//
//   fvm flutter run -d <macos|windows|...> -t tool/codec_probe/main.dart \
//     --dart-define=PROBE_DIR=<samples dir> --dart-define=PROBE_OUT=<out dir>
//
// Not shipped: nothing in lib/ imports it.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';

const _dirDefine = String.fromEnvironment('PROBE_DIR');
const _outDefine = String.fromEnvironment('PROBE_OUT');

/// `--dart-define=PROBE_VO=null` decodes without presenting (for emulators whose
/// GPU cannot give mpv a GL context). Decoders are still fully exercised.
const _vo = String.fromEnvironment('PROBE_VO');
late String _dir;
late String _out;

/// Desktop: the dart-defines. Mobile has no free-form filesystem, so the clips
/// live in the app's own storage: `<documents>/samples` on iOS (devicectl copy
/// to the appDataContainer), `<external files>/samples` on Android (adb push).
Future<void> _resolvePaths() async {
  if (_dirDefine.isNotEmpty) {
    _dir = _dirDefine;
    _out = _outDefine.isNotEmpty ? _outDefine : _dirDefine;
    return;
  }
  final base = Platform.isAndroid
      ? (await getExternalStorageDirectory())!
      : await getApplicationDocumentsDirectory();
  _dir = '${base.path}/samples';
  _out = base.path;
}

Future<String> _prop(Player p, String k) async {
  try {
    return await (p.platform as NativePlayer).getProperty(k);
  } catch (_) {
    return '';
  }
}

Future<Map<String, Object?>> _probe(Player player, File f) async {
  final errors = <String>[];
  final mpvLog = <String>[];
  var advanced = false;
  var maxPos = Duration.zero;
  final subs = [
    player.stream.error.listen(errors.add),
    player.stream.log.listen((l) {
      if (l.text.contains('Failed to initialize a decoder')) errors.add(l.text.trim());
      if (l.level == 'error' || l.level == 'warn') {
        mpvLog.add('${l.prefix}: ${l.text.trim()}');
        if (mpvLog.length > 4) mpvLog.removeAt(0);
      }
    }),
    player.stream.position.listen((p) {
      if (p > maxPos) maxPos = p;
      if (p >= const Duration(seconds: 1)) advanced = true;
    }),
  ];
  try {
    await player.open(Media(f.path)).timeout(const Duration(seconds: 10));
  } catch (e) {
    errors.add('open: $e');
  }
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline) && !advanced) {
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  final vw = await _prop(player, 'video-params/w');
  final aFmt = await _prop(player, 'audio-params/format');
  final aid = await _prop(player, 'aid');
  final vid = await _prop(player, 'vid');
  final result = <String, Object?>{
    'file': f.uri.pathSegments.last,
    'advanced': advanced,
    'max_position_ms': maxPos.inMilliseconds,
    'video_codec': await _prop(player, 'video-codec'),
    'video_w': vw,
    'audio_codec': await _prop(player, 'audio-codec-name'),
    'audio_decoded': aFmt.isNotEmpty,
    'has_audio_track': aid.isNotEmpty && aid != 'no',
    'has_video_track': vid.isNotEmpty && vid != 'no',
    'hwdec': await _prop(player, 'hwdec-current'),
    'errors': errors.toSet().toList(),
    'mpv_log': mpvLog.toList(),
    'duration_ms': player.state.duration.inMilliseconds,
    'playing': player.state.playing,
  };
  final failed = errors.isNotEmpty;
  result['pass'] =
      advanced &&
      !failed &&
      (result['has_video_track'] != true || vw.isNotEmpty) &&
      (result['has_audio_track'] != true || aFmt.isNotEmpty);
  for (final s in subs) {
    await s.cancel();
  }
  try {
    await player.stop().timeout(const Duration(seconds: 5));
  } catch (_) {}
  return result;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await _resolvePaths();
  debugPrint('PROBE dir=$_dir out=$_out');
  final files =
      Directory(_dir).listSync().whereType<File>().where((f) => !f.path.contains('/.')).toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final probe = Player(
    configuration: PlayerConfiguration(logLevel: MPVLogLevel.warn, vo: _vo.isEmpty ? null : _vo),
  );
  if (_vo.isEmpty) {
    // A real, mounted Video surface: Android's mpv cannot create its GPU context
    // without one, so a bare controller reports every clip as failing.
    runApp(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(width: 320, height: 180, child: Video(controller: VideoController(probe))),
      ),
    );
  } else {
    runApp(const SizedBox.shrink());
    // media_kit leaves video decoding off until a VideoController attaches.
    await (probe.platform as NativePlayer).setProperty('vid', 'auto');
  }
  await Future<void>.delayed(const Duration(seconds: 1));
  final report = <String, Object?>{
    'platform': '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    'mpv': await _prop(probe, 'mpv-version'),
    'ffmpeg': await _prop(probe, 'ffmpeg-version'),
  };
  final rows = <Map<String, Object?>>[];
  for (final f in files) {
    final r = await _probe(probe, f);
    rows.add(r);
    debugPrint('ROW ${jsonEncode(r)}');
    debugPrint('${r['pass'] == true ? 'PASS' : 'FAIL'}  ${r['file']}  ${r['errors']}');
  }
  report['results'] = rows;
  // `known_gap_*` clips document a difference we have accepted (see
  // docs/codec-support.md): reported, but they do not fail the run.
  report['failed'] = rows
      .where((r) => r['pass'] != true && !(r['file']! as String).startsWith('known_gap_'))
      .map((r) => r['file'])
      .toList();
  File(
    '$_out/codec_probe.json',
  ).writeAsStringSync(const JsonEncoder.withIndent(' ').convert(report));
  final passed = rows.where((r) => r['pass'] == true).length;
  final gaps = rows
      .where((r) => r['pass'] != true && (r['file']! as String).startsWith('known_gap_'))
      .length;
  debugPrint(
    'DONE $passed/${rows.length} passed, $gaps known gap(s), ${(report['failed']! as List).length} failed',
  );
  await Future<void>.delayed(const Duration(seconds: 2));
  exit((report['failed']! as List).isEmpty ? 0 : 1);
}
