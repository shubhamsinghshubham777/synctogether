import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:synctogether/diagnostics.dart';

/// Largest render texture we ask for - 4K UHD, in either orientation.
const kMaxSurfaceLongSide = 3840, kMaxSurfaceShortSide = 2160;

/// The physical-pixel size of [video] contained in [box] (letterboxed the way
/// `Video` draws it), capped at 4K with the aspect kept, rounded to even.
///
/// This is what makes libass subtitles sharp: mpv draws them into its render
/// texture, and by default that texture is the *video's* size, so a 720p file
/// on a Retina screen rasterises its text at 720p and Flutter stretches it.
/// Sized to the screen, mpv scales the video and draws the text at display
/// resolution. Null while either size is unknown.
({int width, int height})? renderSurfaceSize(Size box, Size video, double devicePixelRatio) {
  if (box.isEmpty || video.isEmpty || !box.isFinite || devicePixelRatio <= 0) return null;
  final fit = math.min(box.width / video.width, box.height / video.height);
  var w = video.width * fit * devicePixelRatio;
  var h = video.height * fit * devicePixelRatio;
  final long = math.max(w, h), short = math.min(w, h);
  final cap = math.min(1.0, math.min(kMaxSurfaceLongSide / long, kMaxSurfaceShortSide / short));
  w *= cap;
  h *= cap;
  int even(double v) => math.max(2, (v / 2).round() * 2);
  return (width: even(w), height: even(h));
}

/// mpv's upscalers beat Flutter's bilinear stretch, which is what a 720p file
/// got before the texture was sized to the screen. spline36 is the sharp,
/// cheap middle ground; ewa_lanczossharp costs too much GPU on laptops.
Future<void> applyVideoQualityOptions(Player player) async {
  final native = player.platform;
  if (native is! NativePlayer || Platform.isAndroid) return;
  const options = {
    'scale': 'spline36',
    'cscale': 'spline36',
    'dscale': 'mitchell',
    'correct-downscaling': 'yes',
  };
  for (final e in options.entries) {
    try {
      await native.setProperty(e.key, e.value);
    } catch (e2, s) {
      reportNonFatal(e2, s, during: 'setting video option ${e.key}');
    }
  }
}

/// Wraps the `Video` and keeps [controller]'s render texture at the size it
/// is shown at (see [renderSurfaceSize]). Debounced, so a window drag or a
/// fullscreen transition resizes once it settles; the old frame stretches for
/// that moment. Android is out: media_kit resets its surface to the video's
/// size on every video-params event and `setSize` throws there.
class VideoSurfaceSizer extends StatefulWidget {
  const VideoSurfaceSizer({super.key, required this.controller, required this.child});

  final VideoController controller;
  final Widget child;

  static bool get supported => !Platform.isAndroid;

  @override
  State<VideoSurfaceSizer> createState() => _VideoSurfaceSizerState();
}

class _VideoSurfaceSizerState extends State<VideoSurfaceSizer> {
  final List<StreamSubscription<int?>> _subs = [];
  Timer? _debounce;
  Size _box = Size.zero;
  double _dpr = 1;
  ({int width, int height})? _requested;

  Player get _player => widget.controller.player;

  @override
  void initState() {
    super.initState();
    // A new file can change the aspect ratio without the box changing.
    _subs
      ..add(_player.stream.width.listen((_) => _schedule()))
      ..add(_player.stream.height.listen((_) => _schedule()));
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), _resize);
  }

  Future<void> _resize() async {
    if (!mounted) return;
    final vw = _player.state.width, vh = _player.state.height;
    if (vw == null || vh == null) return;
    final size = renderSurfaceSize(_box, Size(vw.toDouble(), vh.toDouble()), _dpr);
    if (size == null || size == _requested) return;
    final previous = _requested;
    _requested = size;
    try {
      await widget.controller.setSize(width: size.width, height: size.height);
      // A transition, not a tick: resizes are debounced and deduped.
      if (previous == null) {
        trace(
          'video surface sized',
          category: 'media',
          data: {'video': '${vw}x$vh', 'surface': '${size.width}x${size.height}', 'dpr': _dpr},
        );
      }
    } catch (e, s) {
      _requested = previous;
      reportNonFatal(e, s, during: 'sizing the video render surface');
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final box = constraints.biggest;
        if (box != _box || dpr != _dpr) {
          _box = box;
          _dpr = dpr;
          _schedule();
        }
        return widget.child;
      },
    );
  }
}
