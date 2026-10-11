// EXPERIMENT ONLY (exp/win-libmpv-full): headless libmpv probe. Not shipped.
//
// fvm flutter run -d windows -t tool/exp_probe/main.dart \
//   --dart-define=PROBE_DIR=<media dir> --dart-define=PROBE_OUT=<out dir> --dart-define=PROBE_MODE=codec|subs|misc
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:synctogether/player/subtitles/subtitle_style.dart';
import 'package:synctogether/player/video_surface.dart';

final _dir = Platform.environment['PROBE_DIR']!;
final _out = Platform.environment['PROBE_OUT']!;
final _mode = Platform.environment['PROBE_MODE'] ?? 'codec';

late Player player;
late VideoController vc;
final results = <String, Object?>{};
final errors = <String>[];
final logs = <String>[];

Future<String> prop(String k) async {
  try {
    stdout.writeln('prop $k');
    return await (player.platform as NativePlayer).getProperty(k);
  } catch (e) {
    return '<ERR $e>';
  }
}

Future<List<Map<String, String>>> trackList() async {
  final n = int.tryParse(await prop('track-list/count')) ?? 0;
  final out = <Map<String, String>>[];
  for (var i = 0; i < n; i++) {
    out.add({
      'id': await prop('track-list/$i/id'),
      'type': await prop('track-list/$i/type'),
      'codec': await prop('track-list/$i/codec'),
      'lang': await prop('track-list/$i/lang'),
    });
  }
  return out;
}

Future<double> cpuMs() async {
  final r = await Process.run('powershell', [
    '-NoProfile',
    '-Command',
    '(Get-Process -Id $pid).TotalProcessorTime.TotalMilliseconds',
  ]);
  return double.tryParse((r.stdout as String).trim()) ?? -1;
}

void save() => File(
  '$_out/result_$_mode.json',
).writeAsStringSync(const JsonEncoder.withIndent(' ').convert(results));

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  stdout.writeln('S1 ensureInitialized ok');
  player = Player(configuration: const PlayerConfiguration(logLevel: MPVLogLevel.warn));
  stdout.writeln('S2 player ok');
  vc = VideoController(player);
  stdout.writeln('S3 vc created');
  player.stream.error.listen((e) => errors.add(e));
  player.stream.log.listen((l) {
    if (logs.length < 400) logs.add('${l.level}/${l.prefix}: ${l.text.trim()}');
  });
  await applyVideoQualityOptions(player).timeout(
    const Duration(seconds: 10),
    onTimeout: () => stdout.writeln('TIMEOUT applyVideoQualityOptions'),
  );
  stdout.writeln('S4 quality opts ok');
  runApp(
    MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Video(controller: vc, controls: NoVideoControls),
      ),
    ),
  );
  stdout.writeln('S5 runApp done');
  await Future<void>.delayed(const Duration(seconds: 2));
  Directory(_out).createSync(recursive: true);
  stdout.writeln('STARTED');
  results['mpv-version'] = await prop('mpv-version');
  results['ffmpeg-version'] = await prop('ffmpeg-version');
  results['libmpv-api'] = await prop('mpv-configuration');
  try {
    switch (_mode) {
      case 'codec':
        await codecRun();
      case 'subs':
        await subsRun();
      case 'misc':
        await miscRun();
      case 'opts':
        await optsRun();
      case 'live':
        await liveRun();
    }
  } catch (e, s) {
    results['FATAL'] = '$e\n$s';
  }
  save();
  stdout.writeln('PROBE_DONE');
  exit(0);
}

Future<void> codecRun() async {
  final files =
      Directory(_dir)
          .listSync()
          .whereType<File>()
          .where((f) => !f.path.endsWith('.srt') && !f.path.endsWith('.ass'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in files) {
    final name = f.uri.pathSegments.last;
    stdout.writeln('FILE $name');
    errors.clear();
    logs.clear();
    final r = <String, Object?>{};
    results[name] = r;
    try {
      final opened = Completer<void>();
      final sub = player.stream.duration.listen((d) {
        if (d > Duration.zero && !opened.isCompleted) opened.complete();
      });
      await player.open(Media(f.path), play: true);
      await opened.future.timeout(const Duration(seconds: 10), onTimeout: () {});
      await sub.cancel();
      await Future<void>.delayed(const Duration(seconds: 2));
      r['duration'] = player.state.duration.inSeconds;
      r['video-codec'] = await prop('video-codec');
      r['audio-codec'] = await prop('audio-codec');
      r['video-params'] = '${await prop('video-params/w')}x${await prop('video-params/h')}';
      r['pixelformat'] = await prop('video-params/pixelformat');
      r['audio-params'] =
          '${await prop('audio-params/format')} ${await prop('audio-params/channels')}';
      r['audio-out-params'] = await prop('audio-out-params/format');
      r['hwdec-current'] = await prop('hwdec-current');
      r['vo-configured'] = await prop('vo-configured');
      r['ao'] = await prop('current-ao');
      final t0 = await prop('time-pos');
      final c0 = await cpuMs();
      final d0 = await prop('frame-drop-count');
      final dd0 = await prop('decoder-frame-drop-count');
      await Future<void>.delayed(const Duration(seconds: 5));
      final c1 = await cpuMs();
      final t1 = await prop('time-pos');
      r['time-pos-advance(5s wall)'] = '$t0 -> $t1';
      r['cpu-%-of-1-core(5s, includes powershell spawn)'] = ((c1 - c0) / 5000 * 100).round();
      r['vo-drops'] = '$d0 -> ${await prop('frame-drop-count')}';
      r['decoder-drops'] = '$dd0 -> ${await prop('decoder-frame-drop-count')}';
      r['estimated-vf-fps'] = await prop('estimated-vf-fps');
      r['container-fps'] = await prop('container-fps');
      final tl = await trackList();
      r['tracks'] = tl.map((t) => '${t['type']}:${t['id']}:${t['codec']}').toList();
      await player.pause();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final p1 = await prop('time-pos');
      await Future<void>.delayed(const Duration(milliseconds: 700));
      r['pause-holds'] = p1 == await prop('time-pos');
      await player.play();
      await Future<void>.delayed(const Duration(milliseconds: 700));
      r['resumes'] = (player.state.playing);
      final aud = tl.where((t) => t['type'] == 'audio').toList();
      if (aud.length > 1) {
        await (player.platform as NativePlayer).setProperty('aid', aud[1]['id']!);
        await Future<void>.delayed(const Duration(milliseconds: 800));
        r['switch-audio'] = 'aid=${await prop('aid')} codec=${await prop('audio-codec')}';
        await (player.platform as NativePlayer).setProperty('aid', aud[0]['id']!);
        await Future<void>.delayed(const Duration(milliseconds: 500));
        r['switch-audio-back'] = 'aid=${await prop('aid')} codec=${await prop('audio-codec')}';
      }
      for (final s in tl.where((t) => t['type'] == 'sub')) {
        await (player.platform as NativePlayer).setProperty('sid', s['id']!);
        await Future<void>.delayed(const Duration(milliseconds: 600));
        r['switch-sub ${s['id']}'] = 'sid=${await prop('sid')} codec=${await prop('sub-codec')}';
      }
      final shot = await player.screenshot(format: 'image/jpeg', includeLibassSubtitles: true);
      if (shot != null) {
        File('$_out/shot_$name.jpg').writeAsBytesSync(shot);
        r['screenshot-bytes'] = shot.length;
      } else {
        r['screenshot-bytes'] = null;
      }
    } catch (e, s) {
      r['EXCEPTION'] = '$e\n$s';
    }
    r['errors'] = List<String>.from(errors);
    r['log-warn+'] = logs
        .where((l) => !l.contains('timestamp') && !l.contains('Using hardware decoding'))
        .take(12)
        .toList();
    save();
  }
}

int _diff(List<int> a, List<int> b) {
  if (a.length != b.length) return -1;
  var n = 0;
  for (var i = 0; i < a.length; i += 4) {
    if (a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2]) n++;
  }
  return n;
}

Future<void> subsRun() async {
  final cases = <String, SubtitleStyle Function(SubtitleStyle)>{
    'font-size(scale 1.8)': (s) => s.copyWith(scale: 1.8),
    'text-colour(yellow)': (s) => s.copyWith(textColor: 0xFFFFFF00),
    'outline-width(0)': (s) => s.copyWith(outlineSize: 0),
    'outline-width(6)': (s) => s.copyWith(outlineSize: 6),
    'outline-colour(red)': (s) => s.copyWith(outlineColor: 0xFFFF0000),
    'shadow(offset 6, colour blue)': (s) => s.copyWith(shadowOffset: 6, shadowColor: 0xFF0000FF),
    'background-box(black 80%)': (s) => s.copyWith(backgroundColor: 0xCC000000, outlineSize: 0),
    'position(50)': (s) => s.copyWith(position: 50),
    'position(20)': (s) => s.copyWith(position: 20),
    'bold': (s) => s.copyWith(weight: 700),
    'italic': (s) => s.copyWith(italic: true),
    'blur(8, with outline 3)': (s) => s.copyWith(blur: 8),
    'letter-spacing(6)': (s) => s.copyWith(letterSpacing: 6),
    'align-left': (s) => s.copyWith(align: SubtitleAlign.left),
    'override-embedded(on)': (s) => s.copyWith(overrideEmbedded: true),
  };
  final files =
      Directory(_dir).listSync().whereType<File>().where((f) => f.path.contains('subs_')).toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final native = player.platform as NativePlayer;
  final optionsList = await prop('options');
  results['options-property-length'] = optionsList.length;
  final base = SubtitleStyle.defaults();
  final keys = toMpvProperties(base, font: 'Arial', bold: false, italic: false).keys.toList();
  results['option-existence'] = {
    for (final k in keys) k: optionsList.contains('"$k"') || optionsList.contains(k),
  };
  for (final f in files) {
    final name = f.uri.pathSegments.last;
    final passes = <(String, int, bool)>[
      ('ass-default', 0, false),
      ('ass-override-on', 0, true),
      ('srt', 1, false),
    ];
    for (final pass in passes) {
      final key = '$name/${pass.$1}';
      final r = <String, Object?>{};
      results[key] = r;
      await player.open(Media(f.path), play: true);
      await Future<void>.delayed(const Duration(seconds: 2));
      final subsT = (await trackList()).where((t) => t['type'] == 'sub').toList();
      r['tracks'] = subsT.map((t) => '${t['id']}:${t['codec']}').toList();
      await native.setProperty('sid', subsT[pass.$2]['id']!);
      await player.seek(const Duration(seconds: 3));
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await player.pause();
      Future<List<int>> shot(String tag) async {
        // A paused frame only repaints libass after a seek: force one each time.
        await native.command(['seek', '3', 'absolute+exact']);
        await Future<void>.delayed(const Duration(milliseconds: 900));
        final j = await player.screenshot(format: 'image/jpeg', includeLibassSubtitles: true);
        if (j != null) File('$_out/sub_${name}_${pass.$1}_$tag.jpg').writeAsBytesSync(j);
        return await player.screenshot(format: null, includeLibassSubtitles: true) ?? <int>[];
      }

      Future<void> apply(SubtitleStyle s) async {
        final m = toMpvProperties(s, font: 'Arial', bold: s.weight >= 600, italic: s.italic);
        if (pass.$3) m['sub-ass-override'] = 'force';
        for (final e in m.entries) {
          try {
            await native.setProperty(e.key, e.value);
          } catch (err) {
            ((r['setProperty-errors'] ??= <String>[]) as List<String>).add('${e.key}: $err');
          }
        }
      }

      await apply(base);
      await shot('warm');
      final baseline = await shot('base');
      await native.setProperty('sub-visibility', 'no');
      final hidden = await shot('hidden');
      await native.setProperty('sub-visibility', 'yes');
      r['subtitle-visible(px differing from hidden; must be >0)'] = _diff(baseline, hidden);
      await apply(base);
      final changes = <String, Object?>{};
      r['px-diff-vs-baseline'] = changes;
      changes['CONTROL re-apply defaults (must be 0)'] = _diff(baseline, await shot('control'));
      for (final c in cases.entries) {
        if (c.key.startsWith('override-embedded') && pass.$3) continue;
        await apply(c.value(base));
        changes[c.key] = _diff(baseline, await shot(c.key.replaceAll(RegExp('[^a-z0-9]+'), '_')));
      }
      await apply(base);
      save();
    }
  }
}

Future<void> miscRun() async {
  final f = Directory(
    _dir,
  ).listSync().whereType<File>().firstWhere((f) => f.path.endsWith('h264_aac.mp4'));
  await player.open(Media(f.path), play: true);
  await Future<void>.delayed(const Duration(seconds: 2));
  // Resize via VideoSurfaceSizer's underlying call.
  final sizes = [(1280, 720), (640, 360), (1920, 1080), (3840, 2160), (800, 450)];
  final resize = <String>[];
  for (final s in sizes) {
    try {
      await vc.setSize(width: s.$1, height: s.$2);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      final j = await player.screenshot(format: 'image/jpeg');
      resize.add('${s.$1}x${s.$2}: ok shot=${j?.length}');
    } catch (e) {
      resize.add('${s.$1}x${s.$2}: ERR $e');
    }
  }
  results['resize'] = resize;
  results['errors'] = List<String>.from(errors);
  results['log'] = logs.take(30).toList();
}

Future<void> optsRun() async {
  final native = player.platform as NativePlayer;
  final opts = await prop('options');
  results['sub-options'] = RegExp(
    r'"(sub-[a-z0-9-]+|secondary-sub-[a-z0-9-]+)"',
  ).allMatches(opts).map((m) => m.group(1)).toSet().toList()..sort();
  results['mentions-outline'] = opts.contains('sub-outline-size');
  results['mentions-border-style'] = opts.contains('sub-border-style');
  final f = Directory(
    _dir,
  ).listSync().whereType<File>().firstWhere((f) => f.path.contains('subs_'));
  await player.open(Media(f.path), play: true);
  await Future<void>.delayed(const Duration(seconds: 2));
  final subsT = (await trackList()).where((t) => t['type'] == 'sub').toList();
  await native.setProperty('sid', subsT[1]['id']!);
  await player.seek(const Duration(seconds: 3));
  await Future<void>.delayed(const Duration(milliseconds: 500));
  await player.pause();
  Future<List<int>> shot(String tag) async {
    await native.command(['seek', '3', 'absolute+exact']);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    final j = await player.screenshot(format: 'image/jpeg', includeLibassSubtitles: true);
    if (j != null) File('$_out/opt_$tag.jpg').writeAsBytesSync(j);
    return await player.screenshot(format: null, includeLibassSubtitles: true) ?? <int>[];
  }

  Future<void> set(Map<String, String> m) async {
    for (final e in m.entries) {
      try {
        await native.setProperty(e.key, e.value);
      } catch (err) {
        ((results['set-errors'] ??= <String>[]) as List<String>).add('${e.key}=${e.value}: $err');
      }
    }
    await native.setProperty('sid', 'no');
    await native.setProperty('sid', subsT[1]['id']!);
  }

  final base = {
    'sub-border-size': '3',
    'sub-border-color': '#FF000000',
    'sub-shadow-offset': '0',
    'sub-shadow-color': '#99000000',
    'sub-back-color': '#00000000',
    'sub-color': '#FFFFFFFF',
  };
  await native.setProperty('sub-visibility', 'no');
  await Future<void>.delayed(const Duration(milliseconds: 400));
  await native.setProperty('sub-visibility', 'yes');
  await set(base);
  await shot('warm');
  final baseline = await shot('base');
  final out = <String, Object?>{};
  results['candidates'] = out;
  Future<void> cand(String name, Map<String, String> m, [Map<String, String>? reset]) async {
    await set(base);
    if (reset != null) await set(reset);
    await shot('reset');
    await set(m);
    out[name] = _diff(baseline, await shot(name.replaceAll(RegExp('[^A-Za-z0-9]+'), '_')));
    final rb = <String>[];
    for (final k in m.keys) {
      rb.add('$k -> ${await prop(k)}');
    }
    out['$name (readback)'] = rb;
  }

  await cand('control-noop', {'sub-border-size': '3'});
  await cand('old: shadow 6 blue', {'sub-shadow-offset': '6', 'sub-shadow-color': '#FF0000FF'});
  await cand('old: back-color box', {'sub-back-color': '#CC000000', 'sub-border-size': '0'});
  await cand('new: outline-size 0', {'sub-outline-size': '0'});
  await cand('new: outline-color red', {'sub-outline-color': '#FFFF0000'});
  await cand('new: border-style=background-box + back-color', {
    'sub-border-style': 'background-box',
    'sub-back-color': '#CC000000',
  });
  await cand('new: border-style=outline-and-shadow + shadow 6 blue', {
    'sub-border-style': 'outline-and-shadow',
    'sub-shadow-offset': '6',
    'sub-shadow-color': '#FF0000FF',
  });
  await cand('new: shadow 6 blue, outline 0', {
    'sub-shadow-offset': '6',
    'sub-shadow-color': '#FF0000FF',
    'sub-border-size': '0',
  });
  await cand('new: sub-shadow-offset 12 opaque', {
    'sub-shadow-offset': '12',
    'sub-shadow-color': '#FFFF0000',
  });
  results['option-info sub-shadow-offset'] = [
    for (final k in ['type', 'default-value', 'min', 'max'])
      '$k=${await prop('option-info/sub-shadow-offset/$k')}',
  ];
  results['option-info sub-back-color'] = [
    for (final k in ['type', 'default-value']) '$k=${await prop('option-info/sub-back-color/$k')}',
  ];
  results['option-info sub-border-style'] = [
    for (final k in ['type', 'default-value', 'choices'])
      '$k=${await prop('option-info/sub-border-style/$k')}',
  ];
  results['sub-font-size'] = await prop('sub-font-size');
  results['sub-scale'] = await prop('sub-scale');
  results['osd-height/width'] =
      '${await prop('osd-dimensions/h')} / ${await prop('osd-dimensions/w')}';
}

int _diffRegion(List<int> a, List<int> b, int x0, int x1, int y0, int y1) {
  if (a.length != b.length || a.length != 1280 * 720 * 4) return -1;
  var n = 0;
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      final i = (y * 1280 + x) * 4;
      if (a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2]) n++;
    }
  }
  return n;
}

Future<void> liveRun() async {
  final native = player.platform as NativePlayer;
  final f = Directory(
    _dir,
  ).listSync().whereType<File>().firstWhere((f) => f.path.contains('subs_'));
  await player.open(Media(f.path), play: true);
  await Future<void>.delayed(const Duration(seconds: 2));
  final subsT = (await trackList()).where((t) => t['type'] == 'sub').toList();
  await native.setProperty('sid', subsT[1]['id']!);
  await native.setProperty('sub-visibility', 'no');
  await Future<void>.delayed(const Duration(milliseconds: 300));
  await native.setProperty('sub-visibility', 'yes');
  final base = {
    'sub-border-size': '3',
    'sub-border-color': '#FF000000',
    'sub-shadow-offset': '0',
    'sub-shadow-color': '#99000000',
    'sub-back-color': '#00000000',
    'sub-color': '#FFFFFFFF',
    'sub-border-style': 'outline-and-shadow',
  };
  // Static part of the frame under the subtitle: no moving test-pattern content.
  Future<List<int>> playShot(String tag) async {
    await native.command(['seek', '2', 'absolute+exact']);
    await player.play();
    await Future<void>.delayed(const Duration(milliseconds: 1300));
    await player.pause();
    final j = await player.screenshot(format: 'image/jpeg', includeLibassSubtitles: true);
    if (j != null) File('$_out/live_$tag.jpg').writeAsBytesSync(j);
    return await player.screenshot(format: null, includeLibassSubtitles: true) ?? <int>[];
  }

  Future<void> setAll(Map<String, String> m) async {
    for (final e in m.entries) {
      try {
        await native.setProperty(e.key, e.value);
      } catch (err) {
        ((results['set-errors'] ??= <String>[]) as List<String>).add('${e.key}: $err');
      }
    }
  }

  if (_isNew()) {
    await setAll(base);
  } else {
    base.remove('sub-border-style');
    await setAll(base);
  }
  await playShot('warm');
  final baseline = await playShot('base');
  final out = <String, Object?>{};
  results['live-region-diff(live property write, NO track reload, video playing then paused)'] =
      out;
  Future<void> cand(String name, Map<String, String> m) async {
    await setAll(base);
    await playShot('reset');
    await setAll(m);
    out[name] = _diffRegion(
      baseline,
      await playShot(name.replaceAll(RegExp('[^A-Za-z0-9]+'), '_')),
      360,
      780,
      570,
      710,
    );
  }

  await cand('control: same values again (must be 0)', {'sub-border-size': '3'});
  await cand('text colour yellow', {'sub-color': '#FFFFFF00'});
  await cand('outline size 0', {'sub-border-size': '0'});
  await cand('shadow offset 6 + blue', {'sub-shadow-offset': '6', 'sub-shadow-color': '#FF0000FF'});
  await cand('app-style box (sub-back-color only, outline 0)', {
    'sub-back-color': '#CC000000',
    'sub-border-size': '0',
  });
  if (_isNew()) {
    await cand('0.41 box (border-style=background-box + back-color)', {
      'sub-border-style': 'background-box',
      'sub-back-color': '#CC000000',
    });
  }
}

bool _isNew() => (results['mpv-version'] as String).contains('v0.4');
