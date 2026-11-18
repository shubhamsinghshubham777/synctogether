import 'dart:io';

import 'package:flutter/foundation.dart';

import '../diagnostics.dart';
import 'system_permissions.dart' show PermissionKind, PermissionState;

/// Runs `reg.exe`; injectable so the parsing is tested with no Windows.
typedef RegRunner = Future<ProcessResult> Function(List<String> args);

Future<ProcessResult> _reg(List<String> args) => Process.run('reg', args);

const _consent =
    r'HKCU\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore';

/// What Windows' own privacy switches say about the camera or microphone
/// (board 94c H). Windows has no per-app prompt to ask: there is a device-wide
/// switch and "Let desktop apps access your ..." under it, and either one off
/// gives a silent failure unless we explain it. Read from the registry the
/// Settings page writes, with no native code: a failure to read is `unknown`,
/// never a verdict, so a locked-down machine is not told it is blocked by
/// mistake.
Future<PermissionState> windowsPrivacyStatus(PermissionKind kind, {RegRunner? run}) async {
  if (kIsWeb) return PermissionState.unknown;
  final capability = kind == PermissionKind.camera ? 'webcam' : 'microphone';
  final base = '$_consent\\$capability';
  final r = run ?? _reg;
  try {
    final global = await _value(r, base);
    final desktop = await _value(r, '$base\\NonPackaged');
    if (global == 'Deny' || desktop == 'Deny') {
      trace(
        'windows privacy blocks the device',
        category: 'av',
        data: {'kind': capability, 'global': global, 'desktop': desktop},
      );
      return PermissionState.blocked;
    }
    if (global == null && desktop == null) return PermissionState.unknown;
    return PermissionState.granted;
  } catch (e, s) {
    reportNonFatal(e, s, during: 'reading the Windows $capability privacy switch');
    return PermissionState.unknown;
  }
}

Future<String?> _value(RegRunner run, String key) async {
  final result = await run(['query', key, '/v', 'Value']);
  if (result.exitCode != 0) return null;
  final m = RegExp(r'Value\s+REG_SZ\s+(\S+)').firstMatch('${result.stdout}');
  return m?.group(1);
}
