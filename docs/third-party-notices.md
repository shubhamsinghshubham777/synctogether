# Third-party notices

## mpv and FFmpeg (libmpv)

The video player is built on libmpv and FFmpeg, distributed under the
GNU Lesser General Public License (LGPL) v2.1 or later, as unmodified
prebuilt libraries linked dynamically.

- mpv: https://github.com/mpv-player/mpv, https://mpv.io
- FFmpeg: https://ffmpeg.org, source at https://github.com/FFmpeg/FFmpeg
- Apple and Android builds: https://github.com/media-kit/libmpv-darwin-build,
  https://github.com/media-kit/libmpv-android-video-build (build recipes and
  exact source revisions are in those repositories)
- Windows build: https://github.com/zhongfly/mpv-winbuild, release
  `2026-10-11-d94d095814` (mpv commit d94d095814). The exact archive we ship is
  mirrored at
  https://github.com/shubhamsinghshubham777/synctogether/releases/tag/deps-libmpv-win-20261011

Because the libraries are separate shared objects, you can replace them with
your own build of the same version. Also bundled and under their own licenses:
libass, dav1d, FreeType, FriBidi, HarfBuzz, libxml2, Mbed TLS, uchardet.

## ANGLE and libwebrtc (Windows)

Prebuilt, unmodified binaries committed in `third_party/` so builds do not
depend on GitHub being reachable.

- ANGLE (BSD-3-Clause, from Google ANGLE; the repackaging repo has no licence file): https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES,
  `v1.0.1`, used by media_kit's Windows renderer
- libwebrtc (MIT): https://github.com/webrtc-sdk/libwebrtc, release
  `libwebrtc.m150.7871.02`, used by flutter_webrtc, which downloads it itself at build time (nothing of it is committed here)

## media_kit

MIT. https://github.com/media-kit/media-kit. The `media_kit_libs_*_video`
packages are vendored in `third_party/` with only the native-library download
changed.
