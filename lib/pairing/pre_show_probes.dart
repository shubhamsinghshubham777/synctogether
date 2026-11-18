import 'dart:async';

import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:media_kit/media_kit.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../av/device_preference_service.dart';
import '../av/av_settings_dialog.dart' show nativeMicLevels;
import '../av/livekit_service.dart';
import '../av/system_permissions.dart';
import '../diagnostics.dart';
import '../player/stream/link_probe.dart';
import '../rooms/media_sharing_service.dart';
import 'pre_show_check_logic.dart';

/// The real devices behind the pre-show check. Everything is local: the camera
/// is a bare track that never joins a room, the microphone is the same level
/// meter the AV settings use, and the chime is the splash sound.
const _audioChannel = MethodChannel('app.synctogether/audio_events');

class DevicePreShowProbes implements PreShowProbes {
  DevicePreShowProbes({SystemPermissions? permissions, MediaSharingService? media})
    : _permissions = permissions ?? SystemPermissions.instance,
      _mediaOverride = media;

  final MediaSharingService? _mediaOverride;
  MediaSharingService? _lazyMedia;
  MediaSharingService get _media => _mediaOverride ?? (_lazyMedia ??= MediaSharingService());

  final SystemPermissions _permissions;
  lk.LocalVideoTrack? _track;
  List<lk.MediaDevice> _cams = const [];
  String? _camId;
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
      _cams = cams;
      final preferred = DevicePreferenceService.instance.resolveDevice(
        cams,
        DevicePreferenceService.instance.preferredCam,
      );
      _camId = preferred?.deviceId;
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
  Future<List<CameraChoice>> cameras() async {
    final cams = await lk.Hardware.instance.videoInputs();
    _cams = cams;
    return [for (final c in cams) CameraChoice(c.deviceId, cameraName(c.label))];
  }

  @override
  String? get cameraId => _track == null ? null : _camId;

  @override
  Future<CameraOpen> useCamera(String id) async {
    final device = _cams.where((c) => c.deviceId == id).firstOrNull;
    if (device == null) return CameraOpen.failed;
    await DevicePreferenceService.instance.setPreferredCam(device);
    return openCamera();
  }

  @override
  Stream<void> get camerasChanged => DevicePreferenceService.instance.onDeviceChange.map((_) {});

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

  StreamController<AudioEvent>? _audio;
  Timer? _statePoll;
  AudioState? _lastState;

  /// The system volume and output, once a second: nothing tells a Dart app
  /// the side keys were pressed, and a read is cheap. Said only when it changed.
  Future<void> _pollState() async {
    try {
      final m = await _audioChannel.invokeMethod<Map>('audioState');
      if (m == null) return;
      final kind = switch (m['kind']) {
        'bluetooth' => OutputKind.bluetooth,
        'airplay' => OutputKind.airplay,
        'wired' => OutputKind.wired,
        'other' => OutputKind.other,
        _ => OutputKind.builtIn,
      };
      final s = AudioState(
        volume: (m['volume'] as num?)?.toDouble(),
        outputName: m['name'] as String?,
        output: kind,
        canUseBuiltIn: m['canBuiltIn'] as bool? ?? true,
      );
      if (s == _lastState) return;
      _lastState = s;
      _audio?.add(AudioEvent(AudioEventKind.state, state: s));
    } on MissingPluginException {
      // No native side on this platform: no row.
    } catch (_) {
      // A missed read is not a verdict.
    }
  }

  @override
  Stream<AudioEvent> get audioEvents {
    var out = _audio;
    if (out != null) return out.stream;
    out = _audio = StreamController<AudioEvent>.broadcast(
      onListen: () async {
        _audioChannel.setMethodCallHandler((call) async {
          if (call.method != 'event') return;
          final m = Map<String, Object?>.from(call.arguments as Map);
          final kind = switch (m['type']) {
            'interrupted' => AudioEventKind.interrupted,
            'resumed' => AudioEventKind.resumed,
            'input' => AudioEventKind.input,
            _ => null,
          };
          if (kind == null) return;
          _audio?.add(
            AudioEvent(
              kind,
              name: m['name'] as String?,
              builtIn: m['builtIn'] as bool? ?? true,
              bluetooth: m['bluetooth'] as bool? ?? false,
              canUseBuiltIn: m['canBuiltIn'] as bool? ?? true,
            ),
          );
        });
        _lastState = null;
        _statePoll?.cancel();
        _statePoll = Timer.periodic(const Duration(seconds: 1), (_) => unawaited(_pollState()));
        unawaited(_pollState());
        try {
          await _audioChannel.invokeMethod<void>('start');
        } on MissingPluginException {
          // A platform without the channel (Windows) never says anything.
        } catch (e, s) {
          reportNonFatal(e, s, during: 'listening for audio route changes');
        }
      },
      onCancel: () async {
        _statePoll?.cancel();
        _statePoll = null;
        _audioChannel.setMethodCallHandler(null);
        try {
          await _audioChannel.invokeMethod<void>('stop');
        } catch (_) {}
      },
    );
    return out.stream;
  }

  @override
  Future<void> chooseOutput({required bool builtIn, String? name}) async {
    var label = name;
    if (builtIn) {
      try {
        final r = await _audioChannel.invokeMethod<Map>('useBuiltInOutput');
        label = r?['name'] as String?;
      } on MissingPluginException {
        label = null;
      }
    }
    if (label == null) return;
    final outputs = await lk.Hardware.instance.audioOutputs();
    final want = label.toLowerCase();
    final match =
        outputs.where((d) => d.label.toLowerCase() == want).firstOrNull ??
        outputs
            .where(
              (d) => d.label.toLowerCase().contains(want) || want.contains(d.label.toLowerCase()),
            )
            .firstOrNull;
    if (match == null) {
      trace('chosen output not in the device list', category: 'av', data: {'name': label});
      return;
    }
    await DevicePreferenceService.instance.setPreferredOutput(match);
  }

  @override
  Future<void> chooseInput({required bool builtIn, String? name}) async {
    var label = name;
    if (builtIn) {
      try {
        final r = await _audioChannel.invokeMethod<Map>('useBuiltIn');
        label = r?['name'] as String?;
      } on MissingPluginException {
        label = null;
      }
    }
    if (label == null) return;
    final inputs = await lk.Hardware.instance.audioInputs();
    final want = label.toLowerCase();
    final match =
        inputs.where((d) => d.label.toLowerCase() == want).firstOrNull ??
        inputs
            .where(
              (d) => d.label.toLowerCase().contains(want) || want.contains(d.label.toLowerCase()),
            )
            .firstOrNull;
    if (match == null) {
      trace('chosen microphone not in the device list', category: 'av', data: {'name': label});
      return;
    }
    await DevicePreferenceService.instance.setPreferredMic(match);
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

  @override
  Future<double?> measureNightThroughput(String nightId) async {
    try {
      final dl = await _media.fetchNightDownloadUrl(nightId: nightId);
      return await measureLinkBps(url: dl.streamUrl, totalBytes: dl.fileSize, allowShort: true);
    } catch (e, s) {
      if (e is MediaSharingException && e.code == 'media_gone') throw const FilmGoneException();
      if (!isTransientNetworkError(e)) {
        reportNonFatal(e, s, during: 'testing the connection against the date night film');
      }
      return null;
    }
  }
}
