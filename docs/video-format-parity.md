# Video format parity: desktop vs mobile

## Status (updated 2026-11-06, `main` at e8b7963 and later)

The audit below describes the tree *before* the work; this table is where the gaps stand now.
Everything marked **built** compiles and passes the Dart suite; none of the device-only parts
have run on real hardware yet.

| # | Gap | State |
|---|---|---|
| 1 | Android picker had no path (staged upload dead, no Recent, no R2 share) | **Built**: `MediaAccess.kt` persistable grant, ranged-read uploads from `content://`, `LocalMediaStore` and `RecentVideos` carry the reference. Needs a real-device check (Drive, Downloads, restart). |
| 2 | Gate matched the exact filename | **Built**: same title / duration within 1.5 s / "Same movie" confirmation (`gateMatchOf`). |
| 3 | iOS security scope and iCloud-evicted files | **Built**: scope held for the session, bookmarks persisted, iCloud download requested. Needs a real-device check. |
| 4 | Allow-list rejected odd containers | **Done**: deny-list of clearly-non-media types; mpv's open failure is the real check. |
| 5 | iOS UTI and Android MIME coverage | **Done**: one source of truth in `lib/player/media_file_types.dart`; drift test against `Info.plist`; 15 imported iOS types. |
| 6 | Restart persistence on iOS | **Built** (bookmarks). macOS Store sandbox still falls back to "Find your copy". |
| 7 | Real-device soak (4K HEVC/AV1/DV/ProRes, hardware decode, thermals) | **Open**: needs devices. |
| 8 | Android soft subtitles cannot track the render surface | Accepted. |
| 9 | FFV1-in-Matroska on mpv 0.36 | Accepted gap. |

Audit of 2026-11-05 against `main` at 8d413d4 plus the uncommitted working tree
(`lib/player/media_file_types.dart`). Every claim is tagged **[ran]** (executed
here), **[read]** (plugin/app source or binary strings) or **[inferred]**.

## Verdict

- **Playback parity is already real.** All four platforms ship a full-decoder
  LGPL FFmpeg (all decoders, demuxers, parsers, libdav1d, libass). The codec
  probe passes every clip on Android and iOS except the documented FFV1-in-MKV
  gap. The mobile apps do **not** lack decoders desktop has.
- **The gaps are in picking and file access.** The picker's accepted types differ
  per OS, Android hands back a `content://` URI with **no path** (which silently
  disables four features), iOS never starts security-scoped access, and the gate
  matches on exact filename, which phones derive differently.

## 1. What each OS lets the user pick (current tree) [read]

`FastFilePicker.pickFile` ignores most of `XTypeGroup` on every OS; each
platform reads exactly one field:

| Platform | Backend | Field honoured | Effect now (`kVideoTypeGroup`) |
|---|---|---|---|
| Windows | `file_selector_windows` (`IFileDialog`) | `extensions` only | One "Videos" filter `*.mp4;*.m4v;...` (19 extensions). No "All files" entry. MIME/UTIs ignored. |
| macOS | `macos_file_picker` (`NSOpenPanel`) | `allowedContentTypes` (UTIs) then `allowedFileTypes` (extensions); the second assignment overrides the first | The extension list decides; other files greyed out. |
| iOS | `ios_document_picker` (`UIDocumentPickerViewController(forOpeningContentTypes:)`) | UTIs only. Unknown identifiers are dropped (`compactMap { UTType($0) }`). No UTIs = `UTType.data` (everything) | `public.movie`, `public.video`, `public.mpeg-4`, quicktime, avi, plus imported `org.matroska.mkv/webm` (Info.plist, uncommitted). |
| Android | `saf_util` `ACTION_OPEN_DOCUMENT` | `mimeTypes` only; a single type becomes `intent.type`, so `video/*` | Only files whose provider reports a `video/*` MIME. |

History: before the shared group the lobby picker used
`extensions: ['mp4','mkv']`. Desktop honoured that (so desktop really was
mp4/mkv only) while iOS (no UTIs = everything) and Android (no MIME = `*/*`)
could pick anything, PDFs included. Behaviour was inverted from what is wanted.

Remaining picker problems:

1. **Allow-list rejects legitimate files.** `looksLikeVideoFile` fails any
   extension not in the 19. `mxf` is missing, so our own contract clip
   `dnxhd_pcm.mxf` would be refused. Also missing: `rm`, `rmvb`, `m2v`, `mka`,
   `wtv`, `nut`, `y4m`, `ogm`, `dv`, `mod`, `evo`, `trp`, `tp`, `dat`.
2. **iOS UTI coverage is partial.** On macOS 27 (queried with `UTType`, as a
   proxy for iOS) `asf` does not conform to `public.movie`, and mkv/vob/divx
   resolve to a third-party app's UTI (`io.iina.*`) that a clean iPhone lacks.
   Files whose UTI conforms to nothing in the list stay greyed out.
3. **Android MIME hiding.** `mxf` (`application/mxf`), `rm/rmvb`, and some
   `.ts`/`.mkv` served as `application/octet-stream` or
   `application/x-matroska` by Drive and Downloads providers would not match
   `video/*` [inferred from provider behaviour].
4. **No path to "all types"** on desktop: Windows and macOS only ever show the
   one filter.
5. Subtitle picker: extensions `srt vtt ass ssa sub`; mobile ignores them (no
   UTIs/MIME), so it shows everything. `sup` (external PGS) and `smi` are not
   offered on desktop.

## 2. Playback parity

### Builds [read]

| | macOS | iOS | Android | Windows |
|---|---|---|---|---|
| mpv / FFmpeg | 0.36.0 / 6.0 | 0.36.0 / 6.0 | 0.36.0-549 (78d4374) / 6.0 | 0.41.0-1127 / git N-127367 |
| Build | `--enable-decoders --enable-demuxers --enable-parsers --enable-hwaccels --enable-protocols --enable-libdav1d --enable-videotoolbox --enable-audiotoolbox --enable-mbedtls`, LGPL | identical (same v0.7.3 `video-full` release) | one `libmpv.so`; 515 `ff_*_decoder` symbols, libdav1d, MediaCodec wrappers, libass + freetype + harfbuzz + fribidi present | not re-inspected; docs say full LGPL |
| HW decode | VideoToolbox (`hwdec=auto`) | VideoToolbox (`auto`) | MediaCodec: `auto-safe`, restricted by media_kit to `h264,hevc,mpeg4,mpeg2video,vp8,vp9,av1`; **forced off on emulators** | D3D11 (untested, the VM had no GPU) |
| Subtitles | libass | libass | libass, needs bundled `subfont.ttf` | libass |

Source: the cached v0.7.3 xcframeworks and the downloaded `full-arm64-v8a.jar`.
Apple's `--disable-decoder=h264` is followed by `--enable-decoder=h264`, so
H.264 software decode exists.

### Codec probe [ran]

`tool/codec_samples.sh` (19 contract clips plus the known gap) plus 10 extras I
added: AV1/Opus MKV, FLV, MPEG-1 `.mpg`, `.m2ts`, H.263 `.3gp`, MSMPEG4/AC3
AVI, a 3840x2160 HDR10 HEVC MKV, and MKV/MP4 with SRT, ASS and mov_text
tracks. 30 clips, `tool/codec_probe` built from the current tree.

| Platform | Result | Caveat |
|---|---|---|
| Android arm64 emulator, API 37, `PROBE_VO=null`, mpv 0.36.0-549 / FFmpeg n6.0 | **29/30 PASS**; only `known_gap_ffv1.mkv` fails (expected) | Software decode (`hwdec=no`): MediaCodec untested. Decode only, no presentation. |
| iOS 27 simulator (iPhone 12), `PROBE_VO=null`, mpv 0.36.0 / FFmpeg 6.0 | **29/30 clips demux, decode video and advance playback**; only the known gap fails. The probe marks all 30 FAIL because the simulator has no audio device (`Could not open/initialize audio device`) | Audio decode unverified here. `docs/codec-support.md` records 19/19 with audio on a real iPhone 12 (2026-10-12). Software decode. |
| macOS, Windows | not re-run | Per `docs/codec-support.md`: macOS real playback; Windows 21/21 incl. the FFV1 gap, in an x64-on-ARM VM, software only |

The probe opens plain paths. It does **not** exercise Android `content://`
(media_kit turns it into `fd://N`) nor iOS security-scoped URLs.

### Matrix

| Item | macOS | iOS | Android | Windows | Basis |
|---|---|---|---|---|---|
| MP4/MOV/M4V, MKV, WebM, AVI, WMV, FLV, TS/M2TS, MPG, 3GP, MXF | yes | yes | yes | yes | [ran] mobile, docs desktop |
| FFV1 in Matroska | no | no | no | **yes** | known gap, mpv 0.36 demuxer |
| H.264, HEVC 8/10-bit, VP9, AV1 (dav1d), MPEG-1/2/4, WMV, ProRes, DNxHD, Cinepak, JPEG2000, HuffYUV, UtVideo, H.263, FLV1, MSMPEG4 | yes | yes | yes | yes | [ran] Android and iOS sim (video side) |
| AAC, AC-3, E-AC-3, DTS, TrueHD (alone and beside AC-3), FLAC, ALAC, Opus, Vorbis, MP3, WMA, PCM | yes | yes (device, per docs) | yes | yes | [ran] Android; iOS per docs |
| DTS-HD MA, Atmos (E-AC-3 JOC, TrueHD) | decoded as core / PCM; no object audio anywhere | same | same | same | [inferred] |
| SRT/ASS/SSA/WebVTT/mov_text (soft) | yes | yes | yes, but cannot size to the render surface (docs) | yes | tracks demuxed [ran]; rendering [read] |
| PGS/VobSub/DVB (bitmap) | yes | yes | yes | yes | decoders compiled in [read]; no clip made (ffmpeg cannot encode PGS) |
| HDR10 / HLG | tone-mapped by mpv | same | same | same | 4K HDR10 HEVC decodes [ran, software, 1 s only] |
| Dolby Vision | profile 8 plays as HDR10; profile 5 will look wrong | same | MediaCodec may handle it on some devices | as macOS | [inferred], untested |
| 4K / high-bitrate HEVC / AV1 | VideoToolbox | VideoToolbox | MediaCodec for the allow-listed codecs, else software | D3D11 | untested on hardware |

Software-decode risk on phones: anything outside Android's `hwdec-codecs`
(ProRes, DNxHD, VC-1, WMV, FFV1, 10-bit AV1 on older SoCs) and any 4K HEVC
without hardware falls to the CPU; dav1d at 4K is the worst case. The probe's
1 s window says nothing about sustained realtime speed. Needs a real-device soak.

## 3. How a picked file reaches mpv [read]

| | Windows / macOS | iOS | Android |
|---|---|---|---|
| Result | real path | `path` + `file://` url, **opened in place** (`forOpeningContentTypes:` is not a copy), so no multi-GB tmp copy | `uri` only, `path == null` |
| Access | direct | needs `startAccessingSecurityScopedResource` for anything outside the app container; **nothing in `lib/` or `ios/Runner` calls it** (`accessAppleScopedResource` unused). Works inside our own container (probe); unverified on a real device for iCloud or other-app folders | `Media('content://...')` -> media_kit opens a ContentResolver fd and passes `fd://N`. No copy, any size. A provider that serves a pipe (some cloud providers) is not seekable |
| After restart | path valid (macOS Store sandbox: the panel grant lapses; `files.bookmarks.app-scope` is declared but no bookmark is ever created) | scope lapses | URI grant lapses (`saf_util` never calls `takePersistableUriPermission` for files) |
| iCloud-evicted file | n/a | `.name.icloud` placeholder: `File.existsSync` false, mpv cannot open; no download request | n/a (provider streams) |

Consequences on **Android** because `path == null`:

1. Lobby "stage a video to upload" returns silently (`if (path == null) return`).
2. `LocalMediaStore.record` returns early on a null path: no per-room memory, no
   auto-reopen when rejoining.
3. The host's R2 sharing prompt is guarded by `path != null`: Android hosts can
   never share.
4. Sidecar subtitle discovery needs a directory: skipped.
5. `_basename` falls back to the URI's last segment. For Media/Downloads
   providers that is `video:1234` or `msf:123`, not the filename, although
   `FastFilePickerPath.name` carries the real display name and is ignored. That
   name feeds the gate (below).

## 4. Cross-device sync assumptions [read]

- `LocalMediaStore` holds device-local paths only (64 entries, 35-day TTL);
  nothing path-like is shared across devices, which is correct.
- The readiness gate is **exact string equality** of the picked filename
  (`memberSatisfiesGate`: `member.loadedFileName != media.name`), case and
  extension included, with only a soft dismissible warning when durations differ
  by more than 2 s. The same film as `Movie.mkv` on desktop and `Movie.mp4` on a
  phone, or `Movie (1).mkv` after a re-download, holds the room closed until a
  rename. This bites mobile most (provider-mangled names, cloud re-downloads),
  and widening to "all types" widens the container mix.

## 5. Plan

### Shared source of truth (`lib/player/media_file_types.dart`)

One const `kVideoExtensions` list (expanded) and one `kNonMediaExtensions` deny
set; derive every platform field from them in one helper so the fields cannot
drift. Compare lowercase.

| Field | Value |
|---|---|
| `extensions` (Windows, macOS) | mp4 m4v mov mkv mka webm avi wmv asf flv f4v ts m2ts mts m2v mpg mpeg mpe vob dat 3gp 3g2 ogv ogm divx xvid rm rmvb mxf nut y4m dv wtv evo mod trp tp |
| `uniformTypeIdentifiers` (iOS) | `public.movie`, `public.video`, `public.audiovisual-content`, `public.mpeg`, `public.mpeg-4`, `com.apple.quicktime-movie`, `public.avi`, `public.mpeg-2-transport-stream`, `public.avchd-mpeg-2-transport-stream`, `com.microsoft.windows-media-wmv`, `com.microsoft.advanced-systems-format`, `com.adobe.flash.video`, plus imported `org.matroska.mkv`, `org.matroska.webm`, `org.matroska.mka`, and one imported type (conforming to `public.movie`) for each remaining extension with no system UTI (vob, divx, rm/rmvb, mxf, ogm, nut, wtv, evo) in `UTImportedTypeDeclarations` |
| `mimeTypes` (Android) | `video/*`, `application/x-matroska`, `application/mxf`, `application/vnd.rn-realmedia`, `application/vnd.rn-realmedia-vbr`, `application/octet-stream` (catch-all for providers that mislabel; the deny-list filters junk) |

Least-maintenance alternative: pass no UTIs on iOS (everything) and `*/*` on
Android, and let the deny-list decide. That is what mobile did before the
filter, and it is the only way to be sure a rare container is never greyed out.

### Validation: deny-list plus open-failure fallback, not an allow-list

- Replace `looksLikeVideoFile` with `looksLikeNonMedia(name)`: refuse only
  clearly-not-video extensions (pdf, images, office documents, text, archives,
  executables, apk/ipa/dmg, and standalone subtitle files). Audio-only files stay
  allowed (mpv plays them). Everything unknown goes through.
- mpv is the real arbiter. Already present: `Failed to recognize file format`
  handling and the open-throws snackbar. Keep both, with one friendly line
  ("Hmm, that file won't open here. It might not be a video, or this format
  isn't supported.") and keep the unrecognised-format case as a `trace`, not
  `reportNonFatal`.
- Desktop: Windows can offer "Videos" and "All files" as two groups (a group with
  empty `extensions` renders `*.*`). macOS flattens groups, so for "all" it needs
  no filter at all and relies on the deny-list.

### Config changes

- `ios/Runner/Info.plist`: keep the Matroska declarations, extend per the UTI row.
- `AndroidManifest.xml`: nothing (SAF needs no storage permission).
- `third_party/`: none for playback.

### Gaps, ranked

| # | Gap | Effort |
|---|---|---|
| 1 | Android picker has no path: lobby staged upload dead, no Recent/auto-reopen, no R2 share, no sidecar subs. Carry the `uri` through `LocalMediaStore`, take a persistable grant (needs a small Kotlin plugin or fork; `saf_util.pickFiles` does not), read the R2 upload through the ContentResolver fd | L (2-4 days) |
| 2 | Gate matches exact filename. First use `FastFilePickerPath.name` instead of the URI tail (S). Then match on normalised stem plus duration within ~2 s, keeping the soft warning (M; touches `sync_logic` and its tests) | S + M |
| 3 | iOS in-place URLs never use security scope; iCloud-evicted files unreadable. Wrap open in `accessAppleScopedResource`, hold it for the room, request download of placeholders. Verify on a real device | M (1-2 days) |
| 4 | Allow-list rejects odd containers (`.mxf` today). Deny-list plus expanded extensions | S (half day) |
| 5 | iOS UTI and Android MIME coverage (table above) | S |
| 6 | Restart persistence on iOS and macOS Store (bookmarks). Today it falls back to "Find your copy", which works | M |
| 7 | Real-device soak: 4K HEVC/AV1/DV/ProRes on a mid-range Android and an older iPhone: hardware paths, thermals, battery | M (needs devices) |
| 8 | Android: subtitles cannot track the render surface (accepted); emulator cannot present video, so the probe is decode-only | accepted |
| 9 | FFV1-in-Matroska on mpv 0.36: accepted gap. A Windows host sharing one fails on Mac and mobile peers | accepted |

## Not verified

Real-device playback, Android MediaCodec, iOS security-scoped access, the picker
UIs on any OS, Windows (not run, build not opened), audio decode on the iOS
simulator, Dolby Vision colour, sustained 4K speed.
