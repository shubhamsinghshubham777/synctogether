import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../diagnostics.dart';

/// What the pre-show check can ask the system about.
enum PermissionKind {
  camera('camera'),
  mic('mic');

  const PermissionKind(this.wire);
  final String wire;
}

/// Where a permission stands, from the person's side.
enum PermissionState {
  granted,

  /// Never asked: tapping the row is what shows the system dialog.
  notDetermined,

  /// Refused, but the system will still ask (Android's first no).
  denied,

  /// Refused and the dialog will not return: only system settings can change it
  /// (iOS after any no, Android after two).
  blocked,

  /// Switched off by something the person cannot change here: Screen Time, a
  /// school or work profile, parental controls.
  restricted,

  /// This platform has no way to say (Windows). The check falls back to what
  /// happens when it tries to open the device.
  unknown,
}

/// How the device is connected, for the notes that depend on it.
enum NetworkTransport { wifi, cellular, other, none, unknown }

class NetworkInfo {
  const NetworkInfo({this.transport = NetworkTransport.unknown, this.saver = false});

  final NetworkTransport transport;

  /// Low Data Mode (iOS) or Data Saver (Android) is on.
  final bool saver;
}

/// Camera and microphone permission, and the system pages a fix lives on, behind
/// an interface so the pre-show check is testable with no device.
abstract class SystemPermissions {
  static SystemPermissions instance = ChannelSystemPermissions();

  Future<PermissionState> status(PermissionKind kind);

  /// The one call that shows a system dialog. Made because a person tapped.
  Future<PermissionState> request(PermissionKind kind);

  /// The page where [kind] is switched: the app's own on iOS and Android, the
  /// matching Privacy pane on desktop.
  Future<void> openPermissionSettings(PermissionKind kind);

  /// The page where the connection is fixed (Wi-Fi or mobile data).
  Future<bool> openNetworkSettings();

  Future<NetworkInfo> networkInfo();
}

class ChannelSystemPermissions implements SystemPermissions {
  static const _channel = MethodChannel('app.synctogether/permissions');

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    }
  }

  PermissionState _parse(String? v) => switch (v) {
    'granted' => PermissionState.granted,
    'notDetermined' => PermissionState.notDetermined,
    'denied' => PermissionState.denied,
    'blocked' => PermissionState.blocked,
    'restricted' => PermissionState.restricted,
    _ => PermissionState.unknown,
  };

  @override
  Future<PermissionState> status(PermissionKind kind) async {
    try {
      return _parse(await _call<String>('status', {'kind': kind.wire}));
    } catch (e, s) {
      reportNonFatal(e, s, during: 'reading the ${kind.wire} permission');
      return PermissionState.unknown;
    }
  }

  @override
  Future<PermissionState> request(PermissionKind kind) async {
    try {
      final result = _parse(await _call<String>('request', {'kind': kind.wire}));
      trace('permission asked', category: 'av', data: {'kind': kind.wire, 'result': result.name});
      return result;
    } catch (e, s) {
      reportNonFatal(e, s, during: 'asking for the ${kind.wire} permission');
      return PermissionState.unknown;
    }
  }

  @override
  Future<void> openPermissionSettings(PermissionKind kind) async {
    if (!kIsWeb && Platform.isWindows) {
      // Windows has one switch for desktop apps per device; the page is a URI.
      await _launch(
        'ms-settings:privacy-${kind == PermissionKind.camera ? 'webcam' : 'microphone'}',
      );
      return;
    }
    await _call<void>('openAppSettings', {'kind': kind.wire});
  }

  @override
  Future<NetworkInfo> networkInfo() async {
    try {
      final m = await _call<Map>('networkInfo');
      if (m == null) return const NetworkInfo();
      return NetworkInfo(
        transport: switch (m['transport']) {
          'wifi' => NetworkTransport.wifi,
          'cellular' => NetworkTransport.cellular,
          'none' => NetworkTransport.none,
          'other' => NetworkTransport.other,
          _ => NetworkTransport.unknown,
        },
        saver: m['saver'] == true,
      );
    } catch (e, s) {
      reportNonFatal(e, s, during: 'reading the network type');
      return const NetworkInfo();
    }
  }

  @override
  Future<bool> openNetworkSettings() async {
    if (!kIsWeb && Platform.isWindows) return _launch('ms-settings:network');
    return await _call<bool>('openNetworkSettings') ?? false;
  }

  Future<bool> _launch(String uri) async {
    try {
      return await launchUrl(Uri.parse(uri));
    } catch (e, s) {
      reportNonFatal(e, s, during: 'opening a system settings page');
      return false;
    }
  }
}
