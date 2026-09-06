import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/updates/appcast.dart';

const _kSampleAppcast = '''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>SyncTogether</title>
    <link>https://github.com/shubhamsinghshubham777/synctogether/releases/latest/download/appcast.xml</link>
    <item>
      <title>Version 1.1.0</title>
      <pubDate>Thu, 01 Aug 2026 12:00:00 +0000</pubDate>
      <sparkle:version>1.1.0</sparkle:version>
      <sparkle:shortVersionString>1.1.0</sparkle:shortVersionString>
      <enclosure url="https://github.com/shubhamsinghshubham777/synctogether/releases/download/v1.1.0/SyncTogether-1.1.0-macOS.dmg"
                 sparkle:os="macos"
                 length="85000000"
                 type="application/octet-stream" />
    </item>
    <item>
      <title>Version 1.2.0</title>
      <pubDate>Sat, 05 Sep 2026 12:00:00 +0000</pubDate>
      <sparkle:version>1.2.0</sparkle:version>
      <sparkle:shortVersionString>1.2.0</sparkle:shortVersionString>
      <enclosure url="https://github.com/shubhamsinghshubham777/synctogether/releases/download/v1.2.0/SyncTogether-1.2.0-macOS.dmg"
                 sparkle:os="macos"
                 length="90000000"
                 type="application/octet-stream" />
    </item>
    <item>
      <title>Version 1.2.0</title>
      <pubDate>Sat, 05 Sep 2026 12:00:00 +0000</pubDate>
      <enclosure url="https://github.com/shubhamsinghshubham777/synctogether/releases/download/v1.2.0/SyncTogether-1.2.0-Windows.exe"
                 sparkle:os="windows"
                 sparkle:version="1.2.0"
                 sparkle:shortVersionString="1.2.0"
                 sparkle:installerArguments="/VERYSILENT /SP- /NORESTARTAPPLICATIONS"
                 length="65000000"
                 type="application/octet-stream" />
    </item>
  </channel>
</rss>''';

void main() {
  group('compareVersions', () {
    test('compares semantic versions accurately', () {
      expect(compareVersions('1.2.0', '1.1.0'), greaterThan(0));
      expect(compareVersions('1.1.0', '1.2.0'), lessThan(0));
      expect(compareVersions('1.2.0', '1.2.0'), equals(0));
      expect(compareVersions('1.2.1', '1.2.0'), greaterThan(0));
      expect(compareVersions('2.0.0', '1.9.9'), greaterThan(0));
      expect(compareVersions('1.2.0+5', '1.2.0'), equals(0));
    });
  });

  group('newestVersionIn', () {
    test('extracts the newest version across all items', () {
      expect(newestVersionIn(_kSampleAppcast), '1.2.0');
    });
  });

  group('parseAppcastReleases', () {
    test('parses all release enclosures with OS and length', () {
      final releases = parseAppcastReleases(_kSampleAppcast);
      expect(releases.length, 3);

      final macosReleases = releases.where((r) => r.os == 'macos').toList();
      expect(macosReleases.length, 2);
      expect(macosReleases[0].version, '1.1.0');
      expect(macosReleases[1].version, '1.2.0');
      expect(macosReleases[1].length, 90000000);

      final windowsReleases = releases.where((r) => r.os == 'windows').toList();
      expect(windowsReleases.length, 1);
      expect(windowsReleases[0].version, '1.2.0');
      expect(windowsReleases[0].enclosureUrl, contains('Windows.exe'));
    });
  });

  group('newestReleaseForPlatform', () {
    test('finds the latest release for Windows', () {
      final release = newestReleaseForPlatform(_kSampleAppcast, 'windows');
      expect(release, isNotNull);
      expect(release!.version, '1.2.0');
      expect(release.os, 'windows');
      expect(release.enclosureUrl, contains('Windows.exe'));
    });

    test('finds the latest release for macOS', () {
      final release = newestReleaseForPlatform(_kSampleAppcast, 'macos');
      expect(release, isNotNull);
      expect(release!.version, '1.2.0');
      expect(release.os, 'macos');
      expect(release.enclosureUrl, contains('macOS.dmg'));
    });
  });
}
