import 'dart:async';
import '../ui/booth_icons.g.dart';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel, MissingPluginException;
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:media_kit/media_kit.dart';
import 'package:synctogether/av/device_preference_service.dart';
import 'package:synctogether/av/livekit_service.dart';
import 'package:synctogether/av/macos_audio_devices.dart';
import 'package:synctogether/diagnostics.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/loader.dart';
import 'package:synctogether/ui/pt_theme.dart';

/// Factory for creating local video tracks. Injectable for testing without real camera hardware.
typedef CameraTrackFactory = Future<lk.LocalVideoTrack?> Function(String? deviceId);

Future<void> showAvSettingsDialog(
  BuildContext context, {
  Future<List<lk.MediaDevice>> Function()? enumerateAudioInputs,
  Future<List<lk.MediaDevice>> Function()? enumerateVideoInputs,
  Future<List<lk.MediaDevice>> Function()? enumerateAudioOutputs,
  Player? testPlayer,
  Future<void> Function(lk.MediaDevice? selectedOutput)? onTestSound,
  MicLevels? micLevels,
  CameraTrackFactory? cameraTrackFactory,
}) {
  return showGlassDialog(
    context: context,
    width: 460,
    // Owns its scrolling: the device list is the Flexible middle, so the
    // header and the Save row stay put while it scrolls.
    scrollable: false,
    sheetOnCompact: true,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
    builder: (dialogContext) => _AvSettingsDialogContent(
      enumerateAudioInputs: enumerateAudioInputs,
      enumerateVideoInputs: enumerateVideoInputs,
      enumerateAudioOutputs: enumerateAudioOutputs,
      testPlayer: testPlayer,
      onTestSound: onTestSound,
      micLevels: micLevels ?? nativeMicLevels,
      cameraTrackFactory: cameraTrackFactory,
    ),
  );
}

/// Bar levels (0..1) for a microphone, for as long as the stream is listened
/// to. Takes the device's label. Injectable so tests never open a real device.
typedef MicLevels = Stream<List<double>> Function(String? deviceLabel);

const _kMeterBars = 16;

const _micLevelChannel = MethodChannel('app.synctogether/mic_level');

/// The meter on every platform: each runner reads its own input device
/// (WASAPI, CoreAudio, AVAudioEngine, AudioRecord) and answers `peak`. WebRTC
/// is out of this path on purpose - it only captures once a track rides a
/// peer connection, so a bare local track never delivered a frame. Polls the
/// peak at ~30 Hz and maps it to 0..1 over a 60 dB window, with a fast attack
/// and a short decay so the segments read as an instrument. The device is
/// matched by label; phones have one input and ignore it.
Stream<List<double>> nativeMicLevels(String? deviceLabel) {
  Timer? poll;
  late final StreamController<List<double>> out;
  out = StreamController<List<double>>(
    onListen: () async {
      try {
        final started = await _micLevelChannel.invokeMethod<bool>('start', {'name': deviceLabel});
        if (started != true) {
          // Includes a refused permission: the user's answer, not a bug.
          trace(
            'mic level test refused',
            category: 'av',
            data: {'platform': Platform.operatingSystem},
          );
          if (!out.isClosed) out.addError(StateError('mic level start failed'));
          return;
        }
        if (out.isClosed) return;
        var shown = 0.0;
        poll = Timer.periodic(const Duration(milliseconds: 33), (_) async {
          try {
            final peak = await _micLevelChannel.invokeMethod<double>('peak') ?? 0;
            final db = peak <= 0.000001 ? -60.0 : 20 * math.log(peak) / math.ln10;
            final target = ((db + 60) / 60).clamp(0.0, 1.0);
            shown = target > shown ? target : shown * 0.85 + target * 0.15;
            if (!out.isClosed) out.add([shown]);
          } on MissingPluginException {
            // Torn down mid-poll.
          }
        });
        trace(
          'mic level test started',
          category: 'av',
          data: {'platform': Platform.operatingSystem},
        );
      } catch (e, st) {
        reportNonFatal(e, st, during: 'mic level test');
        if (!out.isClosed) out.addError(e);
      }
    },
    onCancel: () async {
      poll?.cancel();
      try {
        await _micLevelChannel.invokeMethod<void>('stop');
      } catch (_) {}
    },
  );
  return out.stream;
}

class _AvSettingsDialogContent extends StatefulWidget {
  const _AvSettingsDialogContent({
    this.enumerateAudioInputs,
    this.enumerateVideoInputs,
    this.enumerateAudioOutputs,
    this.testPlayer,
    this.onTestSound,
    required this.micLevels,
    this.cameraTrackFactory,
  });

  final MicLevels micLevels;
  final Future<List<lk.MediaDevice>> Function()? enumerateAudioInputs;
  final Future<List<lk.MediaDevice>> Function()? enumerateVideoInputs;
  final Future<List<lk.MediaDevice>> Function()? enumerateAudioOutputs;
  final Player? testPlayer;
  final Future<void> Function(lk.MediaDevice? selectedOutput)? onTestSound;
  final CameraTrackFactory? cameraTrackFactory;

  @override
  State<_AvSettingsDialogContent> createState() => _AvSettingsDialogContentState();
}

class _AvSettingsDialogContentState extends State<_AvSettingsDialogContent> {
  final _prefService = DevicePreferenceService.instance;

  List<lk.MediaDevice> _audioInputs = [];
  List<lk.MediaDevice> _videoInputs = [];
  List<lk.MediaDevice> _audioOutputs = [];
  bool _loading = true;

  lk.MediaDevice? _selectedMic;
  lk.MediaDevice? _selectedOutput;
  lk.MediaDevice? _selectedCam;
  bool _initializedSelections = false;
  bool _saving = false;

  StreamSubscription? _deviceSub;
  Player? _testPlayer;
  bool _isPlayingTestSound = false;

  // Output test audio levels animation.
  Timer? _outputAnimTimer;
  final _outputBars = ValueNotifier<List<double>>(const []);

  // Video preview track & testing state.
  lk.LocalVideoTrack? _camTrack;
  bool _camTesting = true;
  bool _camFailed = false;

  // The mic test: levels land in a notifier that only the meter's painter
  // listens to, so a 60 Hz stream never rebuilds the dialog.
  StreamSubscription<List<double>>? _micSub;
  final _micBars = ValueNotifier<List<double>>(const []);
  bool _micFailed = false;

  @override
  void initState() {
    super.initState();
    if (widget.testPlayer != null) {
      _testPlayer = widget.testPlayer;
    }
    _loadAll();
    _deviceSub = _prefService.onDeviceChange.listen((_) => _loadDevicesOnly());
  }

  @override
  void dispose() {
    _deviceSub?.cancel();
    _micSub?.cancel();
    _micBars.dispose();
    _outputAnimTimer?.cancel();
    _outputBars.dispose();
    _camTrack?.stop();
    _camTrack?.dispose();
    _testPlayer?.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await _prefService.init();
    await _loadDevicesOnly();
  }

  Future<void> _loadDevicesOnly() async {
    try {
      if (widget.enumerateAudioInputs == null) {
        try {
          await rtc.WebRTC.initialize().timeout(
            const Duration(milliseconds: 500),
            onTimeout: () {},
          );
        } catch (_) {}
      }

      List<lk.MediaDevice> inputs;
      List<lk.MediaDevice> videos;
      List<lk.MediaDevice> outputs;

      if (LiveKitService.isMockMode) {
        inputs = const [lk.MediaDevice('mock-mic-1', 'Default Microphone', 'audioinput', null)];
        videos = const [lk.MediaDevice('mock-cam-1', 'FaceTime HD Camera', 'videoinput', null)];
        outputs = const [lk.MediaDevice('mock-out-1', 'Default Speaker', 'audiooutput', null)];
      } else {
        if (widget.enumerateAudioInputs != null) {
          inputs = await widget.enumerateAudioInputs!();
        } else if (Platform.isMacOS) {
          inputs = MacOSAudioDevices.getAudioInputs();
          if (inputs.isEmpty) {
            inputs = await lk.Hardware.instance.audioInputs();
          }
        } else {
          inputs = [];
          for (var i = 0; i < 4; i++) {
            inputs = await lk.Hardware.instance.audioInputs();
            if (inputs.isNotEmpty) break;
            await Future.delayed(const Duration(milliseconds: 300));
          }
        }

        videos = widget.enumerateVideoInputs != null
            ? await widget.enumerateVideoInputs!()
            : await lk.Hardware.instance.videoInputs();

        if (widget.enumerateAudioOutputs != null) {
          outputs = await widget.enumerateAudioOutputs!();
        } else if (Platform.isMacOS) {
          outputs = MacOSAudioDevices.getAudioOutputs();
          if (outputs.isEmpty) {
            outputs = await lk.Hardware.instance.audioOutputs();
          }
        } else {
          outputs = [];
          for (var i = 0; i < 4; i++) {
            outputs = await lk.Hardware.instance.audioOutputs();
            if (outputs.isNotEmpty) break;
            await Future.delayed(const Duration(milliseconds: 300));
          }
        }
      }

      // If WebRTC audio outputs list is still empty on desktop, fallback to
      // media_kit player devices (which use a separate CoreAudio enumeration).
      if (outputs.isEmpty && widget.enumerateAudioOutputs == null) {
        try {
          var player = _testPlayer;
          if (player == null) {
            MediaKit.ensureInitialized();
            player = Player();
            _testPlayer = player;
          }
          // Wait briefly for media_kit's CoreAudio device list to populate.
          List<AudioDevice> playerDevices = player.state.audioDevices;
          if (playerDevices.isEmpty || playerDevices.every((d) => d.name == 'auto')) {
            try {
              playerDevices = await player.stream.audioDevices
                  .firstWhere((devices) => devices.any((d) => d.name != 'auto'))
                  .timeout(const Duration(milliseconds: 600));
            } catch (_) {
              playerDevices = player.state.audioDevices;
            }
          }
          if (playerDevices.isNotEmpty) {
            outputs = playerDevices
                .where((d) => d.name != 'auto' && d.name != 'no')
                .map(
                  (d) => lk.MediaDevice(
                    d.name,
                    d.description.isEmpty ? d.name : d.description,
                    'audiooutput',
                    null,
                  ),
                )
                .toList();
          }
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _audioInputs = inputs;
        _videoInputs = videos;
        _audioOutputs = outputs;
        _loading = false;
        if (!_initializedSelections) {
          _selectedMic = _prefService.resolveDevice(inputs, _prefService.preferredMic);
          _selectedCam = _prefService.resolveDevice(videos, _prefService.preferredCam);
          _selectedOutput = _prefService.resolveDevice(outputs, _prefService.preferredOutput);
          _initializedSelections = true;
          if (_selectedCam != null && _camTesting) {
            _startCamPreview();
          }
        } else {
          _selectedMic = _prefService.resolveDevice(
            inputs,
            _selectedMic != null
                ? PreferredDevice(id: _selectedMic!.deviceId, label: _selectedMic!.label)
                : _prefService.preferredMic,
          );
          _selectedCam = _prefService.resolveDevice(
            videos,
            _selectedCam != null
                ? PreferredDevice(id: _selectedCam!.deviceId, label: _selectedCam!.label)
                : _prefService.preferredCam,
          );
          _selectedOutput = _prefService.resolveDevice(
            outputs,
            _selectedOutput != null
                ? PreferredDevice(id: _selectedOutput!.deviceId, label: _selectedOutput!.label)
                : _prefService.preferredOutput,
          );
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  AudioDevice? _findMatchingAudioDevice(
    List<AudioDevice> playerDevices,
    lk.MediaDevice targetDevice,
  ) {
    if (playerDevices.isEmpty) return null;
    final targetLabel = targetDevice.label.trim().toLowerCase();
    final targetId = targetDevice.deviceId.trim().toLowerCase();

    // 1. Exact ID / name match
    if (targetId.isNotEmpty) {
      final match = playerDevices.where((d) => d.name.trim().toLowerCase() == targetId).firstOrNull;
      if (match != null) return match;
    }

    // 2. Exact label match with description or name
    if (targetLabel.isNotEmpty) {
      final match = playerDevices.where((d) {
        final desc = d.description.trim().toLowerCase();
        final name = d.name.trim().toLowerCase();
        return desc == targetLabel || name == targetLabel;
      }).firstOrNull;
      if (match != null) return match;
    }

    // 3. Substring match
    if (targetLabel.isNotEmpty) {
      final match = playerDevices.where((d) {
        final desc = d.description.trim().toLowerCase();
        final name = d.name.trim().toLowerCase();
        return (desc.isNotEmpty && (desc.contains(targetLabel) || targetLabel.contains(desc))) ||
            (name.isNotEmpty && (name.contains(targetLabel) || targetLabel.contains(name)));
      }).firstOrNull;
      if (match != null) return match;
    }

    // 4. Token / word match (e.g. "headphones", "speakers", "airpods")
    final tokens = targetLabel.split(RegExp(r'\s+')).where((t) => t.length > 2).toList();
    if (tokens.isNotEmpty) {
      final match = playerDevices.where((d) {
        final desc = d.description.trim().toLowerCase();
        final name = d.name.trim().toLowerCase();
        return tokens.every((t) => desc.contains(t) || name.contains(t));
      }).firstOrNull;
      if (match != null) return match;
    }

    return null;
  }

  void _startOutputAnimation() {
    _outputAnimTimer?.cancel();
    final startTime = DateTime.now();
    const duration = Duration(milliseconds: 1400);

    _outputAnimTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
      final elapsed = DateTime.now().difference(startTime);
      if (elapsed >= duration || !_isPlayingTestSound) {
        timer.cancel();
        _outputBars.value = const [];
        if (mounted && _isPlayingTestSound) {
          setState(() => _isPlayingTestSound = false);
        }
        return;
      }

      final progress = elapsed.inMilliseconds / duration.inMilliseconds;
      // Resonant splash chime envelope: attack peak around 15%, decaying with rhythmic bounce.
      final envelope = (progress < 0.15) ? (progress / 0.15) : (1.0 - progress).clamp(0.0, 1.0);
      final bounce = (0.55 + 0.45 * (1 + (timer.tick % 4)) / 4.0);
      final peak = (envelope * bounce).clamp(0.0, 1.0);

      _outputBars.value = List.generate(_kMeterBars, (i) {
        final factor = (1.0 - (i / _kMeterBars) * 0.4);
        return (peak * factor).clamp(0.0, 1.0);
      });
    });
  }

  Future<void> _stopTestSound() async {
    _outputAnimTimer?.cancel();
    _outputBars.value = const [];
    try {
      await _testPlayer?.stop();
    } catch (_) {}
    if (mounted) {
      setState(() => _isPlayingTestSound = false);
    }
  }

  Future<void> _playTestSound() async {
    if (_isPlayingTestSound) return;
    setState(() => _isPlayingTestSound = true);
    _startOutputAnimation();

    if (LiveKitService.isMockMode) {
      await Future.delayed(const Duration(milliseconds: 600));
      _stopTestSound();
      return;
    }
    try {
      if (widget.onTestSound != null) {
        await widget.onTestSound!(_selectedOutput);
        return;
      }

      var player = _testPlayer;
      if (player == null) {
        try {
          MediaKit.ensureInitialized();
          player = Player();
          _testPlayer = player;
        } catch (_) {}
      }

      // Route to currently selected draft output device if available
      final targetDevice = _selectedOutput;
      if (targetDevice != null) {
        // Also route LiveKit / WebRTC hardware output device on desktop
        try {
          await lk.Hardware.instance.selectAudioOutput(targetDevice);
        } catch (_) {}

        if (player != null) {
          var playerDevices = player.state.audioDevices;
          if (playerDevices.isEmpty || playerDevices.every((d) => d.name == 'auto')) {
            try {
              playerDevices = await player.stream.audioDevices
                  .firstWhere((devices) => devices.any((d) => d.name != 'auto'))
                  .timeout(const Duration(milliseconds: 600));
            } catch (_) {
              playerDevices = player.state.audioDevices;
            }
          }

          final match = _findMatchingAudioDevice(playerDevices, targetDevice);
          if (match != null) {
            await player.setAudioDevice(match);
          }
        }
      }

      if (player != null) {
        await player.open(Media('asset:///assets/sfx/splash.wav'), play: true);
        await Future.delayed(const Duration(milliseconds: 1400));
      }
    } catch (_) {
      // Fallback or silent catch for environments without audio hardware
    } finally {
      _stopTestSound();
    }
  }

  Future<void> _saveAndClose() async {
    setState(() => _saving = true);
    try {
      await _prefService.setPreferredMic(_selectedMic);
      await _prefService.setPreferredOutput(_selectedOutput);
      await _prefService.setPreferredCam(_selectedCam);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  bool get _micTesting => _micSub != null;

  Future<void> _toggleMicTest() async {
    if (_micTesting) {
      debugPrint('[BoothCheck/UI] Stopping mic test');
      _stopMicTest();
      return;
    }
    debugPrint(
      '[BoothCheck/UI] Toggling mic test ON. Selected mic: id="${_selectedMic?.deviceId}", label="${_selectedMic?.label}"',
    );
    setState(() {
      _micFailed = false;
    });

    setState(() {
      _micSub = widget
          .micLevels(_selectedMic?.label)
          .listen(
            (bars) {
              _micBars.value = bars;
            },
            onError: (Object err) {
              debugPrint('[BoothCheck/UI] micLevels stream emitted error: $err');
              if (!mounted) return;
              _stopMicTest();
              setState(() => _micFailed = true);
            },
          );
    });
  }

  void _stopMicTest() {
    _micSub?.cancel();
    _micBars.value = const [];
    if (mounted) setState(() => _micSub = null);
  }

  Future<void> _startCamPreview() async {
    if (_selectedCam == null) return;
    await _stopCamPreview();
    if (!mounted) return;
    setState(() {
      _camTesting = true;
      _camFailed = false;
    });

    if (LiveKitService.isMockMode) {
      return;
    }

    try {
      lk.LocalVideoTrack? track;
      if (widget.cameraTrackFactory != null) {
        track = await widget.cameraTrackFactory!(_selectedCam?.deviceId);
      } else {
        String? targetCamId = _selectedCam?.deviceId;
        try {
          final webrtcCams = await lk.Hardware.instance.videoInputs();
          final match = webrtcCams
              .where(
                (d) =>
                    (targetCamId != null && d.deviceId == targetCamId) ||
                    (_selectedCam != null &&
                        d.label.trim().toLowerCase() == _selectedCam!.label.trim().toLowerCase()),
              )
              .firstOrNull;
          if (match != null) {
            targetCamId = match.deviceId;
            lk.Hardware.instance.selectedVideoInput = match;
          }
        } catch (_) {}

        track = await lk.LocalVideoTrack.createCameraTrack(
          lk.CameraCaptureOptions(deviceId: targetCamId),
        );
      }

      if (track != null) {
        await track.start();
      }

      if (!mounted) {
        await track?.stop();
        await track?.dispose();
        return;
      }

      setState(() {
        _camTrack = track;
        _camFailed = false;
      });
    } catch (e, st) {
      reportNonFatal(e, st, during: 'cam preview test');
      if (mounted) {
        setState(() {
          _camFailed = true;
          _camTrack = null;
        });
      }
    }
  }

  Future<void> _stopCamPreview() async {
    final track = _camTrack;
    _camTrack = null;
    await track?.stop();
    await track?.dispose();
    if (mounted) {
      setState(() => _camTesting = false);
    }
  }

  void _toggleCamPreview() {
    if (_camTesting) {
      _stopCamPreview();
    } else {
      _startCamPreview();
    }
  }

  Widget _micMeter() {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        spacing: 10,
        children: [
          Expanded(
            child: SizedBox(
              height: 22,
              child: RepaintBoundary(
                child: CustomPaint(painter: _MeterPainter(_micBars, active: _micTesting)),
              ),
            ),
          ),
          if (_micFailed || _micTesting)
            Text(
              _micFailed ? "Couldn't open that mic" : 'Say something',
              style: PTText.finePrint.copyWith(
                color: _micFailed ? PTColors.danger : PTColors.white(0.5),
              ),
            ),
        ],
      ),
    );
  }

  Widget _outputMeter() {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        spacing: 10,
        children: [
          Expanded(
            child: SizedBox(
              height: 22,
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _MeterPainter(_outputBars, active: _isPlayingTestSound),
                ),
              ),
            ),
          ),
          if (_isPlayingTestSound)
            Text('Playing sound', style: PTText.finePrint.copyWith(color: PTColors.white(0.5))),
        ],
      ),
    );
  }

  Widget _cameraPreview() {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(PTRadius.panel),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            decoration: BoxDecoration(
              color: PTColors.aisle,
              borderRadius: BorderRadius.circular(PTRadius.panel),
              border: Border.all(color: PTColors.rail),
            ),
            child: _camTesting && _camTrack != null
                ? lk.VideoTrackRenderer(_camTrack!, fit: .cover, mirrorMode: .mirror)
                : Center(
                    child: Column(
                      mainAxisSize: .min,
                      children: [
                        Icon(BoothIcons.videocam, size: 28, color: PTColors.white(0.2)),
                        const SizedBox(height: 6),
                        Text(
                          _camFailed
                              ? "Couldn't open camera"
                              : (_videoInputs.isEmpty
                                    ? 'No camera found'
                                    : 'Camera preview paused'),
                          style: PTText.finePrint.copyWith(
                            color: _camFailed ? PTColors.danger : PTColors.white(0.4),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(height: 220, child: Center(child: PTLoader(size: 24)));
    }

    // Short windows (landscape phone, big text) cannot keep both the header
    // and the Save row pinned, so the whole body scrolls as one there.
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < MediaQuery.textScalerOf(context).scale(380);
        final body = Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          children: [
            GlassDialogHeader(
              eyebrow: 'Booth check',
              title: 'Test your mic and camera',
              closeSize: 32,
              onClose: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 14),
            Container(height: 1, color: PTColors.rail),
            _scrollMiddle(
              compact: compact,
              child: Column(
                crossAxisAlignment: .start,
                children: [
                  _deviceSection(
                    icon: BoothIcons.mic,
                    title: 'Microphone',
                    devices: _audioInputs,
                    selectedDevice: _selectedMic,
                    onSelected: (dev) {
                      // A running test follows the newly chosen device.
                      final wasTesting = _micTesting;
                      if (wasTesting) _stopMicTest();
                      setState(() {
                        _selectedMic = dev;
                      });
                      if (wasTesting) _toggleMicTest();
                    },
                    trailingAction: DialogTextButton(
                      label: _micTesting ? 'Stop' : 'Test mic',
                      onPressed: _audioInputs.isEmpty ? null : _toggleMicTest,
                    ),
                    footer: _micMeter(),
                  ),
                  _deviceSection(
                    icon: BoothIcons.volume,
                    title: 'Audio Output',
                    subtitle: 'Does not apply to YouTube mode',
                    devices: _audioOutputs,
                    selectedDevice: _selectedOutput,
                    onSelected: (dev) {
                      setState(() {
                        _selectedOutput = dev;
                      });
                    },
                    trailingAction: DialogTextButton(
                      label: _isPlayingTestSound ? 'Stop' : 'Test sound',
                      onPressed: _audioOutputs.isEmpty
                          ? null
                          : (_isPlayingTestSound ? _stopTestSound : _playTestSound),
                    ),
                    footer: _outputMeter(),
                  ),
                  _deviceSection(
                    icon: BoothIcons.videocam,
                    title: 'Camera',
                    devices: _videoInputs,
                    selectedDevice: _selectedCam,
                    onSelected: (dev) {
                      final wasTesting = _camTesting;
                      setState(() {
                        _selectedCam = dev;
                      });
                      if (wasTesting) {
                        _startCamPreview();
                      }
                    },
                    trailingAction: DialogTextButton(
                      label: _camTesting ? 'Stop camera' : 'Test camera',
                      onPressed: _videoInputs.isEmpty ? null : _toggleCamPreview,
                    ),
                    footer: _cameraPreview(),
                  ),
                ],
              ),
            ),
            Container(height: 1, color: PTColors.rail),
            const SizedBox(height: 16),
            // Hugging the trailing edge while both fit; stacked full-width
            // (Save on top) on a squeezed window, never ellipsized.
            PTButtonBar(
              alignEnd: true,
              spacing: 10,
              buttons: [
                PTButton(
                  maxLines: 2,
                  label: 'Cancel',
                  height: 38,
                  variant: .secondary,
                  expand: false,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                PTButton(
                  maxLines: 2,
                  label: 'Save',
                  height: 38,
                  variant: .primary,
                  expand: false,
                  loading: _saving,
                  onPressed: _saving ? null : _saveAndClose,
                ),
              ],
            ),
          ],
        );
        return compact ? SingleChildScrollView(child: body) : body;
      },
    );
  }

  /// The device list: its own capped scroller between pinned header and
  /// actions, or plain content when the whole body is already scrolling.
  Widget _scrollMiddle({required bool compact, required Widget child}) => compact
      ? child
      : Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 480),
            child: SingleChildScrollView(child: child),
          ),
        );

  Widget _deviceSection({
    required IconData icon,
    required String title,
    String? subtitle,
    required List<lk.MediaDevice> devices,
    required lk.MediaDevice? selectedDevice,
    required ValueChanged<lk.MediaDevice?> onSelected,
    Widget? trailingAction,
    Widget? footer,
  }) {
    final matchingSelected = devices
        .where((d) => d.deviceId == selectedDevice?.deviceId)
        .firstOrNull;

    // Hairline-ruled sections rather than stacked cards.
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: title == 'Camera' ? null : const Border(bottom: BorderSide(color: PTColors.rail)),
      ),
      child: Column(
        crossAxisAlignment: .start,
        children: [
          Row(
            crossAxisAlignment: subtitle != null
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              Padding(
                padding: EdgeInsets.only(top: subtitle != null ? 2 : 0),
                child: Icon(icon, size: 16, color: PTColors.white(0.6)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title.toUpperCase(), style: PTText.label.copyWith(color: PTColors.fg)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: PTText.finePrint.copyWith(color: PTColors.white(0.5), height: 1.25),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailingAction != null) ...[const SizedBox(width: 8), trailingAction],
            ],
          ),
          const SizedBox(height: 10),
          if (devices.isEmpty)
            Text('No devices found', style: PTText.finePrint.copyWith(color: PTColors.white(0.45)))
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(PTRadius.control),
                border: Border.all(color: PTColors.rail),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  dropdownColor: PTColors.menuSurface,
                  icon: Icon(BoothIcons.chevronDown, size: 18, color: PTColors.white(0.6)),
                  value: matchingSelected?.deviceId,
                  items: devices.map((d) {
                    final label = d.label.trim().isEmpty ? 'Default Device' : d.label;
                    return DropdownMenuItem<String>(
                      value: d.deviceId,
                      child: Text(
                        label,
                        style: PTText.body.copyWith(fontSize: 13, color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val == null) return;
                    final chosen = devices.where((d) => d.deviceId == val).firstOrNull;
                    onSelected(chosen);
                  },
                ),
              ),
            ),
          ?footer,
        ],
      ),
    );
  }
}

/// Square segments in a row, lit Cue from the left as the level rises -
/// idle segments stay Rail so the meter reads as an instrument, not a void.
class _MeterPainter extends CustomPainter {
  _MeterPainter(this.bars, {required this.active}) : super(repaint: bars);

  final ValueNotifier<List<double>> bars;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final values = bars.value;
    final level = values.isEmpty ? 0.0 : values.reduce((a, b) => a > b ? a : b);
    const gap = 3.0;
    final w = (size.width - gap * (_kMeterBars - 1)) / _kMeterBars;
    final lit = (level * _kMeterBars).round();
    final on = Paint()..color = PTColors.online;
    final off = Paint()..color = active ? PTColors.rail : PTColors.white(0.06);
    for (var i = 0; i < _kMeterBars; i++) {
      final rect = Rect.fromLTWH(i * (w + gap), 0, w, size.height);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(1.5)),
        i < lit ? on : off,
      );
    }
  }

  @override
  bool shouldRepaint(_MeterPainter old) => old.bars != bars || old.active != active;
}
