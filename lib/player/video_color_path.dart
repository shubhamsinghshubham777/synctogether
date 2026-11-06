import 'dart:async';
import 'dart:io';

import 'package:media_kit/media_kit.dart';
import 'package:synctogether/diagnostics.dart';

/// `--dart-define=MPV_HWDEC=<mode>` forces mpv's `hwdec` on iOS and turns the
/// automatic choice below off. A diagnostics aid for comparing decode paths on
/// a TestFlight/dev build (`auto`, `videotoolbox`, `videotoolbox-copy`, `no`);
/// it has no UI and is empty in store builds.
const kMpvHwdecOverride = String.fromEnvironment('MPV_HWDEC');

/// How to decode one stream: the `hwdec` mode and an optional `vf` chain.
class VideoPathPlan {
  const VideoPathPlan({required this.hwdec, required this.vf, required this.reason});

  /// The cheap default: VideoToolbox zero-copy straight into the GL texture.
  static const standard = VideoPathPlan(hwdec: 'auto', vf: '', reason: 'standard');

  final String hwdec;

  /// mpv `vf` value; empty clears the chain.
  final String vf;
  final String reason;

  bool get isStandard => hwdec == standard.hwdec && vf.isEmpty;
}

final _highDepth = RegExp(r'p(10|12|14|16)|^p(010|012|016|210|216|410|416)');
const _hdrGammas = {'hlg', 'pq', 'v-log', 's-log1', 's-log2'};

/// Whether mpv's pixel-format name (`yuv420p10`, `p010`, `gbrp12`...) carries
/// more than 8 bits per component.
bool isHighBitDepthFormat(String? format) =>
    format != null && _highDepth.hasMatch(format.toLowerCase());

/// Which decode path [params] needs on iOS.
///
/// mpv's iOS output is OpenGL ES (`Dios-gl`, media_kit's `TextureHW`). The
/// zero-copy `videotoolbox` interop hands it the decoder's CVPixelBuffer, and
/// for 10-bit streams (every iPhone camera HEVC/Dolby Vision clip is 10-bit
/// Rec.2020 HLG, decoded to `p010`) that 16-bit biplanar buffer is sampled as
/// if it were 8-bit: the chroma plane reads as ~0 and the picture comes out
/// green/magenta with almost no saturation. `videotoolbox-copy` downloads the
/// frame to system memory, and `format=nv12` makes that an 8-bit frame every
/// GLES device samples correctly; mpv's shader still tone-maps HLG/PQ to SDR
/// from the stream's tags. 8-bit SDR keeps the zero-copy path (battery).
///
/// Only the *source* matters, so [pixelformat]/[hwPixelformat] are the
/// `video-params` ones (before `vf`), and the hardware surface's real format
/// (`hw-pixelformat`, e.g. `p010`) wins over `videotoolbox`.
VideoPathPlan planVideoPath({
  required bool isIOS,
  String? pixelformat,
  String? hwPixelformat,
  String? gamma,
  String? primaries,
}) {
  if (!isIOS) return VideoPathPlan.standard;
  final format = (hwPixelformat != null && hwPixelformat.isNotEmpty) ? hwPixelformat : pixelformat;
  final deep = isHighBitDepthFormat(format);
  final hdr = _hdrGammas.contains(gamma?.toLowerCase());
  final wide = primaries?.toLowerCase() == 'bt.2020' && deep;
  if (!deep && !hdr && !wide) return VideoPathPlan.standard;
  return VideoPathPlan(
    hwdec: 'videotoolbox-copy',
    vf: 'format=nv12',
    reason: deep ? 'high-bit-depth' : 'hdr-transfer',
  );
}

/// Applies [planVideoPath] to a live [Player] as each file's params arrive.
/// iOS only; one per player (see [VideoColorGuard.attach]).
class VideoColorGuard {
  VideoColorGuard._(this._player, {required this.isIOS}) {
    _native = _player.platform is NativePlayer ? _player.platform! as NativePlayer : null;
    _subs
      ..add(_player.stream.playlist.listen((_) => unawaited(_reset())))
      ..add(_player.stream.videoParams.listen((p) => unawaited(_onParams(p))));
  }

  static final _guards = Expando<VideoColorGuard>('VideoColorGuard');

  /// Idempotent per [player]. [isIOS] is a seam for tests and the probe.
  static void attach(Player player, {bool? isIOS}) {
    final ios = isIOS ?? Platform.isIOS;
    if (!ios || _guards[player] != null) return;
    if (kMpvHwdecOverride.isNotEmpty) {
      final native = player.platform;
      if (native is NativePlayer) {
        unawaited(native.setProperty('hwdec', kMpvHwdecOverride));
        trace('hwdec override', category: 'media', data: {'hwdec': kMpvHwdecOverride});
      }
      return;
    }
    _guards[player] = VideoColorGuard._(player, isIOS: ios);
  }

  final Player _player;
  final bool isIOS;
  late final NativePlayer? _native;
  final List<StreamSubscription<Object?>> _subs = [];
  bool _forced = false;

  /// A new file starts on the standard path; its own params decide again.
  Future<void> _reset() async {
    final native = _native;
    if (native == null || !_forced) return;
    _forced = false;
    try {
      await native.setProperty('vf', '');
      await native.setProperty('hwdec', VideoPathPlan.standard.hwdec);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'restoring the standard video path');
    }
  }

  Future<void> _onParams(VideoParams p) async {
    final native = _native;
    if (native == null || _forced || p.pixelformat == null) return;
    final plan = planVideoPath(
      isIOS: isIOS,
      pixelformat: p.pixelformat,
      hwPixelformat: p.hwPixelformat,
      gamma: p.gamma,
      primaries: p.primaries,
    );
    trace(
      'video path decided',
      category: 'media',
      data: {
        'hwdec': plan.hwdec,
        'vf': plan.vf,
        'reason': plan.reason,
        'pixfmt': p.pixelformat,
        'hw_pixfmt': p.hwPixelformat,
        'gamma': p.gamma,
        'primaries': p.primaries,
        'matrix': p.colormatrix,
        'rotate': p.rotate,
      },
    );
    if (plan.isStandard) return;
    _forced = true;
    try {
      await native.setProperty('vf', plan.vf);
      await native.setProperty('hwdec', plan.hwdec);
    } catch (e, s) {
      _forced = false;
      reportNonFatal(e, s, during: 'switching to the copy video path');
    }
  }

  void dispose() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
  }
}
