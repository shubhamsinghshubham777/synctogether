/// What a bug report says about the film that is playing: container, codecs,
/// colour, tracks and the decode path, so we can tell whether a file's format
/// is truly supported. Pure Dart over plain values: the mpv reads are injected
/// ([MpvRead]) so the rules are testable as a table and a missing property just
/// leaves its line out.
///
/// **The name never travels by default.** Only the extension does. The redacted
/// base name ([mediaFileName]) is exposed separately for the opt-in switch.
library;

import 'redact.dart';

/// Reads one mpv property; null or empty means "not available".
typedef MpvRead = Future<String?> Function(String property);

/// Longest a single value may be, and the most a whole report section set may
/// weigh. The server caps the whole context at 16 KB; media must stay a small part.
const kMediaValueMax = 120;
const kMediaTotalMax = 1800;

/// How long one mpv read may take before its line is simply omitted.
const kMpvReadTimeout = Duration(milliseconds: 400);

final _tail = RegExp(r'[?#].*$');
final _knownMediaExt = RegExp(
  r'\b[^\s/\\\x27"]+\.(mkv|mp4|m4v|mov|avi|wmv|flv|webm|ts|m2ts|mts|mpg|mpeg|ogv|3gp|mp3|m4a|aac|flac|ogg|opus|wav|srt|ass|ssa|vtt|sub|idx|sup)\b',
  caseSensitive: false,
);
final _url = RegExp(r'\b[a-z][a-z0-9+.\-]*://[^\s\x27"]+', caseSensitive: false);

String _lastSegment(String s) {
  final clean = s.replaceAll(_tail, '');
  final i = clean.lastIndexOf(RegExp(r'[\\/]'));
  return i < 0 ? clean : clean.substring(i + 1);
}

/// The lower-case extension of a file name, path or URL (`mkv`), or null when
/// there is none worth sending. Query strings and fragments are ignored, only
/// the last dot of the last segment counts, and anything that is not 1-5 letters
/// or digits is not an extension.
String? mediaExtension(String? nameOrUri) {
  if (nameOrUri == null) return null;
  final seg = _lastSegment(nameOrUri.trim());
  final dot = seg.lastIndexOf('.');
  if (dot <= 0 || dot == seg.length - 1) return null;
  final ext = seg.substring(dot + 1).toLowerCase();
  return RegExp(r'^[a-z0-9]{1,5}$').hasMatch(ext) ? ext : null;
}

/// The base name only (never a path, never a query string or URL token), with
/// emails and long tokens scrubbed. For the opt-in "include the video's file name".
String? mediaFileName(String? nameOrUri) {
  if (nameOrUri == null) return null;
  final seg = redactText(_lastSegment(nameOrUri.trim())).trim();
  if (seg.isEmpty) return null;
  return seg.length > kMediaValueMax ? seg.substring(0, kMediaValueMax) : seg;
}

/// A coarse size band, never the exact size.
String sizeBucket(int bytes) {
  const mib = 1024 * 1024;
  const gib = 1024 * mib;
  if (bytes < 100 * mib) return '<100 MB';
  if (bytes < gib) return '100 MB-1 GB';
  if (bytes < 4 * gib) return '1-4 GB';
  if (bytes < 8 * gib) return '4-8 GB';
  return '>8 GB';
}

/// Bits per channel from an mpv/ffmpeg pixel format (`yuv420p10le` -> 10).
int? bitDepthOf(String? pixelFormat) {
  if (pixelFormat == null || pixelFormat.isEmpty) return null;
  if (pixelFormat == 'p010') return 10;
  if (pixelFormat == 'p016') return 16;
  final m = RegExp(r'(9|10|12|14|16)(?:le|be)$').firstMatch(pixelFormat);
  return m == null ? 8 : int.parse(m[1]!);
}

/// An mpv log line with URLs and file names taken out. Paths shrink to their
/// base name first (redactText), then any media or subtitle base name loses its
/// stem and keeps its extension, which is the useful part.
String redactMpvLine(String line) {
  var s = redactText(line);
  s = s.replaceAll(_url, '<url>');
  s = s.replaceAllMapped(_knownMediaExt, (m) => '<file>.${m[1]!.toLowerCase()}');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return s.length > kMediaValueMax ? s.substring(0, kMediaValueMax) : s;
}

/// The last few warnings and errors from mpv, already redacted.
class MpvLogBuffer {
  MpvLogBuffer({this.capacity = 10});
  final int capacity;
  final List<String> _lines = [];

  List<String> get lines => List.unmodifiable(_lines);

  void add(String level, String text) {
    if (level != 'warn' && level != 'error' && level != 'fatal') return;
    final clean = redactMpvLine(text);
    if (clean.isEmpty) return;
    if (_lines.isNotEmpty && _lines.last == clean) return;
    _lines.add(clean);
    if (_lines.length > capacity) _lines.removeAt(0);
  }
}

/// What the caller knows without asking mpv.
class MediaFacts {
  const MediaFacts({
    required this.mode,
    required this.source,
    this.nameOrUri,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.playing = false,
    this.buffering = false,
    this.subtitleFormats = const [],
    this.externalSubtitles = 0,
    this.audioTrackCount = 0,
    this.uploadState,
  });

  /// `local` or `youtube` (the room's playback mode).
  final String mode;

  /// `local`, `uploaded` (streaming the host's shared copy) or `youtube`.
  final String source;

  /// The raw name or URI: only its extension and, on opt-in, its base name leave.
  final String? nameOrUri;
  final Duration position;
  final Duration duration;
  final bool playing;
  final bool buffering;
  final List<String> subtitleFormats;
  final int externalSubtitles;
  final int audioTrackCount;
  final String? uploadState;
}

/// The section names, in the order a report shows them.
const kMediaSections = ['media', 'video', 'color', 'audio', 'subs', 'decode', 'mpv'];

String _clip(String v) => v.length > kMediaValueMax ? v.substring(0, kMediaValueMax) : v;

/// The part of the report that needs no mpv: it changes with every snapshot.
Map<String, Map<String, String>> liveSections(MediaFacts f) {
  final media = <String, String>{'mode': f.mode, 'source': f.source};
  if (f.mode != 'youtube') {
    final ext = mediaExtension(f.nameOrUri);
    if (ext != null) media['ext'] = ext;
    if (f.uploadState != null && f.uploadState != 'none') media['upload'] = f.uploadState!;
  }
  media['pos_s'] = '${f.position.inSeconds}';
  media['dur_s'] = '${f.duration.inSeconds}';
  media['playing'] = '${f.playing}';
  media['buffering'] = '${f.buffering}';
  final out = {'media': media};
  if (f.mode != 'youtube' && f.subtitleFormats.isNotEmpty) {
    out['subs'] = {
      'tracks': '${f.subtitleFormats.length}',
      'formats': f.subtitleFormats.toSet().join(', '),
      if (f.externalSubtitles > 0) 'external': '${f.externalSubtitles}',
    };
  }
  if (f.mode != 'youtube' && f.audioTrackCount > 0) {
    out['audio'] = {'tracks': '${f.audioTrackCount}'};
  }
  return out;
}

/// Reads what only mpv knows. Every property is read in parallel with its own
/// timeout and a missing one leaves its line out; the whole call never throws.
Future<Map<String, Map<String, String>>> readMpvSections(MpvRead read) async {
  Future<String?> get(String p) async {
    try {
      final v = (await read(p).timeout(kMpvReadTimeout))?.trim();
      return (v == null || v.isEmpty) ? null : v;
    } catch (_) {
      return null;
    }
  }

  final names = const [
    'file-format',
    'file-size',
    'video-format',
    'current-tracks/video/codec-profile',
    'video-params/w',
    'video-params/h',
    'container-fps',
    'estimated-vf-fps',
    'video-params/pixelformat',
    'video-params/rotate',
    'video-bitrate',
    'video-params/primaries',
    'video-params/gamma',
    'video-params/colormatrix',
    'video-params/colorlevels',
    'audio-codec-name',
    'audio-params/hr-channels',
    'audio-params/samplerate',
    'audio-params/format',
    'audio-bitrate',
    'hwdec-current',
    'current-tracks/video/decoder',
    'current-vo',
  ];
  final values = await Future.wait(names.map(get));
  final v = {for (var i = 0; i < names.length; i++) names[i]: values[i]};

  void put(Map<String, String> m, String k, String? val) {
    if (val != null && val.isNotEmpty) m[k] = _clip(val);
  }

  String? kbps(String? bps) {
    final n = double.tryParse(bps ?? '');
    return (n == null || n <= 0) ? null : '${(n / 1000).round()}';
  }

  final media = <String, String>{};
  put(media, 'container', v['file-format']);
  final size = int.tryParse(v['file-size'] ?? '');
  if (size != null && size > 0) media['size'] = sizeBucket(size);

  final video = <String, String>{};
  put(video, 'codec', v['video-format']);
  put(video, 'profile', v['current-tracks/video/codec-profile']);
  final w = v['video-params/w'], h = v['video-params/h'];
  if (w != null && h != null) video['res'] = '${w}x$h';
  final fps = double.tryParse(v['container-fps'] ?? v['estimated-vf-fps'] ?? '');
  if (fps != null && fps > 0) video['fps'] = fps.toStringAsFixed(fps % 1 == 0 ? 0 : 2);
  put(video, 'pix', v['video-params/pixelformat']);
  final bits = bitDepthOf(v['video-params/pixelformat']);
  if (bits != null) video['bits'] = '$bits';
  final rot = int.tryParse(v['video-params/rotate'] ?? '');
  if (rot != null && rot != 0) video['rot'] = '$rot';
  put(video, 'kbps', kbps(v['video-bitrate']));

  final color = <String, String>{};
  put(color, 'primaries', v['video-params/primaries']);
  put(color, 'transfer', v['video-params/gamma']);
  put(color, 'matrix', v['video-params/colormatrix']);
  put(color, 'range', v['video-params/colorlevels']);
  final gamma = v['video-params/gamma'];
  if (gamma != null) {
    color['hdr'] = switch (gamma) {
      'pq' => 'hdr10',
      'hlg' => 'hlg',
      _ => 'no',
    };
  }

  final audio = <String, String>{};
  put(audio, 'codec', v['audio-codec-name']);
  put(audio, 'ch', v['audio-params/hr-channels']);
  put(audio, 'rate', v['audio-params/samplerate']);
  put(audio, 'fmt', v['audio-params/format']);
  put(audio, 'kbps', kbps(v['audio-bitrate']));

  final decode = <String, String>{};
  final hw = v['hwdec-current'];
  if (hw != null) decode['mode'] = (hw == 'no') ? 'software' : 'hardware';
  if (hw != null && hw != 'no') decode['hwdec'] = _clip(hw);
  put(decode, 'decoder', v['current-tracks/video/decoder']);
  put(decode, 'vo', v['current-vo']);

  return {
    for (final e in {
      'media': media,
      'video': video,
      'color': color,
      'audio': audio,
      'decode': decode,
    }.entries)
      if (e.value.isNotEmpty) e.key: e.value,
  };
}

/// Overlays [extra] onto [base] section by section (extra wins per key).
Map<String, Map<String, String>> mergeSections(
  Map<String, Map<String, String>> base,
  Map<String, Map<String, String>> extra,
) {
  final out = {
    for (final e in base.entries) e.key: {...e.value},
  };
  for (final e in extra.entries) {
    (out[e.key] ??= {}).addAll(e.value);
  }
  return out;
}

/// Trims [sections] under [max] characters of values: the mpv log goes first,
/// then whole sections from the end of [kMediaSections], never `media`.
Map<String, Map<String, String>> capSections(
  Map<String, Map<String, String>> sections, {
  int max = kMediaTotalMax,
}) {
  int weight(Map<String, Map<String, String>> s) => s.values.fold(
    0,
    (a, m) => a + m.entries.fold(0, (b, e) => b + e.key.length + e.value.length + 2),
  );
  final out = {
    for (final e in sections.entries) e.key: {...e.value},
  };
  for (final name in kMediaSections.reversed) {
    if (weight(out) <= max) break;
    if (name == 'media') continue;
    out.remove(name);
  }
  return out;
}
