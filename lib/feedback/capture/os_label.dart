import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:synctogether/diagnostics.dart';

import 'redact.dart';

/// "iOS 27.0", "Android 16", "macOS 27.0", "Windows 11": what a person would
/// say, for the line a user reads in "See exactly what we send". The raw
/// platform string ("Version 27.0 (Build 24A437)") only goes into the report's
/// context, with the build split out.
class OsLabel {
  const OsLabel(this.label, {this.build});

  final String label;
  final String? build;

  /// [platform] is `Platform.operatingSystem`, [raw] the first line of
  /// `Platform.operatingSystemVersion`. Android's raw string is a kernel banner,
  /// so its release ("16") comes from [androidRelease].
  static OsLabel of(String platform, String raw, {String? androidRelease}) {
    final first = raw.split('\n').first.trim();
    final build = RegExp(r'Build\s+([A-Za-z0-9.]+)').firstMatch(first)?.group(1);
    switch (platform) {
      case 'ios':
        return OsLabel(_named('iOS', _version(first)), build: build);
      case 'macos':
        return OsLabel(_named('macOS', _version(first)), build: build);
      case 'android':
        final release = androidRelease?.trim();
        return OsLabel(release == null || release.isEmpty ? 'Android' : 'Android $release');
      case 'windows':
        final number = int.tryParse(
          build ?? RegExp(r'\b\d+\.\d+\.(\d+)\b').firstMatch(first)?.group(1) ?? '',
        );
        // Windows 11 is NT 10.0 from build 22000.
        final name = number == null ? 'Windows' : (number >= 22000 ? 'Windows 11' : 'Windows 10');
        return OsLabel(name, build: number?.toString());
      default:
        return OsLabel(first.isEmpty ? platform : '$platform $first');
    }
  }

  static String? _version(String raw) => RegExp(r'(\d+(?:\.\d+)+)').firstMatch(raw)?.group(1);

  static String _named(String name, String? version) => version == null ? name : '$name $version';

  /// Replaced by tests; the real lookup asks the platform for the Android release.
  @visibleForTesting
  static Future<String?> Function() androidReleaseLookup = _androidRelease;

  static Future<String?> _androidRelease() async =>
      (await DeviceInfoPlugin().androidInfo).version.release;

  /// The label for this device. Fails soft: Android without a release just says "Android".
  static Future<OsLabel> read(String platform, String raw) async {
    String? release;
    if (platform == 'android') {
      try {
        release = await androidReleaseLookup();
      } catch (e, s) {
        reportNonFatal(e, s, during: 'reading the Android release');
      }
    }
    final label = of(platform, raw, androidRelease: release);
    return OsLabel(redactText(label.label), build: label.build);
  }
}
