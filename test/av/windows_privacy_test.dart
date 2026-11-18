import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/av/system_permissions.dart';
import 'package:synctogether/av/windows_privacy.dart';

/// What `reg query <key> /v Value` prints for one value, and its exit code.
ProcessResult _hit(String data) => ProcessResult(
  0,
  0,
  '\r\nHKEY_CURRENT_USER\\Software\\...\\microphone\r\n    Value    REG_SZ    $data\r\n\r\n',
  '',
);

ProcessResult get _miss => ProcessResult(0, 1, '', 'ERROR: The system was unable to find the key.');

RegRunner _fake({String? global, String? desktop}) => (args) async {
  final key = args[1];
  final data = key.endsWith('NonPackaged') ? desktop : global;
  return data == null ? _miss : _hit(data);
};

void main() {
  test('both switches on is granted', () async {
    expect(
      await windowsPrivacyStatus(
        PermissionKind.mic,
        run: _fake(global: 'Allow', desktop: 'Allow'),
      ),
      PermissionState.granted,
    );
  });

  test('"Let desktop apps access your microphone" off is blocked', () async {
    expect(
      await windowsPrivacyStatus(
        PermissionKind.mic,
        run: _fake(global: 'Allow', desktop: 'Deny'),
      ),
      PermissionState.blocked,
    );
  });

  test('the device-wide switch off is blocked, for the camera too', () async {
    expect(
      await windowsPrivacyStatus(PermissionKind.camera, run: _fake(global: 'Deny')),
      PermissionState.blocked,
    );
  });

  test('asks for the right capability key', () async {
    final keys = <String>[];
    await windowsPrivacyStatus(
      PermissionKind.camera,
      run: (args) async {
        keys.add(args[1]);
        return _miss;
      },
    );
    expect(keys.first, endsWith(r'ConsentStore\webcam'));
    expect(keys.last, endsWith(r'ConsentStore\webcam\NonPackaged'));
  });

  test('a machine that will not say is not told it is blocked', () async {
    expect(await windowsPrivacyStatus(PermissionKind.mic, run: _fake()), PermissionState.unknown);
    expect(
      await windowsPrivacyStatus(
        PermissionKind.mic,
        run: (_) async => throw const ProcessException('reg', []),
      ),
      PermissionState.unknown,
    );
  });
}
