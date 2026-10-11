# Codec support

SyncTogether plays local files with libmpv (via media_kit). media_kit's own
native libs ship a deliberately slim FFmpeg (`--disable-all` plus a whitelist),
which silently dropped TrueHD (Blu-ray remuxes played with no sound), ProRes,
DNxHD, FFV1 and others. Every platform now ships a **full-codec LGPL** build
instead.

## What ships where

| Platform | libmpv | Source | Pinned by |
|---|---|---|---|
| macOS | mpv 0.36.0, FFmpeg 6.0 | `media-kit/libmpv-darwin-build` v0.7.3, `video-full` | sha256 in the vendored `Makefile` |
| iOS | mpv 0.36.0, FFmpeg 6.0 | same release, `ios-universal-video-full` | sha256 in the vendored `Makefile` |
| Android | mpv 78d4374, FFmpeg 6.0 | `media-kit/libmpv-android-video-build` v1.1.11, `full-*.jar` | md5 per ABI in the vendored `build.gradle` |
| Windows | mpv 0.41.0-1127 (d94d095814), FFmpeg git N-127367 | `zhongfly/mpv-winbuild` `mpv-dev-lgpl-x86_64`, **mirrored** | md5 in the vendored `CMakeLists.txt` |

media_kit's packages hardcode the slim download with no switch, so the four
`media_kit_libs_*_video` packages are vendored in `third_party/` and wired in
with `dependency_overrides`. Only the download URL and checksum differ from
upstream 1.x; diff against the pub package to see exactly that.

**Why Windows is on a different mpv.** No full-codec Windows build exists at
mpv 0.36, and building one means pinning every 2023 dependency of a
toolchain that tracks upstream HEAD. The Windows archive is mirrored on our own
release `deps-libmpv-win-20261011` (a pre-release; it must never be marked
"latest", because the self-updater reads `releases/latest`), since upstream
deletes builds after about a month.

## The contract

A clip in `tool/codec_samples.sh` must play (video renders, audio decodes, time
advances, no decoder error) on **every** platform. Covered: H.264, HEVC 10-bit,
VP9, AV1 (decoder only), MPEG-2, MPEG-4, WMV, ProRes, DNxHD, FFV1 (AVI/MOV),
HuffYUV, UtVideo, Cinepak, JPEG 2000; audio AAC, AC-3, E-AC-3, DTS, TrueHD
(alone and beside AC-3), FLAC, ALAC, Opus, Vorbis, MP3, WMA, PCM.

Deliberately **not** included: GPL components (x264/x265 encoders), nonfree
ones (fdk-aac), anything needing external libraries we do not ship, and
encoders and muxers, which playback never uses. Native FFmpeg decoders only.

## Known differences (honest list)

- **FFV1 in Matroska** plays on Windows but not on macOS/iOS/Android: mpv 0.36's
  own Matroska demuxer cannot open it (AVI and MOV work everywhere). Tracked by
  `known_gap_ffv1.mkv`.
- **Windows decodes a few more formats** (its FFmpeg is newer). Extra is not a
  parity break for playback, but a file only Windows can play will fail for
  members elsewhere.
- **Different mpv versions**: defaults differ (0.41 shrank `sub-font-size` 55 to
  38 and needs `sub-border-style` for the subtitle box). Every subtitle option we
  depend on is pinned explicitly in `toMpvProperties`; any new mpv property
  we start relying on must be pinned the same way.
- **Hardware decode differs by platform** (VideoToolbox on Apple, D3D11 on
  Windows, MediaCodec on Android); software fallback is identical.

## Verifying

```bash
tool/codec_samples.sh /tmp/samples                 # needs ffmpeg
fvm flutter run -d <macos|windows|...> -t tool/codec_probe/main.dart \
  --dart-define=PROBE_DIR=/tmp/samples --dart-define=PROBE_OUT=/tmp/out
```

The probe prints PASS/FAIL per clip and writes `codec_probe.json` (with the mpv
and FFmpeg versions it ran against). CI additionally asserts the built macOS
app's `Avcodec` is the full build (`--enable-decoders` in its configure string).
Last runs (2026-10-12), every one 19/19 contract clips plus the one known gap:

| Platform | Build under test | Notes |
|---|---|---|
| macOS (Apple silicon, 27.0) | mpv 0.36.0, FFmpeg 6.0 | real playback |
| iOS (iPhone 12, 27.0) | mpv 0.36.0, FFmpeg 6.0 | real device, real playback; VideoToolbox decodes H.264/HEVC |
| Android (emulator, API 37, arm64) | full jars v1.1.11 | **decode-only** (`PROBE_VO=null`): the emulator's GPU cannot give mpv a GL context, so presentation is untested there |
| Windows | mpv 0.41, FFmpeg git | **not yet re-run** against the mirrored archive; the experiment's results (`docs/experiments/win-libmpv-full.md`) apply |

Mobile has no free-form filesystem, so the probe reads `<documents>/samples`
(Android: the app's external files dir). Push the clips in with
`xcrun devicectl device copy to --device <udid> --domain-type appDataContainer
--domain-identifier app.synctogether --source <samples> --destination
Documents/samples` (iOS; use a **release** build, a debug one cannot launch
standalone) or `adb push` plus `chmod -R a+rwX` (Android), then read
`codec_probe.json` back the same way. On an emulator add
`--dart-define=PROBE_VO=null`.

## Bumping a build

- **Apple/Android**: change the version and checksum in the vendored Makefile /
  `build.gradle`; confirm the release contains `video-full` assets.
- **Windows**: download the new `mpv-dev-lgpl-x86_64-*.7z`, mirror it on a new
  `deps-libmpv-win-<date>` pre-release (`--latest=false`), update the URL and md5
  in the vendored `CMakeLists.txt`, then re-run the probe and the subtitle
  tests: mpv option names and defaults move between versions.

## Licensing

The mpv and FFmpeg binaries are LGPL (no `--enable-gpl`, no nonfree). The
Windows DLL reports `-Dgpl=false`. See [third-party-notices.md](third-party-notices.md)
for the attribution and source links we owe. Decoding patented formats (HEVC,
AAC, TrueHD, DTS) carries patent-licensing questions that vary by jurisdiction;
that is a legal call, not one this document makes.
