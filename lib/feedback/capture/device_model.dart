import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:synctogether/diagnostics.dart';

import 'redact.dart';

/// The human name of the hardware a report came from ("iPhone 17", "Samsung
/// SM-S921B", "MacBook Pro"), so "it only happens on this phone" is visible
/// without asking. A model name only: never an identifier. Nothing here reads
/// `identifierForVendor`, an advertising id, a serial or a hardware UUID, and
/// the plugin calls that would return them are not made.
///
/// Fails soft. Any error leaves the model out of the report and goes to
/// `reportNonFatal`; the report is still worth sending.
class DeviceModel {
  DeviceModel._();

  /// Replaced by tests; the real lookup talks to the platform.
  @visibleForTesting
  static Future<String?> Function() lookup = _platformLookup;

  static String? _cached;
  static bool _resolved = false;

  @visibleForTesting
  static void debugReset() {
    _cached = null;
    _resolved = false;
  }

  static Future<String?> read() async {
    if (_resolved) return _cached;
    try {
      final raw = (await lookup())?.trim();
      _cached = raw == null || raw.isEmpty ? null : redactText(raw);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'reading the device model');
      _cached = null;
    }
    _resolved = true;
    return _cached;
  }

  /// "Samsung SM-S921B": the manufacturer in front unless the model already
  /// starts with it (a Pixel says "Pixel 8", a Galaxy says "SM-S921B").
  @visibleForTesting
  static String androidName(String manufacturer, String model) {
    final maker = manufacturer.trim();
    final name = model.trim();
    if (name.isEmpty) return maker;
    if (maker.isEmpty || name.toLowerCase().startsWith(maker.toLowerCase())) return name;
    return '${maker[0].toUpperCase()}${maker.substring(1)} $name';
  }

  static Future<String?> _platformLookup() async {
    final info = DeviceInfoPlugin();
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        final ios = await info.iosInfo;
        return ios.modelName.isNotEmpty ? ios.modelName : ios.model;
      case TargetPlatform.android:
        final android = await info.androidInfo;
        return androidName(android.manufacturer, android.model);
      case TargetPlatform.macOS:
        final mac = await info.macOsInfo;
        return mac.modelName.isNotEmpty ? mac.modelName : mac.model;
      case TargetPlatform.windows:
        return (await info.windowsInfo).productName;
      default:
        return null;
    }
  }
}
