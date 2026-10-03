import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:synctogether/av/av_failover.dart';
import 'package:synctogether/av/macos_audio_devices.dart';
import 'package:synctogether/diagnostics.dart';
import 'package:synctogether/env.dart';
import 'package:synctogether/rooms/room_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Consecutive transient failures before an unreachable AV backend is worth a
/// report (~45 s of 1/2/4/8/15 s backoff). Retries carry on regardless.
const kAvReportAfterAttempts = 5;

/// Whether [error] is the network or the server being unreachable: expected,
/// retried with backoff, and not a bug on its own. A 4xx from the token
/// function (not a member, bad request) is a real answer and is not transient.
bool isTransientAvError(Object error) => switch (error) {
  FunctionException(:final status) =>
    status == 0 || status == 408 || status == 429 || status >= 500,
  SocketException() ||
  HttpException() ||
  TimeoutException() ||
  lk.MediaConnectException() ||
  lk.TimeoutException() => true,
  // NotAllowed is the SFU refusing our token - a real answer, like a 4xx.
  lk.ConnectException(:final reason) => reason != lk.ConnectionErrorReason.NotAllowed,
  _ => false,
};

enum AvConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,

  /// Every AV endpoint is spent or down. Playback and chat are unaffected;
  /// the service keeps asking on a slow timer and recovers on its own.
  unavailable,
}

/// A minted token and the endpoint it is for. [camera] is whether it may
/// publish video - always in a video room, and in a voice room only while
/// its video trial runs on an endpoint that allows trials.
typedef AvToken = ({
  String token,
  String url,
  String? endpoint,
  List<String> endpoints,
  bool camera,
});

/// Fetches a token for [roomId]. [failedEndpoint] reports the endpoint we
/// could not use so the server re-pins the room elsewhere.
/// [forceEndpoint] is the debug switch; the server ignores it unless the
/// deployment sets `AV_DEBUG_SWITCHING`.
typedef AvTokenFetcher =
    Future<AvToken> Function(String roomId, {String? failedEndpoint, String? forceEndpoint});

Future<AvToken> _fetchTokenFromSupabase(
  String roomId, {
  String? failedEndpoint,
  String? forceEndpoint,
}) async {
  final response = await Supabase.instance.client.functions.invoke(
    'livekit-token',
    body: {'room_id': roomId, 'failed_endpoint': ?failedEndpoint, 'force_endpoint': ?forceEndpoint},
  );
  final data = (response.data as Map).cast<String, dynamic>();
  return (
    token: data['token'] as String,
    url: (data['url'] as String?) ?? Env.livekitUrl!,
    endpoint: data['endpoint'] as String?,
    endpoints: [...?(data['endpoints'] as List?)?.whereType<String>()],
    camera: data['camera'] as bool? ?? false,
  );
}

/// Voice/video layer per room. Identity = Supabase user id (the token minted
/// by the livekit-token edge function enforces room membership server-side).
///
/// The server may hold several LiveKit-protocol endpoints (self-hosted,
/// LiveKit Cloud). The room is pinned to one; when ours refuses or can't be
/// reached we report it and are handed the next, staying in [connecting] the
/// whole time so the switch looks like an ordinary connect. When none is left
/// we sit in [AvConnectionState.unavailable] and retry slowly.
class LiveKitService extends ChangeNotifier {
  LiveKitService({required this.roomId, this.avLevel = AvLevel.voice, AvTokenFetcher? fetchToken})
    : _fetchToken = fetchToken ?? _fetchTokenFromSupabase;

  final String roomId;

  final AvTokenFetcher _fetchToken;

  /// The endpoint we are (or were last) connected to.
  String? _endpoint;
  String? get endpoint => _endpoint;

  /// Every endpoint id the server knows - only filled in when the deployment
  /// allows debug switching, which is what shows the debug menu entry.
  List<String> _endpoints = const [];
  List<String> get endpoints => _endpoints;

  /// Consecutive unreachable-SFU failures on [_endpoint].
  int _endpointFailures = 0;

  final AvLevel avLevel;

  /// AV is available only when the client knows the LiveKit URL; without it
  /// the whole facecam UI stays hidden.
  static bool? isConfiguredOverride;
  static bool isMockMode = false;
  static bool get isConfigured => isConfiguredOverride ?? (Env.livekitUrl ?? '').isNotEmpty;

  static bool isAvailableFor(AvLevel level) => isConfigured && level.allowsVoice;

  /// Whether the camera may publish right now: a video room always, a voice
  /// room only while the token we hold carries a video-trial grant.
  bool get canPublishCamera => avLevel.allowsVideo || _trialCamera;

  /// The current token's camera grant, in a voice room. Flipped on by a fresh
  /// token after a trial starts, off at the trial's end or by a token from an
  /// endpoint that does not run trials (a failover to LiveKit Cloud).
  bool _trialCamera = false;

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
    } on AvCapacityExhausted catch (e) {
      _enterUnavailable(e);
    } catch (e, s) {
      _noteFailure(e, s, during: 'connecting to LiveKit for room $roomId');
      _setState(.disconnected);
      if (!_disposed) _scheduleReconnect();
      rethrow;
    }
  }

  /// Fetches a token and connects, hopping to another endpoint when ours
  /// refuses or stops answering. Throws [AvCapacityExhausted] when the server
  /// has nothing left to offer.
  Future<void> _connectInternal({String? force}) async {
    String? failed;
    for (var hop = 0; ; hop++) {
      final AvToken minted;
      try {
        minted = await _fetchToken(
          roomId,
          failedEndpoint: failed,
          forceEndpoint: failed == null ? force : null,
        );
      } catch (e) {
        throw capacityExhaustedFrom(e) ?? e;
      }
      if (_disposed) return;
      if (minted.endpoint != _endpoint) _endpointFailures = 0;
      _endpoint = minted.endpoint;
      if (minted.endpoints.isNotEmpty) _endpoints = minted.endpoints;
      if (!avLevel.allowsVideo) _setTrialCamera(minted.camera);
      try {
        await _connectRoom(minted.url, minted.token);
        _endpointFailures = 0;
        return;
      } catch (e) {
        final verdict = judgeConnectFailure(e);
        if (verdict == .unreachable) _endpointFailures++;
        final hopOn =
            minted.endpoint != null &&
            hop < kAvMaxHopsPerAttempt &&
            shouldFailOver(verdict, _endpointFailures);
        if (!hopOn) rethrow;
        trace(
          'av endpoint failing over',
          category: 'av',
          data: {
            'room_id': roomId,
            'endpoint': minted.endpoint,
            'verdict': verdict.name,
            'failures': _endpointFailures,
            'error': '$e',
          },
        );
        failed = minted.endpoint;
        _endpointFailures = 0;
        if (_disposed) return;
      }
    }
  }

  /// Connects a fresh [lk.Room] and only then swaps it in for the old one, so
  /// an endpoint move is make-before-break: whatever was playing keeps playing
  /// until the new SFU is actually up. A failure leaves the old room untouched.
  Future<void> _connectRoom(String url, String token) async {
    final room = lk.Room(
      roomOptions: const lk.RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        defaultCameraCaptureOptions: _cameraCapture,
      ),
    );
    // Events from a room that is not (or no longer) ours must not move our
    // state - the candidate and the outgoing room overlap during a swap.
    bool live() => identical(room, _room);
    final listener = room.createListener()
      ..on<lk.RoomReconnectingEvent>((_) {
        if (live()) _setState(.reconnecting);
      })
      ..on<lk.RoomReconnectedEvent>((_) {
        if (!live()) return;
        _setState(.connected);
        _reconnectAttempts = 0;
        unawaited(_syncTracks());
      })
      ..on<lk.RoomDisconnectedEvent>((event) {
        if (live()) _onDisconnected(event);
      })
      // Track/participant churn and speaking changes all surface as change
      // notifications so tiles rebuild.
      ..on<lk.RoomEvent>((_) {
        if (!live()) return;
        if (_state == .connected) {
          final local = room.localParticipant;
          if (local != null) {
            if ((_desiredMicEnabled && !local.isMicrophoneEnabled()) ||
                (_desiredCamEnabled && canPublishCamera && !local.isCameraEnabled())) {
              unawaited(_syncTracks());
            }
          }
        }
        notifyListeners();
      });

    try {
      await room.connect(url, token);
    } catch (_) {
      await listener.dispose();
      try {
        await room.dispose();
      } catch (_) {}
      rethrow;
    }
    if (_disposed) {
      await listener.dispose();
      await room.dispose();
      return;
    }

    final oldRoom = _room;
    final oldListener = _listener;
    _room = room;
    _listener = listener;
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _setState(.connected);
    // The old room goes after the swap: its tracks are released before ours
    // publish, so the camera is never held by two rooms at once.
    await oldListener?.dispose();
    try {
      await oldRoom?.disconnect();
      await oldRoom?.dispose();
    } catch (_) {}

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

  /// Every endpoint is out. Expected, so traced rather than reported; the
  /// retry is slow because quota does not come back in seconds.
  void _enterUnavailable(AvCapacityExhausted e) {
    trace(
      'av capacity exhausted',
      category: 'av',
      data: {'room_id': roomId, 'retry_s': e.retryAfter.inSeconds},
    );
    _setState(.unavailable);
    if (_disposed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(e.retryAfter, () {
      if (_disposed || _state != .unavailable) return;
      _reconnectAttempts = 0;
      unawaited(_reconnectGuarded());
    });
  }

  /// Another member moved the room to [endpoint] (`av_endpoint_changed`).
  /// Following it is what keeps everyone on one SFU, so it skips the backoff.
  void followEndpoint(String endpoint) {
    if (_disposed || isMockMode || endpoint == _endpoint || _state == .connecting) return;
    trace(
      'av following room to new endpoint',
      category: 'av',
      data: {'room_id': roomId, 'from': _endpoint, 'to': endpoint},
    );
    unawaited(_move());
  }

  /// Debug builds only: pin the room to [endpoint]. The rest of the room
  /// follows through the same broadcast a real failover sends.
  Future<void> debugSwitchTo(String endpoint) async {
    if (!kDebugMode || _disposed || endpoint == _endpoint) return;
    trace('av debug switch', category: 'av', data: {'room_id': roomId, 'to': endpoint});
    await _move(force: endpoint);
  }

  /// Moves a live call to another endpoint without the viewer noticing: the
  /// state stays [AvConnectionState.connected] and the old room keeps playing
  /// until the new one is up ([_connectRoom] is make-before-break). Only a
  /// call that wasn't up in the first place goes through the visible path.
  Future<void> _move({String? force}) async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    if (_state != .connected || _room == null) {
      await _reconnectGuarded(force: force);
      return;
    }
    try {
      await _connectInternal(force: force);
    } on AvCapacityExhausted catch (e) {
      // Nowhere better to go; the room we're on still works, so stay.
      trace(
        'av move found nowhere to go',
        category: 'av',
        data: {'room_id': roomId, 'retry_s': e.retryAfter.inSeconds},
      );
    } catch (e, s) {
      _noteFailure(e, s, during: 'moving AV to another endpoint for room $roomId');
    }
  }

  /// A video trial started: fetch a token that carries the camera grant. It
  /// rides the endpoint-move path, so the call never drops while it swaps.
  Future<void> beginVideoTrial() async {
    if (_disposed || avLevel.allowsVideo || _trialCamera || isMockMode) {
      if (isMockMode) _setTrialCamera(true);
      return;
    }
    trace('av video trial: refreshing grant', category: 'av', data: {'room_id': roomId});
    await _move();
  }

  /// The trial ran out. The camera goes off here, before the grant does -
  /// [_syncTracks] only touches the camera while it may publish, so flipping
  /// the grant first would leave it live until the server revokes it.
  Future<void> endVideoTrial() async {
    if (avLevel.allowsVideo || !_trialCamera) return;
    if (_desiredCamEnabled) await setCamEnabled(false);
    _setTrialCamera(false);
  }

  void _setTrialCamera(bool on) {
    if (on == _trialCamera) return;
    _trialCamera = on;
    trace(
      on ? 'av video trial camera granted' : 'av video trial camera withdrawn',
      category: 'av',
      data: {'room_id': roomId, 'endpoint': _endpoint},
    );
    // A token without the grant (trial over, or a move to an endpoint that
    // runs no trials) must not leave a camera wish behind to re-publish.
    if (!on && _desiredCamEnabled) {
      _desiredCamEnabled = false;
      final local = _room?.localParticipant;
      if (local != null && local.isCameraEnabled()) {
        unawaited(
          local.setCameraEnabled(false).catchError((Object e, StackTrace s) {
            reportNonFatal(e, s, during: 'turning the camera off as a video trial ended');
            return null;
          }),
        );
      }
    }
    notifyListeners();
  }

  Future<void> _reconnectGuarded({String? force}) async {
    try {
      await _reconnect(force: force);
    } on AvCapacityExhausted catch (e) {
      _enterUnavailable(e);
    } catch (e, s) {
      _noteFailure(e, s, during: 'av reconnection attempt for room $roomId');
      _setState(.disconnected);
      if (!_disposed) _scheduleReconnect();
    }
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

  /// An unreachable backend is traced per attempt and reported once, when it
  /// has stayed unreachable for [kAvReportAfterAttempts] tries - reporting
  /// every attempt of an endless backoff made a dev stack without its
  /// functions runtime (or a user offline) look like a flood of bugs.
  void _noteFailure(Object e, StackTrace s, {required String during}) {
    if (!isTransientAvError(e)) {
      reportNonFatal(e, s, during: during);
      return;
    }
    trace(
      'av backend unreachable',
      category: 'av',
      data: {'room_id': roomId, 'attempt': _reconnectAttempts, 'error': '$e'},
    );
    if (_reconnectAttempts == kAvReportAfterAttempts) {
      reportNonFatal(e, s, during: '$during (still unreachable after $_reconnectAttempts tries)');
    }
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
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (_disposed || _state == .connecting || _state == .connected) return;
      unawaited(_reconnectGuarded());
    });
  }

  Future<void> _reconnect({String? force}) async {
    if (_disposed) return;
    _setState(.reconnecting);
    // No teardown first: _connectRoom swaps the old room out once the new
    // one is up, and a dead old room costs nothing to keep for that long.
    await _connectInternal(force: force);
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
    if (isMockMode) {
      return const [lk.MediaDevice('mock-mic-1', 'Default Microphone', 'audioinput', null)];
    }
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      try {
        final devices = MacOSAudioDevices.getAudioInputs();
        if (devices.isNotEmpty) return devices;
      } catch (_) {}
    }
    try {
      return await lk.Hardware.instance.audioInputs();
    } catch (e, s) {
      reportNonFatal(e, s, during: 'audioInputDevices');
      return const [];
    }
  }

  Future<List<lk.MediaDevice>> videoInputDevices() async {
    if (isMockMode) {
      return const [lk.MediaDevice('mock-cam-1', 'FaceTime HD Camera', 'videoinput', null)];
    }
    try {
      return await lk.Hardware.instance.videoInputs();
    } catch (e, s) {
      reportNonFatal(e, s, during: 'videoInputDevices');
      return const [];
    }
  }

  Future<List<lk.MediaDevice>> audioOutputDevices() async {
    if (isMockMode) {
      return const [lk.MediaDevice('mock-out-1', 'Default Speaker', 'audiooutput', null)];
    }
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      try {
        final devices = MacOSAudioDevices.getAudioOutputs();
        if (devices.isNotEmpty) return devices;
      } catch (_) {}
    }
    try {
      return await lk.Hardware.instance.audioOutputs();
    } catch (e, s) {
      reportNonFatal(e, s, during: 'audioOutputDevices');
      return const [];
    }
  }

  lk.MediaDevice? _selectedAudioInput;
  lk.MediaDevice? get selectedAudioInput =>
      _selectedAudioInput ??
      (isMockMode
          ? const lk.MediaDevice('mock-mic-1', 'Default Microphone', 'audioinput', null)
          : null);
  String? get selectedAudioInputId =>
      _selectedAudioInput?.deviceId ??
      _room?.selectedAudioInputDeviceId ??
      (isMockMode ? 'mock-mic-1' : lk.Hardware.instance.selectedAudioInput?.deviceId);
  String? get selectedAudioInputLabel =>
      _selectedAudioInput?.label ??
      (isMockMode ? 'Default Microphone' : lk.Hardware.instance.selectedAudioInput?.label);

  lk.MediaDevice? _selectedVideoInput;
  lk.MediaDevice? get selectedVideoInput =>
      _selectedVideoInput ??
      (isMockMode
          ? const lk.MediaDevice('mock-cam-1', 'FaceTime HD Camera', 'videoinput', null)
          : null);
  String? get selectedVideoInputId =>
      _selectedVideoInput?.deviceId ??
      _room?.selectedVideoInputDeviceId ??
      (isMockMode ? 'mock-cam-1' : lk.Hardware.instance.selectedVideoInput?.deviceId);
  String? get selectedVideoInputLabel =>
      _selectedVideoInput?.label ??
      (isMockMode ? 'FaceTime HD Camera' : lk.Hardware.instance.selectedVideoInput?.label);

  lk.MediaDevice? _selectedAudioOutput;
  lk.MediaDevice? get selectedAudioOutput =>
      _selectedAudioOutput ??
      (isMockMode
          ? const lk.MediaDevice('mock-out-1', 'Default Speaker', 'audiooutput', null)
          : null);
  String? get selectedAudioOutputId =>
      _selectedAudioOutput?.deviceId ??
      _room?.selectedAudioOutputDeviceId ??
      (isMockMode ? 'mock-out-1' : lk.Hardware.instance.selectedAudioOutput?.deviceId);
  String? get selectedAudioOutputLabel =>
      _selectedAudioOutput?.label ??
      (isMockMode ? 'Default Speaker' : lk.Hardware.instance.selectedAudioOutput?.label);

  Stream<List<lk.MediaDevice>> get onDeviceChange =>
      isMockMode ? const Stream.empty() : lk.Hardware.instance.onDeviceChange.stream;

  Future<void> setAudioInputDevice(lk.MediaDevice device) async {
    _selectedAudioInput = device;
    if (isMockMode) {
      notifyListeners();
      return;
    }
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

    try {
      if (_room != null) {
        await _room!.setAudioInputDevice(target);
      } else {
        await lk.Hardware.instance.selectAudioInput(target);
      }
    } catch (e, s) {
      reportNonFatal(e, s, during: 'setting audio input device ${device.label}');
    }
    notifyListeners();
  }

  Future<void> setVideoInputDevice(lk.MediaDevice device) async {
    _selectedVideoInput = device;
    if (isMockMode) {
      notifyListeners();
      return;
    }
    try {
      if (_room != null) {
        await _room!.setVideoInputDevice(device);
      } else {
        lk.Hardware.instance.selectedVideoInput = device;
      }
    } catch (e, s) {
      reportNonFatal(e, s, during: 'setting video input device ${device.label}');
    }
    notifyListeners();
  }

  Future<void> setAudioOutputDevice(lk.MediaDevice device) async {
    _selectedAudioOutput = device;
    if (isMockMode) {
      notifyListeners();
      return;
    }
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

    try {
      if (_room != null) {
        await _room!.setAudioOutputDevice(target);
      } else {
        await lk.Hardware.instance.selectAudioOutput(target);
      }
    } catch (e, s) {
      reportNonFatal(e, s, during: 'setting audio output device ${device.label}');
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
