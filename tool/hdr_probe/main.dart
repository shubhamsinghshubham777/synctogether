// Visual colour probe: plays one clip full-screen through the same
// Player + VideoController + applyVideoQualityOptions chain the room uses, and
// dumps mpv's view of the stream (hwdec, pixel format, matrix, primaries,
// transfer) so a tint can be matched to a decode path. Not shipped.
//
// It polls `<documents>/samples/_cmd.txt` once a second; a new line of the form
//   <clip file name> [hwdec=<mode>] [extra mpv option=value ...]
// opens that clip. After 2.5 s it writes `<documents>/status.json`.
//
//   fvm flutter run -d <ios sim> -t tool/hdr_probe/main.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:synctogether/player/video_surface.dart';

late Player player;
late NativePlayer native;
final label = ValueNotifier<String>('waiting for _cmd.txt');

Future<String> prop(String k) async {
  try {
    return await native.getProperty(k);
  } catch (_) {
    return '';
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final docs = await getApplicationDocumentsDirectory();
  player = Player(configuration: const PlayerConfiguration(logLevel: MPVLogLevel.warn));
  native = player.platform! as NativePlayer;
  final controller = VideoController(player);
  unawaited(applyVideoQualityOptions(player));
  player.stream.log.listen((l) => debugPrint('MPV ${l.level} ${l.prefix}: ${l.text.trim()}'));
  player.stream.videoParams.listen(
    (p) => debugPrint('PARAMS ${p.pixelformat} ${p.hwPixelformat} ${p.gamma} ${p.primaries}'),
  );
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Video(controller: controller, controls: NoVideoControls),
            Align(
              alignment: Alignment.bottomLeft,
              child: ValueListenableBuilder<String>(
                valueListenable: label,
                builder: (_, v, _) => Container(
                  color: const Color(0xAA000000),
                  padding: const EdgeInsets.all(4),
                  child: Text(v, style: const TextStyle(fontSize: 9, color: Colors.white)),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  var last = '';
  Timer.periodic(const Duration(seconds: 1), (_) async {
    final cmd = File('${docs.path}/samples/_cmd.txt');
    if (!cmd.existsSync()) return;
    final line = cmd.readAsStringSync().trim();
    if (line.isEmpty || line == last) return;
    last = line;
    final parts = line.split(RegExp(r'\s+'));
    await native.setProperty('vf', '');
    await native.setProperty('hwdec', 'auto');
    for (final o in parts.skip(1)) {
      final i = o.indexOf('=');
      await native.setProperty(o.substring(0, i), o.substring(i + 1));
    }
    if (parts.first.contains('rot')) await controller.setSize(width: 720, height: 1280);
    await player.open(Media('${docs.path}/samples/${parts.first}'));
    // The simulator renders in software; size the surface like the room does
    // (display size, rotation applied) so a rotated clip cannot trip mpv's crop.
    if (Platform.environment.containsKey('SIMULATOR_DEVICE_NAME')) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final dw = int.tryParse(await prop('video-params/dw')) ?? 0;
      final dh = int.tryParse(await prop('video-params/dh')) ?? 0;
      final rot = int.tryParse(await prop('video-params/rotate')) ?? 0;
      if (dw > 0 && dh > 0) {
        final w = rot % 180 == 0 ? dw : dh, h = rot % 180 == 0 ? dh : dw;
        await controller.setSize(width: w, height: h);
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    final s = <String, String>{
      'cmd': line,
      'hwdec-current': await prop('hwdec-current'),
      'hwdec': await prop('hwdec'),
      'vo-configured': await prop('vo-configured'),
      'video-codec': await prop('video-codec'),
      'pixelformat': await prop('video-params/pixelformat'),
      'hw-pixelformat': await prop('video-params/hw-pixelformat'),
      'colormatrix': await prop('video-params/colormatrix'),
      'primaries': await prop('video-params/primaries'),
      'gamma': await prop('video-params/gamma'),
      'colorlevels': await prop('video-params/colorlevels'),
      'sig-peak': await prop('video-params/sig-peak'),
      'rotate': await prop('video-params/rotate'),
      'w': await prop('video-params/w'),
      'h': await prop('video-params/h'),
      'dw': await prop('video-params/dw'),
      'out-pixelformat': await prop('video-out-params/pixelformat'),
      'out-colormatrix': await prop('video-out-params/colormatrix'),
      'out-gamma': await prop('video-out-params/gamma'),
      'vf': await prop('vf'),
      'tone-mapping': await prop('tone-mapping'),
    };
    label.value = s.entries.map((e) => '${e.key}=${e.value}').join('  ');
    File(
      '${docs.path}/status.json',
    ).writeAsStringSync(const JsonEncoder.withIndent(' ').convert(s));
    debugPrint('STATUS ${jsonEncode(s)}');
  });
}
