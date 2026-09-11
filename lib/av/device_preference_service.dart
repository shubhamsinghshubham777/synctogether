import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:shared_preferences/shared_preferences.dart';

class PreferredDevice {
  const PreferredDevice({required this.id, required this.label});
  final String id;
  final String label;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PreferredDevice &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          label == other.label;

  @override
  int get hashCode => id.hashCode ^ label.hashCode;

  @override
  String toString() => 'PreferredDevice(id: $id, label: $label)';
}

/// Manages persisted user preferences for default audio and video hardware
/// devices, and provides resilient fallback resolution when devices disconnect.
class DevicePreferenceService extends ChangeNotifier {
  DevicePreferenceService._();

  static final DevicePreferenceService instance = DevicePreferenceService._();

  static const _kMicIdKey = 'preferred_mic_id';
  static const _kMicLabelKey = 'preferred_mic_label';
  static const _kCamIdKey = 'preferred_cam_id';
  static const _kCamLabelKey = 'preferred_cam_label';
  static const _kOutputIdKey = 'preferred_output_id';
  static const _kOutputLabelKey = 'preferred_output_label';

  SharedPreferences? _prefs;
  bool _initialized = false;
  bool get isInitialized => _initialized;

  PreferredDevice? _preferredMic;
  PreferredDevice? _preferredCam;
  PreferredDevice? _preferredOutput;

  PreferredDevice? get preferredMic => _preferredMic;
  PreferredDevice? get preferredCam => _preferredCam;
  PreferredDevice? get preferredOutput => _preferredOutput;

  Stream<List<lk.MediaDevice>> get onDeviceChange => lk.Hardware.instance.onDeviceChange.stream;

  Future<void> init([SharedPreferences? testPrefs]) async {
    if (_initialized && testPrefs == null) return;
    _prefs = testPrefs ?? await SharedPreferences.getInstance();

    final micId = _prefs!.getString(_kMicIdKey);
    final micLabel = _prefs!.getString(_kMicLabelKey);
    if (micId != null && micLabel != null) {
      _preferredMic = PreferredDevice(id: micId, label: micLabel);
    }

    final camId = _prefs!.getString(_kCamIdKey);
    final camLabel = _prefs!.getString(_kCamLabelKey);
    if (camId != null && camLabel != null) {
      _preferredCam = PreferredDevice(id: camId, label: camLabel);
    }

    final outputId = _prefs!.getString(_kOutputIdKey);
    final outputLabel = _prefs!.getString(_kOutputLabelKey);
    if (outputId != null && outputLabel != null) {
      _preferredOutput = PreferredDevice(id: outputId, label: outputLabel);
    }

    _initialized = true;
    notifyListeners();
  }

  Future<void> setPreferredMic(lk.MediaDevice? device) async {
    await _ensureInitialized();
    if (device == null) {
      _preferredMic = null;
      await _prefs?.remove(_kMicIdKey);
      await _prefs?.remove(_kMicLabelKey);
    } else {
      _preferredMic = PreferredDevice(id: device.deviceId, label: device.label);
      await _prefs?.setString(_kMicIdKey, device.deviceId);
      await _prefs?.setString(_kMicLabelKey, device.label);
    }
    notifyListeners();
  }

  Future<void> setPreferredCam(lk.MediaDevice? device) async {
    await _ensureInitialized();
    if (device == null) {
      _preferredCam = null;
      await _prefs?.remove(_kCamIdKey);
      await _prefs?.remove(_kCamLabelKey);
    } else {
      _preferredCam = PreferredDevice(id: device.deviceId, label: device.label);
      await _prefs?.setString(_kCamIdKey, device.deviceId);
      await _prefs?.setString(_kCamLabelKey, device.label);
    }
    notifyListeners();
  }

  Future<void> setPreferredOutput(lk.MediaDevice? device) async {
    await _ensureInitialized();
    if (device == null) {
      _preferredOutput = null;
      await _prefs?.remove(_kOutputIdKey);
      await _prefs?.remove(_kOutputLabelKey);
    } else {
      _preferredOutput = PreferredDevice(id: device.deviceId, label: device.label);
      await _prefs?.setString(_kOutputIdKey, device.deviceId);
      await _prefs?.setString(_kOutputLabelKey, device.label);
    }
    notifyListeners();
  }

  /// Resolves the best available device from [available] based on [preferred].
  ///
  /// Fallback hierarchy:
  /// 1. Exact `deviceId` match.
  /// 2. Exact `label` match (handles deviceId changes across reboots).
  /// 3. Partial `label` match (e.g. system name variants).
  /// 4. System default / first available.
  lk.MediaDevice? resolveDevice(List<lk.MediaDevice> available, PreferredDevice? preferred) {
    if (available.isEmpty) return null;
    if (preferred == null) return available.firstOrNull;

    // 1. Exact deviceId match
    if (preferred.id.isNotEmpty) {
      final exactId = available.firstWhereOrNull((d) => d.deviceId == preferred.id);
      if (exactId != null) return exactId;
    }

    final targetLabel = preferred.label.trim().toLowerCase();
    if (targetLabel.isNotEmpty) {
      // 2. Exact label match
      final exactLabel = available.firstWhereOrNull(
        (d) => d.label.trim().toLowerCase() == targetLabel,
      );
      if (exactLabel != null) return exactLabel;

      // 3. Partial label match
      final partialLabel = available.firstWhereOrNull((d) {
        final dLabel = d.label.trim().toLowerCase();
        return dLabel.contains(targetLabel) || targetLabel.contains(dLabel);
      });
      if (partialLabel != null) return partialLabel;
    }

    // 4. Default / first available
    return available.firstOrNull;
  }

  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await init();
    }
  }
}
