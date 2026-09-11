import 'package:media_kit/media_kit.dart';
import 'package:synctogether/player/youtube/pt_youtube_controller.dart';

/// Maps common ISO-639-1 (2-letter) and ISO-639-2 (3-letter) language codes
/// to their human-friendly English names.
const Map<String, String> _kIsoLanguageNames = {
  // English & Hindi
  'en': 'English',
  'eng': 'English',
  'hi': 'Hindi',
  'hin': 'Hindi',

  // South Asian languages
  'bn': 'Bengali',
  'ben': 'Bengali',
  'gu': 'Gujarati',
  'guj': 'Gujarati',
  'kn': 'Kannada',
  'kan': 'Kannada',
  'ml': 'Malayalam',
  'mal': 'Malayalam',
  'mr': 'Marathi',
  'mar': 'Marathi',
  'pa': 'Punjabi',
  'pan': 'Punjabi',
  'ta': 'Tamil',
  'tam': 'Tamil',
  'te': 'Telugu',
  'tel': 'Telugu',
  'ur': 'Urdu',
  'urd': 'Urdu',

  // East & Southeast Asian languages
  'ja': 'Japanese',
  'jpn': 'Japanese',
  'ko': 'Korean',
  'kor': 'Korean',
  'zh': 'Chinese',
  'zho': 'Chinese',
  'chi': 'Chinese',
  'vi': 'Vietnamese',
  'vie': 'Vietnamese',
  'th': 'Thai',
  'tha': 'Thai',
  'id': 'Indonesian',
  'ind': 'Indonesian',
  'ms': 'Malay',
  'msa': 'Malay',
  'may': 'Malay',
  'tl': 'Tagalog',
  'fil': 'Tagalog',

  // European & Middle Eastern languages
  'es': 'Spanish',
  'spa': 'Spanish',
  'fr': 'French',
  'fra': 'French',
  'fre': 'French',
  'de': 'German',
  'deu': 'German',
  'ger': 'German',
  'it': 'Italian',
  'ita': 'Italian',
  'pt': 'Portuguese',
  'por': 'Portuguese',
  'ru': 'Russian',
  'rus': 'Russian',
  'ar': 'Arabic',
  'ara': 'Arabic',
  'fa': 'Persian',
  'fas': 'Persian',
  'per': 'Persian',
  'tr': 'Turkish',
  'tur': 'Turkish',
  'nl': 'Dutch',
  'nld': 'Dutch',
  'dut': 'Dutch',
  'pl': 'Polish',
  'pol': 'Polish',
  'sv': 'Swedish',
  'swe': 'Swedish',
  'da': 'Danish',
  'dan': 'Danish',
  'fi': 'Finnish',
  'fin': 'Finnish',
  'no': 'Norwegian',
  'nor': 'Norwegian',
  'el': 'Greek',
  'ell': 'Greek',
  'gre': 'Greek',
  'he': 'Hebrew',
  'heb': 'Hebrew',
  'cs': 'Czech',
  'ces': 'Czech',
  'cze': 'Czech',
  'hu': 'Hungarian',
  'hun': 'Hungarian',
  'ro': 'Romanian',
  'ron': 'Romanian',
  'rum': 'Romanian',
  'uk': 'Ukrainian',
  'ukr': 'Ukrainian',
};

/// Resolves an ISO-639 code or language string to a human-friendly name.
String? resolveLanguageName(String? rawLanguage) {
  if (rawLanguage == null) return null;
  final trimmed = rawLanguage.trim();
  if (trimmed.isEmpty) return null;

  final match = _kIsoLanguageNames[trimmed.toLowerCase()];
  if (match != null) return match;

  // If not in our dictionary, capitalize if it looks like a short code or word.
  if (trimmed.length <= 3) {
    return trimmed.toUpperCase();
  }
  return trimmed[0].toUpperCase() + trimmed.substring(1);
}

/// Returns true if [track] represents the synthetic "auto" or "no" track.
bool isSpecialTrack(dynamic track) {
  if (track is SubtitleTrack) {
    return track.id == 'no' || track.id == 'auto';
  }
  if (track is AudioTrack) {
    return track.id == 'no' || track.id == 'auto';
  }
  if (track is PTYouTubeCaptionTrack) {
    return track.isOff;
  }
  return false;
}

/// Compares two track instances by their underlying ID so selection is reliable.
bool isTrackSelected(dynamic track, dynamic selected) {
  if (selected == null) return false;
  if (track == selected) return true;
  if (track is SubtitleTrack && selected is SubtitleTrack) {
    return track.id == selected.id;
  }
  if (track is AudioTrack && selected is AudioTrack) {
    return track.id == selected.id;
  }
  if (track is PTYouTubeCaptionTrack && selected is PTYouTubeCaptionTrack) {
    if (track.isOff && selected.isOff) return true;
    if (track.isOff != selected.isOff) return false;
    if (track.id == selected.id) return true;
    if (track == selected) return true;
    if (track.languageCode != null && track.languageCode == selected.languageCode) {
      if (track.kind != null && selected.kind != null) {
        return track.kind == selected.kind;
      }
      return true;
    }
    return false;
  }
  return false;
}

/// Produces a human-readable, unambiguous label for a subtitle or audio track.
///
/// Handles:
/// - Synthetic tracks ("Off" for `id == 'no'`, "Auto" for `id == 'auto'`).
/// - ISO-639 translation (`hin` -> "Hindi", `eng` -> "English").
/// - Encoder watermark preservation (`Hindi • ~Anup (Track 1)`).
/// - Deduping if title equals the language name (avoids "English • English").
/// - Track index appending when numeric.
String formatTrackLabel(dynamic track) {
  if (track is SubtitleTrack) {
    if (track.id == 'no') return 'Off';
    if (track.id == 'auto') return 'Auto';

    return _assembleTrackLabel(id: track.id, language: track.language, title: track.title);
  }

  if (track is AudioTrack) {
    if (track.id == 'no') return 'Off';
    if (track.id == 'auto') return 'Auto';

    final channelSuffix = _formatAudioChannels(track);
    return _assembleTrackLabel(
      id: track.id,
      language: track.language,
      title: track.title,
      extraSuffix: channelSuffix,
    );
  }

  if (track is PTYouTubeCaptionTrack) {
    if (track.isOff) return 'Off';
    final langName = resolveLanguageName(track.languageCode) ?? track.languageName;
    final display = track.displayName.trim();
    if (display.isEmpty ||
        display.toLowerCase() == track.languageCode?.toLowerCase() ||
        display == 'Captions') {
      return langName ?? (display.isNotEmpty ? display : track.id);
    }
    if (langName != null && langName.isNotEmpty) {
      if (display.toLowerCase().contains(langName.toLowerCase())) {
        return display;
      }
      return '$langName • $display';
    }
    return display;
  }

  return track?.toString() ?? '';
}

String _assembleTrackLabel({
  required String id,
  required String? language,
  required String? title,
  String? extraSuffix,
}) {
  final langName = resolveLanguageName(language);
  final cleanedTitle = title?.trim().isNotEmpty == true ? title!.trim() : null;

  // Avoid "English • English" if the title simply repeats the language name.
  final showTitle =
      cleanedTitle != null &&
      (langName == null || !cleanedTitle.toLowerCase().contains(langName.toLowerCase()));

  final isNumericId = int.tryParse(id) != null;
  final trackNumStr = isNumericId ? 'Track $id' : null;

  final buffer = StringBuffer();

  if (langName != null) {
    buffer.write(langName);
    if (showTitle) {
      buffer.write(' • $cleanedTitle');
    }
    if (extraSuffix != null && extraSuffix.isNotEmpty) {
      buffer.write(' • $extraSuffix');
    }
    if (trackNumStr != null) {
      buffer.write(' ($trackNumStr)');
    }
  } else if (cleanedTitle != null) {
    buffer.write(cleanedTitle);
    if (extraSuffix != null && extraSuffix.isNotEmpty) {
      buffer.write(' • $extraSuffix');
    }
    if (trackNumStr != null) {
      buffer.write(' ($trackNumStr)');
    }
  } else {
    buffer.write(trackNumStr ?? 'Track $id');
    if (extraSuffix != null && extraSuffix.isNotEmpty) {
      buffer.write(' • $extraSuffix');
    }
  }

  return buffer.toString();
}

String? _formatAudioChannels(AudioTrack track) {
  final channels = track.channels?.trim();
  if (channels != null && channels.isNotEmpty) {
    if (channels.contains('5.1')) return '5.1';
    if (channels.contains('7.1')) return '7.1';
    if (channels.toLowerCase() == 'stereo') return 'Stereo';
    return channels;
  }
  final count = track.channelscount;
  if (count != null) {
    if (count == 1) return 'Mono';
    if (count == 2) return 'Stereo';
    if (count == 6) return '5.1';
    if (count == 8) return '7.1';
  }
  return null;
}
