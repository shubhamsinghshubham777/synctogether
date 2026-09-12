import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:synctogether/av/macos_audio_devices.dart';
import 'package:synctogether/diagnostics.dart';
import 'package:synctogether/env.dart';
import 'package:synctogether/rooms/room_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum AvConnectionState { disconnected, connecting, connected, reconnecting }

/// Voice/video layer per room. Identity = Supabase user id (the token minted
/// by the livekit-token edge function enforces room membership server-side).
class LiveKitService extends ChangeNotifier {
  LiveKitService({required this.roomId, this.avLevel = AvLevel.voice});

  final String roomId;

  final AvLevel avLevel;

  /// AV is available only when the client knows the LiveKit URL; without it
  /// the whole facecam UI stays hidden.
  static bool? isConfiguredOverride;
  static bool isMockMode = false;
  static bool get isConfigured => isConfiguredOverride ?? (Env.livekitUrl ?? '').isNotEmpty;

  static bool isAvailableFor(AvLevel level) => isConfigured && level.allowsVoice;

  bool get canPublishCamera => avLevel.allowsVideo;

  static const _cameraCapture = lk.CameraCaptureOptions(
    params: lk.VideoParameters(
      dimensions: lk.VideoDimensionsPresets.h360_169,
      encoding: lk.VideoEncoding(maxFramerate: 24, maxBitrate: 400 * 1000),
    ),
  );

  lk.Room? _room;
  lk.Room? get room => _room;

  AvConnectionState _state = .disconnected;
  AvConnectionState get state => _state;

  bool _desiredMicEnabled = false;
  bool _desiredCamEnabled = false;
  bool _disposed = false;
  bool _syncingTracks = false;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;

  bool get micEnabled => _desiredMicEnabled;
  bool get camEnabled => _desiredCamEnabled;

  lk.LocalParticipant? get localParticipant => _room?.localParticipant;
  List<lk.RemoteParticipant> get remoteParticipants =>
      _room?.remoteParticipants.values.toList() ?? const [];

  lk.EventsListener<lk.RoomEvent>? _listener;

  Future<void> connect() async {
    if (!isAvailableFor(avLevel) ||
        _state == .connecting ||
        _state == .connected ||
        _state == .reconnecting) {
      return;
    }
    _setState(.connecting);
    if (isMockMode) {
      _setState(.connected);
      return;
    }
    try {
      await _connectInternal();
    } catch (e, s) {
      reportNonFatal(e, s, during: 'connecting to LiveKit for room $roomId');
      _setState(.disconnected);
      if (!_disposed) _scheduleReconnect();
      rethrow;
    }
  }

  Future<void> _connectInternal() async {
    final response = await Supabase.instance.client.functions.invoke(
      'livekit-token',
      body: {'room_id': roomId},
    );
    final data = (response.data as Map).cast<String, dynamic>();
    final token = data['token'] as String;
    final url = (data['url'] as String?) ?? Env.livekitUrl!;

    final room = lk.Room(
      roomOptions: const lk.RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        defaultCameraCaptureOptions: _cameraCapture,
      ),
    );
    _listener = room.createListener()
      ..on<lk.RoomReconnectingEvent>((_) => _setState(.reconnecting))
      ..on<lk.RoomReconnectedEvent>((_) {
        _setState(.connected);
        _reconnectAttempts = 0;
        unawaited(_syncTracks());
      })
      ..on<lk.RoomDisconnectedEvent>(_onDisconnected)
      // Track/participant churn and speaking changes all surface as change
      // notifications so tiles rebuild.
      ..on<lk.RoomEvent>((_) {
        if (_state == .connected) {
          final local = _room?.localParticipant;
          if (local != null) {
            if ((_desiredMicEnabled && !local.isMicrophoneEnabled()) ||
                (_desiredCamEnabled && canPublishCamera && !local.isCameraEnabled())) {
              unawaited(_syncTracks());
            }
          }
        }
        notifyListeners();
      });

    await room.connect(url, token);
    _room = room;
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _setState(.connected);

    // Re-apply selected devices if set
    if (_selectedAudioInput != null) {
      unawaited(setAudioInputDevice(_selectedAudioInput!));
    }
    if (_selectedVideoInput != null) {
      unawaited(setVideoInputDevice(_selectedVideoInput!));
    }
    if (_selectedAudioOutput != null) {
      unawaited(setAudioOutputDevice(_selectedAudioOutput!));
    }

    await _syncTracks();
  }

  void _onDisconnected(lk.RoomDisconnectedEvent event) {
    trace(
      'av disconnected: ${event.reason?.name}',
      category: 'av',
      data: {'room_id': roomId, 'reason': event.reason?.name},
    );
    _setState(.disconnected);

    if (_disposed) return;

    if (event.reason == lk.DisconnectReason.clientInitiated ||
        event.reason == lk.DisconnectReason.roomDeleted ||
        event.reason == lk.DisconnectReason.duplicateIdentity) {
      return;
    }

    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed ||
        _reconnectTimer?.isActive == true ||
        _state == .connecting ||
        _state == .connected ||
        _state == .reconnecting) {
      return;
    }

    final delaySeconds = (1 << _reconnectAttempts.clamp(0, 4)).clamp(1, 15);
    _reconnectAttempts++;

    trace(
      'scheduling av reconnect attempt $_reconnectAttempts in ${delaySeconds}s',
      category: 'av',
      data: {'room_id': roomId, 'attempt': _reconnectAttempts, 'delay_s': delaySeconds},
    );

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () async {
      if (_disposed || _state == .connecting || _state == .connected) return;
      try {
        await _reconnect();
      } catch (e, s) {
        reportNonFatal(e, s, during: 'av reconnection attempt for room $roomId');
        _setState(.disconnected);
        if (!_disposed) _scheduleReconnect();
      }
    });
  }

  Future<void> _reconnect() async {
    if (_disposed) return;
    _setState(.reconnecting);

    await _cleanupRoom();
    if (_disposed) return;

    await _connectInternal();
  }

  Future<void> _cleanupRoom() async {
    await _listener?.dispose();
    _listener = null;
    try {
      await _room?.disconnect();
    } catch (_) {}
    try {
      await _room?.dispose();
    } catch (_) {}
    _room = null;
  }

  Future<void> _syncTracks() async {
    if (_syncingTracks || _state != .connected) return;
    final local = _room?.localParticipant;
    if (local == null) return;
    _syncingTracks = true;
    try {
      if (_desiredMicEnabled != local.isMicrophoneEnabled()) {
        await local.setMicrophoneEnabled(_desiredMicEnabled);
      }
      if (canPublishCamera && _desiredCamEnabled != local.isCameraEnabled()) {
        await local.setCameraEnabled(
          _desiredCamEnabled,
          cameraCaptureOptions: _desiredCamEnabled ? _cameraCapture : null,
        );
      }
    } catch (e, s) {
      reportNonFatal(e, s, during: 'syncing AV tracks for room $roomId');
    } finally {
      _syncingTracks = false;
    }
  }

  Future<void> setMicEnabled(bool enabled) async {
    _desiredMicEnabled = enabled;
    notifyListeners();
    if (_room != null && _state == .connected) {
      try {
        await _room?.localParticipant?.setMicrophoneEnabled(enabled);
      } catch (e, s) {
        reportNonFatal(e, s, during: 'setting microphone enabled to $enabled');
      }
    }
  }

  Future<void> setCamEnabled(bool enabled) async {
    if (enabled && !canPublishCamera) return;
    _desiredCamEnabled = enabled;
    notifyListeners();
    if (_room != null && _state == .connected) {
      try {
        await _room?.localParticipant?.setCameraEnabled(
          enabled,
          cameraCaptureOptions: enabled ? _cameraCapture : null,
        );
      } catch (e, s) {
        reportNonFatal(e, s, during: 'setting camera enabled to $enabled');
      }
    }
  }

  Future<List<lk.MediaDevice>> audioInputDevices() async {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      final devices = MacOSAudioDevices.getAudioInputs();
      if (devices.isNotEmpty) return devices;
    }
    return lk.Hardware.instance.audioInputs();
  }

  Future<List<lk.MediaDevice>> videoInputDevices() => lk.Hardware.instance.videoInputs();

  Future<List<lk.MediaDevice>> audioOutputDevices() async {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      final devices = MacOSAudioDevices.getAudioOutputs();
      if (devices.isNotEmpty) return devices;
    }
    return lk.Hardware.instance.audioOutputs();
  }

  lk.MediaDevice? _selectedAudioInput;
  lk.MediaDevice? get selectedAudioInput => _selectedAudioInput;
  String? get selectedAudioInputId =>
      _selectedAudioInput?.deviceId ??
      _room?.selectedAudioInputDeviceId ??
      lk.Hardware.instance.selectedAudioInput?.deviceId;
  String? get selectedAudioInputLabel =>
      _selectedAudioInput?.label ?? lk.Hardware.instance.selectedAudioInput?.label;

  lk.MediaDevice? _selectedVideoInput;
  lk.MediaDevice? get selectedVideoInput => _selectedVideoInput;
  String? get selectedVideoInputId =>
      _selectedVideoInput?.deviceId ??
      _room?.selectedVideoInputDeviceId ??
      lk.Hardware.instance.selectedVideoInput?.deviceId;
  String? get selectedVideoInputLabel =>
      _selectedVideoInput?.label ?? lk.Hardware.instance.selectedVideoInput?.label;

  lk.MediaDevice? _selectedAudioOutput;
  lk.MediaDevice? get selectedAudioOutput => _selectedAudioOutput;
  String? get selectedAudioOutputId =>
      _selectedAudioOutput?.deviceId ??
      _room?.selectedAudioOutputDeviceId ??
      lk.Hardware.instance.selectedAudioOutput?.deviceId;
  String? get selectedAudioOutputLabel =>
      _selectedAudioOutput?.label ?? lk.Hardware.instance.selectedAudioOutput?.label;

  Stream<List<lk.MediaDevice>> get onDeviceChange => lk.Hardware.instance.onDeviceChange.stream;

  Future<void> setAudioInputDevice(lk.MediaDevice device) async {
    _selectedAudioInput = device;
    var target = device;
    try {
      final webrtcDevices = await lk.Hardware.instance.audioInputs();
      final match = webrtcDevices
          .where(
            (d) =>
                d.deviceId == device.deviceId ||
                d.label.trim().toLowerCase() == device.label.trim().toLowerCase(),
          )
          .firstOrNull;
      if (match != null) target = match;
    } catch (_) {}

    if (_room != null) {
      await _room!.setAudioInputDevice(target);
    } else {
      await lk.Hardware.instance.selectAudioInput(target);
    }
    notifyListeners();
  }

  Future<void> setVideoInputDevice(lk.MediaDevice device) async {
    _selectedVideoInput = device;
    if (_room != null) {
      await _room!.setVideoInputDevice(device);
    } else {
      lk.Hardware.instance.selectedVideoInput = device;
    }
    notifyListeners();
  }

  Future<void> setAudioOutputDevice(lk.MediaDevice device) async {
    _selectedAudioOutput = device;
    var target = device;
    try {
      final webrtcDevices = await lk.Hardware.instance.audioOutputs();
      final match = webrtcDevices
          .where(
            (d) =>
                d.deviceId == device.deviceId ||
                d.label.trim().toLowerCase() == device.label.trim().toLowerCase(),
          )
          .firstOrNull;
      if (match != null) target = match;
    } catch (_) {}

    if (_room != null) {
      await _room!.setAudioOutputDevice(target);
    } else {
      await lk.Hardware.instance.selectAudioOutput(target);
    }
    notifyListeners();
  }

  void _setState(AvConnectionState state) {
    if (state != _state) {
      trace('av ${state.name}', category: 'av', data: {'room_id': roomId});
    }
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    unawaited(_cleanupRoom());
    super.dispose();
  }
}
