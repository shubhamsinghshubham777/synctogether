import 'dart:async';

import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:media_kit/media_kit.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../av/device_preference_service.dart';
import '../av/av_settings_dialog.dart' show nativeMicLevels;
import '../av/livekit_service.dart';
import '../av/system_permissions.dart';
import '../diagnostics.dart';
import 'pre_show_check_logic.dart';

/// The real devices behind the pre-show check. Everything is local: the camera
/// is a bare track that never joins a room, the microphone is the same level
/// meter the AV settings use, and the chime is the splash sound.
class DevicePreShowProbes implements PreShowProbes {
  DevicePreShowProbes({SystemPermissions? permissions})
    : _permissions = permissions ?? SystemPermissions.instance;

  final SystemPermissions _permissions;
  lk.LocalVideoTrack? _track;
  final _ended = StreamController<void>.broadcast();

  @override
  Future<PermissionState> permission(PermissionKind kind) => _permissions.status(kind);

  @override
  Future<PermissionState> request(PermissionKind kind) => _permissions.request(kind);

  @override
  Future<void> openPermissionSettings(PermissionKind kind) =>
      _permissions.openPermissionSettings(kind);

  @override
  Future<bool> openNetworkSettings() => _permissions.openNetworkSettings();

  @override
  Future<NetworkInfo> networkInfo() => _permissions.networkInfo();

  /// The live preview track, for the thumbnail. Null when the camera is off.
  lk.LocalVideoTrack? get track => _track;

  @override
  Stream<void> get cameraEnded => _ended.stream;

  @override
  Future<CameraOpen> openCamera() async {
    if (LiveKitService.isMockMode) return CameraOpen.ok;
    await closeCamera();
    try {
      final cams = await lk.Hardware.instance.videoInputs();
      if (cams.isEmpty) return CameraOpen.none;
      final preferred = DevicePreferenceService.instance.resolveDevice(
        cams,
        DevicePreferenceService.instance.preferredCam,
      );
      final track = await lk.LocalVideoTrack.createCameraTrack(
        lk.CameraCaptureOptions(deviceId: preferred?.deviceId),
      );
      await track.start();
      _track = track;
      track.mediaStreamTrack.onEnded = () {
        if (!_ended.isClosed) _ended.add(null);
      };
      return CameraOpen.ok;
    } catch (e, s) {
      final text = '$e'.toLowerCase();
      if (text.contains('notallowed') || text.contains('permission') || text.contains('denied')) {
        return CameraOpen.denied;
      }
      if (text.contains('notfound') || text.contains('no camera') || text.contains('no device')) {
        return CameraOpen.none;
      }
      if (text.contains('notreadable') || text.contains('in use') || text.contains('busy')) {
        return CameraOpen.busy;
      }
      reportNonFatal(e, s, during: 'opening the pre-show camera');
      return CameraOpen.failed;
    }
  }

  @override
  Future<void> closeCamera() async {
    final track = _track;
    _track = null;
    if (track == null) return;
    track.mediaStreamTrack.onEnded = null;
    try {
      await track.stop();
      await track.dispose();
    } catch (e, s) {
      reportNonFatal(e, s, during: 'closing the pre-show camera');
    }
  }

  @override
  Stream<List<double>> micLevels() =>
      nativeMicLevels(DevicePreferenceService.instance.preferredMic?.label);

  @override
  Future<ChimeResult> playChime() async {
    if (LiveKitService.isMockMode) return ChimeResult.played;
    Player? player;
    try {
      MediaKit.ensureInitialized();
      player = Player();
      final out = DevicePreferenceService.instance.preferredOutput;
      if (out != null) {
        try {
          final outputs = await lk.Hardware.instance.audioOutputs();
          final match = DevicePreferenceService.instance.resolveDevice(outputs, out);
          if (match != null) await lk.Hardware.instance.selectAudioOutput(match);
        } catch (_) {
          // The default output is what the room would use too.
        }
      }
      await player.open(Media('asset:///assets/sfx/splash.wav'), play: true);
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      return ChimeResult.played;
    } catch (e, s) {
      reportNonFatal(e, s, during: 'playing the pre-show chime');
      return ChimeResult.failed;
    } finally {
      try {
        await player?.dispose();
      } catch (_) {}
    }
  }

  /// Median of three round trips to the server the room runs on. A failure that
  /// is only the network is a reading ("offline"), not an error to report.
  @override
  Future<LatencyReading> measureLatency() async {
    final samples = <int>[];
    for (var i = 0; i < 3; i++) {
      final watch = Stopwatch()..start();
      try {
        await Supabase.instance.client.rpc('get_server_time').timeout(const Duration(seconds: 8));
        samples.add(watch.elapsedMilliseconds);
      } catch (e, s) {
        if (samples.isEmpty && i == 2) {
          if (!isTransientNetworkError(e)) {
            reportNonFatal(e, s, during: 'measuring the connection for the pre-show check');
          }
          return const LatencyReading.failed();
        }
      }
    }
    if (samples.isEmpty) return const LatencyReading.failed();
    samples.sort();
    return LatencyReading.ms(samples[samples.length ~/ 2]);
  }
}
