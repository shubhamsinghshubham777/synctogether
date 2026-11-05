import 'package:file_selector/file_selector.dart';

// The single source of truth for "which files may the user pick as a video".
//
// Every platform's picker honours a DIFFERENT field of `XTypeGroup` and ignores
// the rest (docs/video-format-parity.md section 1), so the three lists below
// are derived side by side here and must never be edited anywhere else:
//
//   Windows / macOS   [kVideoExtensions]   (`IFileDialog` / `NSOpenPanel`)
//   iOS               [kVideoUtis]         (`UIDocumentPickerViewController`;
//                                           an identifier the app does not know
//                                           is silently dropped by the plugin)
//   Android           [kVideoMimeTypes]    (SAF `ACTION_OPEN_DOCUMENT`)
//
// The filter is ADVISORY. Providers mislabel files, iOS "Browse" shows
// everything and a user can always rename a file, so a pick is only refused by
// [looksLikeNonMedia] (a deny-list of things that are plainly not video) and
// otherwise handed to mpv, whose own open failure is the real arbiter. Never
// reintroduce an allow-list: it rejected `.mxf` (our own contract clip) and
// every container nobody remembered to add.
//
// iOS UTIs: `ios/Runner/Info.plist` declares (UTImportedTypeDeclarations) one
// type per extension that has no system UTI on a clean iPhone; a drift test
// (`test/player/media_file_types_test.dart`) fails if the two disagree.
// Nothing needs UTExportedTypeDeclarations - we own none of these formats.

/// Every container the full-codec libmpv plays, lower case, no dot. Desktop
/// pickers filter on exactly this list.
const kVideoExtensions = <String>[
  'mp4',
  'm4v',
  'mov',
  'mkv',
  'mka',
  'webm',
  'avi',
  'wmv',
  'asf',
  'flv',
  'f4v',
  'ts',
  'm2ts',
  'mts',
  'm2v',
  'mpg',
  'mpeg',
  'mpe',
  'vob',
  'dat',
  '3gp',
  '3g2',
  'ogv',
  'ogm',
  'divx',
  'xvid',
  'rm',
  'rmvb',
  'mxf',
  'nut',
  'y4m',
  'dv',
  'wtv',
  'evo',
  'mod',
  'trp',
  'tp',
];

/// iOS uniform type identifiers. The system ones cover everything that
/// conforms to `public.movie` (mp4, mov, m4v, avi, wmv, flv, ts, mpg, 3gp, ogv,
/// rm, mxf, dv...); the explicit entries are the ones that do NOT conform
/// (`asf`) or that a clean iPhone resolves to a dynamic type - those are the
/// `app.synctogether.video.*` / `org.matroska.*` types imported in Info.plist.
const kVideoUtis = <String>[
  'public.movie',
  'public.video',
  'public.audiovisual-content',
  'public.mpeg',
  'public.mpeg-4',
  'com.apple.quicktime-movie',
  'public.avi',
  'public.mpeg-2-transport-stream',
  'public.avchd-mpeg-2-transport-stream',
  'com.microsoft.windows-media-wmv',
  'com.microsoft.advanced-systems-format',
  'com.adobe.flash.video',
  'org.matroska.mkv',
  'org.matroska.webm',
  'org.matroska.mka',
  ...kImportedVideoUtis,
];

/// The identifiers `ios/Runner/Info.plist` imports (besides `org.matroska.*`,
/// which [kVideoUtis] lists by hand). One per extension with no reliable system
/// type; each conforms to `public.movie` in the plist.
const kImportedVideoUtis = <String>[
  'app.synctogether.video.vob',
  'app.synctogether.video.divx',
  'app.synctogether.video.realmedia',
  'app.synctogether.video.mxf',
  'app.synctogether.video.ogm',
  'app.synctogether.video.nut',
  'app.synctogether.video.wtv',
  'app.synctogether.video.evo',
  'app.synctogether.video.y4m',
  'app.synctogether.video.mod',
  'app.synctogether.video.mpegts',
  'app.synctogether.video.dat',
];

/// Android MIME types for the SAF picker. `video/*` is what well-behaved
/// providers report; the rest are the labels Drive, Downloads and MTP
/// providers actually use for Matroska, MXF and RealMedia, and
/// `application/octet-stream` is the catch-all for providers that label
/// nothing (the deny-list filters junk afterwards). With more than one type
/// `saf_util` sends `*/*` plus `EXTRA_MIME_TYPES`.
const kVideoMimeTypes = <String>[
  'video/*',
  'application/x-matroska',
  'application/mxf',
  'application/vnd.rn-realmedia',
  'application/vnd.rn-realmedia-vbr',
  'application/octet-stream',
];

/// The video filter for every local-file picker.
const kVideoTypeGroup = XTypeGroup(
  label: 'Videos',
  extensions: kVideoExtensions,
  mimeTypes: kVideoMimeTypes,
  uniformTypeIdentifiers: kVideoUtis,
);

/// An empty group renders `*.*` on Windows ("All files"). macOS flattens groups
/// (the Videos group still restricts it), iOS/Android read only their own
/// fields, so this is a Windows-only escape hatch for a rare container.
const kAllFilesTypeGroup = XTypeGroup(label: 'All files');

/// `[Videos, All files]` for `FastFilePicker.pickFile(acceptedTypeGroups:)`.
const kVideoPickerGroups = <XTypeGroup>[kVideoTypeGroup, kAllFilesTypeGroup];

/// Friendly refusal, shown both for a deny-listed pick and when mpv cannot open
/// what was picked (the one line, so the two cases read alike).
const kNotAVideoMessage =
    "Hmm, that file won't open here. It might not be a video, or this format isn't supported.";

/// Extensions that are plainly not video. Audio is deliberately absent (mpv
/// plays it). Compared lower case against the text after the LAST dot, so
/// `movie.mp4.zip` is refused and `movie.final.mkv` is not.
const kNonMediaExtensions = <String>{
  // documents
  'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'odt', 'ods', 'odp', 'rtf',
  'pages', 'numbers', 'key', 'epub', 'mobi',
  // text and data
  'txt', 'md', 'csv', 'json', 'xml', 'html', 'htm', 'log', 'yaml', 'yml', 'ini',
  // images
  'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif', 'tif', 'tiff', 'svg',
  'ico', 'avif', 'raw', 'dng', 'psd',
  // archives and disk images
  'zip', 'rar', '7z', 'tar', 'gz', 'tgz', 'bz2', 'xz', 'zst', 'dmg',
  // programs and packages
  'apk', 'aab', 'ipa', 'exe', 'msi', 'pkg', 'deb', 'rpm', 'app', 'bat', 'sh', 'dll',
  'so', 'dylib', 'jar',
  // standalone subtitle files (picked through the subtitle picker instead)
  'srt', 'vtt', 'ass', 'ssa', 'sub', 'sup', 'smi', 'idx',
};

/// The lower-case text after the last dot of [name]'s final path segment, or
/// null when there is none (`movie`, `.hidden`, `trailing.`).
String? fileExtensionOf(String name) {
  final base = name.split(RegExp(r'[/\\]')).last;
  final dot = base.lastIndexOf('.');
  if (dot <= 0 || dot == base.length - 1) return null;
  return base.substring(dot + 1).toLowerCase();
}

/// Whether [name] is plainly not media (see [kNonMediaExtensions]). This is the
/// ONLY gate in front of the player: unknown and missing extensions pass, and
/// mpv's open failure is the real check.
bool looksLikeNonMedia(String name) {
  final ext = fileExtensionOf(name);
  return ext != null && kNonMediaExtensions.contains(ext);
}

/// Whether [name] carries a container extension we know plays. Informational
/// only (badges, sort order); it must never be used to REFUSE a file.
bool hasKnownVideoExtension(String name) {
  final ext = fileExtensionOf(name);
  return ext != null && kVideoExtensions.contains(ext);
}

/// Compatibility name for call sites written against the old allow-list. It is
/// now the inverse of [looksLikeNonMedia]; new code should call that directly.
bool looksLikeVideoFile(String name) => !looksLikeNonMedia(name);
