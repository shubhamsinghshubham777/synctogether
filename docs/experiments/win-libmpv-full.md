# Experiment: full-codec LGPL libmpv on Windows

Branch `exp/win-libmpv-full`. Go/no-go experiment, not a ship. Run 2026-10-11.

## 1. Verdict

**GO-WITH-CAVEATS.** The swap fixes every codec we tried to fix and breaks nothing in playback. It does change subtitle behaviour: the background box stops working until `sub-border-style=background-box` is also set, and the default text size shrinks about 31%. Several things could not be tested (section 7), mainly because the test VM has no GPU.

## 2. Versions

| | Before | After |
|---|---|---|
| mpv | v0.36.0-403-g652a1dd907 | v0.41.0-1127-gd94d09581 |
| ffmpeg | n6.0 | N-127367-gb5902e69c |
| `libmpv-2.dll` | 29.8 MB (12 MB zipped) | 101.2 MB (40 MB zipped) |
| Runner folder | about 150 MB | 218.6 MB |

- Archive used: `mpv-dev-lgpl-x86_64-20261011-git-d94d095814.7z` (zhongfly/mpv-winbuild). SHA-256 matches the release page (`9241604a...ebde8`); MD5 `0cfad5f90518088dd47bcddf00339092`. The DLL in the built runner is byte-identical to the archive's.
- Licence: the running DLL reports `-Dgpl=false`, and no libx264, libx265, xvid or fdk strings were found. FFmpeg's own configure string was not readable, so "LGPL" rests on that plus the asset name.
- The new DLL looks unstripped (`-Ddebug=true`); stripping might shrink it. Not tried.
- The installer was not built, so there is no installer-size figure.

## 3. Codec matrix

Same probe executable on both sides; only the DLL differs. "OK" means it opened, the video rendered, the audio decoder initialised with no errors, and time advanced.

| File | Before (0.36) | After (0.41) |
|---|---|---|
| H.264 + AAC (control) | OK | OK |
| H.264 + E-AC3 (control) | OK | OK |
| H.264 + DTS (control) | OK | OK |
| HEVC 10-bit | OK | OK |
| AV1 (dav1d) | OK | OK |
| JPEG2000 | OK | OK |
| TrueHD only | video plays, audio silent: `Failed to initialize a decoder for codec 'truehd'` | OK |
| TrueHD + AC3 | silent: mpv auto-picks TrueHD and never falls back to AC3 | plays TrueHD; switching to AC3 and back works |
| ProRes | fails to open: `Failed to initialize a decoder for codec 'prores'` | OK |
| FFV1 | fails: `Failed to initialize a decoder for codec ''` | OK |
| DNxHD in MXF | `Failed to recognize file format` (no MXF demuxer) | OK |

- AV1, HEVC and JPEG2000 already worked on 0.36.
- Seek, scrub burst, pause/resume and audio-track switching passed on both.
- `setSize` at 1280x720, 640x360, 1080p, 4K and 800x450 raised no errors on either build.
- CPU, one run per side: the H.264 controls read 25-30% of one core on 0.41 against 12-24% on 0.36. Could be noise or build flags.
- Not covered: VC-1 (no sample found, no encoder) and PGS (ffmpeg cannot encode it).

## 4. Subtitle options

Measured by screenshotting with libass subtitles before and after each change. Each result comes from a pass where the "re-apply defaults" control read 0 and the subtitle was visibly drawn. The first ASS pass was invalid and is discarded.

| Control | 0.41 result |
|---|---|
| Font size | Works, but see the default-size change below |
| Text colour | Works |
| Outline width and colour | Works through the old `sub-border-*` names, which 0.41 still accepts |
| Shadow | Works with live updates while playing. A paused-frame test gave 0 pixels; traced to a test artifact. |
| **Background box** | **No-op as the app sets it.** `sub-back-color` alone draws no box. Adding `sub-border-style=background-box` brings it back (confirmed on screenshots). |
| Position, bold, italic, blur, letter-spacing, alignment | Work |
| Override embedded styles | Works on the ASS track. Reads 0 on SRT on both versions, which is expected. |

Names that need attention:

- `sub-border-style` is new in 0.41 (choices `outline-and-shadow`, `opaque-box`, `background-box`). The app needs to set it for the box. On 0.36 setting it is silently ignored with no exception, so it is safe on both.
- `sub-outline-*` exist only in 0.41. The old `sub-border-*` still work there.

Defaults that changed:

- `sub-font-size` 55 -> 38. At the same `sub-scale`, text is about 31% smaller.
- `sub-back-color` `#00000000` -> `#AF000000`.
- CLAUDE.md says macOS ships mpv 0.36. With the swap, Windows and macOS would show different default text sizes unless `sub-scale` is compensated.

Tests: `fvm flutter test test/player` passes (74). The full suite ran about 4,730 tests with one failure, `test/ui/no_hardcoded_colors_test.dart`. The only offenders it lists are lines from `pt_theme.dart`, the allowed file, which looks like a Windows path-separator problem in the test rather than anything changed here. Not verified on `main`.

## 5. Other surprises

- The real app's release build (`fvm flutter build windows --release`) launches and stays up for 12 s with no missing-DLL error. The ANGLE download and header/`.lib` steps still worked with the new archive.
- The probe app hung in debug mode at `applyVideoQualityOptions`; the cause was not found. Release builds do not have the problem, so all results are from release builds.

## 6. Exact changes

1. `third_party/media_kit_libs_windows_video/` is a copy of pub 1.0.11 with three lines changed in `windows/CMakeLists.txt`:

   ```
   -set(LIBMPV "mpv-dev-x86_64-20230924-git-652a1dd.7z")
   +set(LIBMPV "mpv-dev-lgpl-x86_64-20261011-git-d94d095814.7z")
   -set(LIBMPV_URL "https://github.com/media-kit/libmpv-win32-video-build/releases/download/2023-09-24/${LIBMPV}")
   +set(LIBMPV_URL "https://github.com/zhongfly/mpv-winbuild/releases/download/2026-10-11-d94d095814/${LIBMPV}")
   -set(LIBMPV_MD5 "a832ef24b3a6ff97cd2560b5b9d04cd8")
   +set(LIBMPV_MD5 "0cfad5f90518088dd47bcddf00339092")
   ```

2. `pubspec.yaml` gets a `dependency_overrides:` entry pointing `media_kit_libs_windows_video` at that folder; `pubspec.lock` changes with it.
3. `tool/exp_probe/main.dart` is a headless probe app, not for shipping. Modes `codec`, `subs`, `misc`, `opts`, `live`, driven by `PROBE_DIR`, `PROBE_OUT` and `PROBE_MODE` environment variables. Build with `fvm flutter build windows --release -t tool/exp_probe/main.dart`.

Test media was generated with ffmpeg 9.0.2 (essentials build): 8 s clips of `testsrc2` plus a sine tone, encoded with `-c:a truehd -strict -2`, `prores_ks`, `ffv1`, `dnxhd` (1080p, 36M), `libx265` 10-bit, `libaom-av1` and `jpeg2000`, plus an MKV carrying one ASS and one SRT track.

## 7. Not tested

- GPU, CPU and 4K: the machine was a Parallels Windows 11 ARM64 VM running emulated x64 with a virtual GPU and no hardware decoding. CPU and 4K stutter numbers mean nothing for real PCs, and no 4K files were generated.
- Audio: nobody listened. "Audio OK" only means the decoder initialised without errors and the clock advanced.
- 403 mid-playback: the re-sign and restore-tracks path is untested (needs a room and an expiring URL).
- Fullscreen and YouTube mode against the new build. The YouTube unit tests pass but do not touch libmpv.
- VC-1, PGS, and the installer build (inno_bundle).
- macOS parity.
- The ASS default-styling pass: its measurement was invalid, so it is covered only by the forced-override pass.
