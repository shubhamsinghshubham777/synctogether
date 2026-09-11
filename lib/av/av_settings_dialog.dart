import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:material_symbols_icons/symbols.dart';
import 'package:media_kit/media_kit.dart';
import 'package:synctogether/av/device_preference_service.dart';
import 'package:synctogether/av/macos_audio_devices.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/loader.dart';
import 'package:synctogether/ui/pt_theme.dart';

Future<void> showAvSettingsDialog(
  BuildContext context, {
  Future<List<lk.MediaDevice>> Function()? enumerateAudioInputs,
  Future<List<lk.MediaDevice>> Function()? enumerateVideoInputs,
  Future<List<lk.MediaDevice>> Function()? enumerateAudioOutputs,
  Player? testPlayer,
  Future<void> Function(lk.MediaDevice? selectedOutput)? onTestSound,
}) {
  return showGlassDialog(
    context: context,
    width: 460,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
    builder: (dialogContext) => _AvSettingsDialogContent(
      enumerateAudioInputs: enumerateAudioInputs,
      enumerateVideoInputs: enumerateVideoInputs,
      enumerateAudioOutputs: enumerateAudioOutputs,
      testPlayer: testPlayer,
      onTestSound: onTestSound,
    ),
  );
}

class _AvSettingsDialogContent extends StatefulWidget {
  const _AvSettingsDialogContent({
    this.enumerateAudioInputs,
    this.enumerateVideoInputs,
    this.enumerateAudioOutputs,
    this.testPlayer,
    this.onTestSound,
  });

  final Future<List<lk.MediaDevice>> Function()? enumerateAudioInputs;
  final Future<List<lk.MediaDevice>> Function()? enumerateVideoInputs;
  final Future<List<lk.MediaDevice>> Function()? enumerateAudioOutputs;
  final Player? testPlayer;
  final Future<void> Function(lk.MediaDevice? selectedOutput)? onTestSound;

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

      final videos = widget.enumerateVideoInputs != null
          ? await widget.enumerateVideoInputs!()
          : await lk.Hardware.instance.videoInputs();

      List<lk.MediaDevice> outputs;
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

  Future<void> _playTestSound() async {
    if (_isPlayingTestSound) return;
    setState(() => _isPlayingTestSound = true);
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
        await Future.delayed(const Duration(seconds: 1));
      }
    } catch (_) {
      // Fallback or silent catch for environments without audio hardware
    } finally {
      if (mounted) setState(() => _isPlayingTestSound = false);
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(height: 220, child: Center(child: PTLoader(size: 24)));
    }

    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      children: [
        Row(
          children: [
            const Icon(Symbols.tune_rounded, size: 22, color: PTColors.textAccent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Audio & Video Settings',
                style: PTText.cardHeading,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            PTIconButton(
              icon: Symbols.close_rounded,
              size: 32,
              iconSize: 18,
              glass: false,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(height: 1, color: PTColors.white(0.08)),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 400),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: .start,
              children: [
                _deviceSection(
                  icon: Symbols.mic_rounded,
                  title: 'Microphone',
                  devices: _audioInputs,
                  selectedDevice: _selectedMic,
                  onSelected: (dev) {
                    setState(() {
                      _selectedMic = dev;
                    });
                  },
                ),
                const SizedBox(height: 14),
                _deviceSection(
                  icon: Symbols.volume_up_rounded,
                  title: 'Audio Output',
                  subtitle: 'Does not apply to YouTube mode',
                  devices: _audioOutputs,
                  selectedDevice: _selectedOutput,
                  onSelected: (dev) {
                    setState(() {
                      _selectedOutput = dev;
                    });
                  },
                  trailingAction: PTIconButton(
                    icon: Symbols.volume_up_rounded,
                    tooltip: _isPlayingTestSound ? 'Playing test audio...' : 'Test output',
                    size: 32,
                    iconSize: 18,
                    glass: true,
                    onPressed: _isPlayingTestSound ? null : _playTestSound,
                  ),
                ),
                const SizedBox(height: 14),
                _deviceSection(
                  icon: Symbols.videocam_rounded,
                  title: 'Camera',
                  devices: _videoInputs,
                  selectedDevice: _selectedCam,
                  onSelected: (dev) {
                    setState(() {
                      _selectedCam = dev;
                    });
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: .end,
          children: [
            PTButton(
              label: 'Cancel',
              height: 38,
              variant: .secondary,
              expand: false,
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 10),
            PTButton(
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
  }

  Widget _deviceSection({
    required IconData icon,
    required String title,
    String? subtitle,
    required List<lk.MediaDevice> devices,
    required lk.MediaDevice? selectedDevice,
    required ValueChanged<lk.MediaDevice?> onSelected,
    Widget? trailingAction,
  }) {
    final matchingSelected = devices
        .where((d) => d.deviceId == selectedDevice?.deviceId)
        .firstOrNull;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PTColors.white(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PTColors.white(0.07)),
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
                child: Icon(icon, size: 18, color: PTColors.textAccent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: PTText.body.copyWith(fontWeight: .w600, color: Colors.white),
                    ),
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
                color: PTColors.white(0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: PTColors.white(0.1)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  dropdownColor: const Color(0xFF1B172C),
                  icon: const Icon(
                    Symbols.keyboard_arrow_down_rounded,
                    size: 18,
                    color: PTColors.textAccent,
                  ),
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
        ],
      ),
    );
  }
}
