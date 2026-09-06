import 'dart:math' as math;

final _versionInFeed = RegExp(
  r'sparkle:(?:shortVersionString|version)\s*=\s*"([^"]*)"'
  r'|<sparkle:(?:shortVersionString|version)\s*>([^<]*)<',
);

final _itemRegex = RegExp(r'<item>(.*?)</item>', dotAll: true);
final _enclosureRegex = RegExp(r'<enclosure\s+([^>]*)/?>', dotAll: true);
final _urlRegex = RegExp(r'url\s*=\s*"([^"]*)"');
final _osRegex = RegExp(r'sparkle:os\s*=\s*"([^"]*)"');
final _lengthRegex = RegExp(r'length\s*=\s*"([^"]*)"');

class AppcastRelease {
  final String version;
  final String enclosureUrl;
  final String? os;
  final int? length;

  const AppcastRelease({required this.version, required this.enclosureUrl, this.os, this.length});
}

List<AppcastRelease> parseAppcastReleases(String appcastXml) {
  final releases = <AppcastRelease>[];
  for (final itemMatch in _itemRegex.allMatches(appcastXml)) {
    final itemContent = itemMatch.group(1) ?? '';

    String? version;
    final vMatch = _versionInFeed.firstMatch(itemContent);
    if (vMatch != null) {
      version = (vMatch.group(1) ?? vMatch.group(2) ?? '').trim();
    }

    final encMatch = _enclosureRegex.firstMatch(itemContent);
    if (encMatch == null) continue;

    final encAttrs = encMatch.group(1) ?? '';
    final urlMatch = _urlRegex.firstMatch(encAttrs);
    final url = urlMatch?.group(1)?.trim();
    if (url == null || url.isEmpty) continue;

    final osMatch = _osRegex.firstMatch(encAttrs);
    final os = osMatch?.group(1)?.trim().toLowerCase();

    final lenMatch = _lengthRegex.firstMatch(encAttrs);
    final length = int.tryParse(lenMatch?.group(1)?.trim() ?? '');

    if (version != null && version.isNotEmpty) {
      releases.add(AppcastRelease(version: version, enclosureUrl: url, os: os, length: length));
    }
  }
  return releases;
}

AppcastRelease? newestReleaseForPlatform(String appcastXml, String platformOs) {
  final target = platformOs.toLowerCase();
  final releases = parseAppcastReleases(appcastXml);
  AppcastRelease? best;
  for (final release in releases) {
    if (release.os != null && release.os != target) continue;
    if (best == null || compareVersions(release.version, best.version) > 0) {
      best = release;
    }
  }
  return best;
}

String? newestVersionIn(String appcastXml) {
  String? best;
  for (final match in _versionInFeed.allMatches(appcastXml)) {
    final raw = (match.group(1) ?? match.group(2) ?? '').trim();
    if (raw.isEmpty) continue;
    if (best == null || compareVersions(raw, best) > 0) best = raw;
  }
  return best;
}

int compareVersions(String a, String b) {
  final left = _segments(a);
  final right = _segments(b);
  for (var i = 0; i < math.max(left.length, right.length); i++) {
    final x = i < left.length ? left[i] : 0;
    final y = i < right.length ? right[i] : 0;
    if (x != y) return x < y ? -1 : 1;
  }
  return 0;
}

List<int> _segments(String version) => version
    .trim()
    .split('+')
    .first
    .split('-')
    .first
    .split('.')
    .map((segment) => int.tryParse(segment.trim()) ?? 0)
    .toList();
