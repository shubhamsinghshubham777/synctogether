import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/feedback/capture/os_label.dart';

void main() {
  test('iOS and macOS read like a person says them, with the build set aside', () {
    final ios = OsLabel.of('ios', 'Version 27.0 (Build 24A437)');
    expect(ios.label, 'iOS 27.0');
    expect(ios.build, '24A437');
    final mac = OsLabel.of('macos', 'Version 27.0 (Build 26A428)');
    expect(mac.label, 'macOS 27.0');
    expect(mac.build, '26A428');
  });

  test('Android says its release, since the raw string is a kernel banner', () {
    expect(
      OsLabel.of('android', '6.1.99-android14 #1 SMP', androidRelease: '16').label,
      'Android 16',
    );
    expect(OsLabel.of('android', '6.1.99').label, 'Android');
    expect(OsLabel.of('android', '6.1.99', androidRelease: '  ').label, 'Android');
  });

  test('Windows 11 starts at build 22000', () {
    expect(OsLabel.of('windows', '"Windows 10 Pro" 10.0 (Build 26100)').label, 'Windows 11');
    expect(OsLabel.of('windows', '"Windows 10 Pro" 10.0 (Build 19045)').label, 'Windows 10');
    expect(OsLabel.of('windows', 'Microsoft Windows 10.0.22631').label, 'Windows 11');
    expect(OsLabel.of('windows', 'something odd').label, 'Windows');
  });

  test('an unknown platform keeps its raw first line', () {
    expect(OsLabel.of('linux', 'Ubuntu 24.04\nmore').label, 'linux Ubuntu 24.04');
    expect(OsLabel.of('fuchsia', '').label, 'fuchsia');
  });

  test('a failing Android lookup still gives a label and does not throw', () async {
    OsLabel.androidReleaseLookup = () async => throw StateError('no plugin');
    expect((await OsLabel.read('android', 'x')).label, 'Android');
    OsLabel.androidReleaseLookup = () async => '15';
    expect((await OsLabel.read('android', 'x')).label, 'Android 15');
  });
}
