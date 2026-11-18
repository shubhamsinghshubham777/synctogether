import 'dart:async';

import 'package:synctogether/av/system_permissions.dart';
import 'package:synctogether/pairing/pre_show_check_logic.dart';

/// Devices handed in by the test: no camera, microphone or network is touched.
/// Every call is recorded in [calls] so a test can prove what was (not) asked.
class FakeProbes implements PreShowProbes {
  FakeProbes({
    this.camera = PermissionState.notDetermined,
    this.mic = PermissionState.notDetermined,
    this.cameraOpens = CameraOpen.ok,
    this.latency = const LatencyReading.ms(48),
    this.network = const NetworkInfo(transport: NetworkTransport.wifi),
    this.chime = ChimeResult.played,
    this.micFails = false,
  });

  PermissionState camera;
  PermissionState mic;

  /// What a request answers, when the person allows or refuses.
  PermissionState onRequestCamera = PermissionState.granted;
  PermissionState onRequestMic = PermissionState.granted;
  CameraOpen cameraOpens;
  LatencyReading latency;
  NetworkInfo network;
  ChimeResult chime;
  bool micFails;

  final calls = <String>[];
  final levels = StreamController<List<double>>.broadcast();
  final ended = StreamController<void>.broadcast();

  int count(String call) => calls.where((c) => c == call).length;

  @override
  Future<PermissionState> permission(PermissionKind kind) async =>
      kind == PermissionKind.camera ? camera : mic;

  @override
  Future<PermissionState> request(PermissionKind kind) async {
    calls.add('request:${kind.name}');
    if (kind == PermissionKind.camera) {
      camera = onRequestCamera;
      return camera;
    }
    mic = onRequestMic;
    return mic;
  }

  @override
  Future<void> openPermissionSettings(PermissionKind kind) async =>
      calls.add('settings:${kind.name}');

  @override
  Future<bool> openNetworkSettings() async {
    calls.add('network-settings');
    return true;
  }

  @override
  Future<NetworkInfo> networkInfo() async => network;

  @override
  Future<CameraOpen> openCamera() async {
    calls.add('camera-open');
    return cameraOpens;
  }

  @override
  Future<void> closeCamera() async => calls.add('camera-close');

  @override
  Stream<void> get cameraEnded => ended.stream;

  @override
  Stream<List<double>> micLevels() {
    calls.add('mic-open');
    if (micFails) return Stream<List<double>>.error(StateError('no mic'));
    return levels.stream;
  }

  @override
  Future<ChimeResult> playChime() async {
    calls.add('chime');
    return chime;
  }

  @override
  Future<LatencyReading> measureLatency() async {
    calls.add('measure');
    return latency;
  }
}
