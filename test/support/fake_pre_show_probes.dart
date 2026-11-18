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
    this.filmBps,
    this.cameraList = const [],
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

  /// What the film throughput probe reads, in bits per second (null: no reading).
  double? filmBps;

  /// The cameras this fake device has (empty: just the one, unnamed).
  List<CameraChoice> cameraList;
  String? _camId;
  final changed = StreamController<void>.broadcast();
  final audio = StreamController<AudioEvent>.broadcast();

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
    _camId = cameraList.isEmpty ? null : cameraList.first.id;
    return cameraOpens;
  }

  @override
  Future<void> closeCamera() async {
    _camId = null;
    calls.add('camera-close');
  }

  @override
  Future<List<CameraChoice>> cameras() async => cameraList;

  @override
  String? get cameraId => _camId;

  @override
  Future<CameraOpen> useCamera(String id) async {
    calls.add('camera-use:$id');
    _camId = id;
    return cameraOpens;
  }

  @override
  Stream<void> get camerasChanged => changed.stream;

  @override
  Stream<AudioEvent> get audioEvents => audio.stream;

  @override
  Future<void> chooseOutput({required bool builtIn, String? name}) async =>
      calls.add('output:${builtIn ? 'builtin' : 'keep:$name'}');

  @override
  Future<void> chooseInput({required bool builtIn, String? name}) async =>
      calls.add('input:${builtIn ? 'builtin' : 'keep:$name'}');

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

  @override
  Future<double?> measureNightThroughput(String nightId) async {
    calls.add('film-probe');
    return filmBps;
  }
}
