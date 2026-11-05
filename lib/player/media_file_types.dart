import 'package:file_selector/file_selector.dart';

/// Containers our full-codec libmpv plays. The one list the picker's filters
/// and [looksLikeVideoFile] both read, so they cannot disagree.
const kVideoExtensions = <String>[
  'mp4',
  'm4v',
  'mkv',
  'mov',
  'webm',
  'avi',
  'wmv',
  'flv',
  'ts',
  'm2ts',
  'mts',
  'mpg',
  'mpeg',
  '3gp',
  'ogv',
  'vob',
  'divx',
  'f4v',
  'asf',
];

/// The video filter for every local-file picker. Each platform honours a
/// different field and ignores the rest: desktop reads [extensions], Android
/// [mimeTypes], and iOS only [uniformTypeIdentifiers] (the document picker has
/// no notion of extensions, which is why `['mp4', 'mkv']` let a PDF through).
/// `org.matroska.*` are declared in `ios/Runner/Info.plist`; an identifier the
/// app does not know is dropped by the plugin, so mkv/webm would grey out.
const kVideoTypeGroup = XTypeGroup(
  label: 'Videos',
  extensions: kVideoExtensions,
  mimeTypes: ['video/*'],
  uniformTypeIdentifiers: [
    'public.movie',
    'public.video',
    'public.mpeg-4',
    'com.apple.quicktime-movie',
    'public.avi',
    'org.matroska.mkv',
    'org.matroska.webm',
  ],
);

/// Friendly refusal for a pick that is plainly not a video.
const kNotAVideoMessage =
    "Hmm, that doesn't look like a video. Pick an MP4, MKV, MOV or WebM file.";

/// Whether [name] could be a video. The pickers' filters are advisory (iOS
/// "Browse" and some Files providers show everything), so a pick is checked
/// here before the player is asked to open it. A name with no extension is
/// given the benefit of the doubt - the player will try it.
bool looksLikeVideoFile(String name) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return true;
  return kVideoExtensions.contains(name.substring(dot + 1).toLowerCase());
}
