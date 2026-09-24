import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:material_symbols_icons/symbols.dart';
import 'package:synctogether/diagnostics.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/loader.dart';
import 'package:synctogether/ui/pt_theme.dart';

/// Opens a camera dialog that renders a live webcam viewfinder and captures
/// a photo frame, returning the raw image bytes (PNG) or null on cancellation.
Future<Uint8List?> showCameraCaptureDialog(BuildContext context) {
  return showGlassDialog<Uint8List>(
    context: context,
    width: 400,
    padding: const EdgeInsets.all(24),
    builder: (dialogContext) => const CameraCaptureDialog(),
  );
}

class CameraCaptureDialog extends StatefulWidget {
  const CameraCaptureDialog({super.key});

  @override
  State<CameraCaptureDialog> createState() => _CameraCaptureDialogState();
}

class _CameraCaptureDialogState extends State<CameraCaptureDialog> {
  final _renderer = rtc.RTCVideoRenderer();
  rtc.MediaStream? _stream;
  bool _initializing = true;
  bool _capturing = false;
  String? _error;
  List<rtc.MediaDeviceInfo> _cameras = const [];
  String? _selectedCameraId;

  @override
  void initState() {
    super.initState();
    _initAndStart();
  }

  Future<void> _initAndStart() async {
    try {
      await _renderer.initialize();
      await _startCamera();
    } catch (e, s) {
      reportNonFatal(e, s, during: 'initializing renderer for camera capture');
      if (mounted) {
        setState(() {
          _initializing = false;
          _error = 'Could not initialize video renderer.';
        });
      }
    }
  }

  Future<void> _stopStream() async {
    final stream = _stream;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        track.stop();
      }
      await stream.dispose();
      _stream = null;
    }
  }

  Future<void> _startCamera([String? targetDeviceId]) async {
    try {
      await _stopStream();

      final Map<String, dynamic> videoConstraints = {'width': 720, 'height': 720};
      if (targetDeviceId != null && targetDeviceId.isNotEmpty) {
        // macOS and Web accept 'deviceId' directly
        videoConstraints['deviceId'] = targetDeviceId;
        // Windows WebRTC C++ (DirectShow/Media Foundation) queries 'sourceId' inside 'optional'
        videoConstraints['optional'] = [
          {'sourceId': targetDeviceId},
        ];
      } else {
        videoConstraints['facingMode'] = 'user';
      }

      final stream = await rtc.navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': videoConstraints,
      });

      if (!mounted) {
        for (final track in stream.getTracks()) {
          track.stop();
        }
        await stream.dispose();
        return;
      }

      if (stream.getVideoTracks().isEmpty) {
        for (final track in stream.getTracks()) {
          track.stop();
        }
        await stream.dispose();
        if (mounted) {
          setState(() {
            _initializing = false;
            _error =
                'No camera device detected on this system. You can choose an image file instead.';
          });
        }
        return;
      }

      _stream = stream;
      _renderer.srcObject = stream;

      // Enumerate camera devices after permission is granted
      List<rtc.MediaDeviceInfo> videoDevices = const [];
      try {
        final devices = await rtc.navigator.mediaDevices.enumerateDevices();
        videoDevices = devices.where((d) => d.kind == 'videoinput').toList();
      } catch (e, s) {
        reportNonFatal(e, s, during: 'enumerating video input devices');
      }

      String? activeId = targetDeviceId;
      if (activeId == null || !videoDevices.any((d) => d.deviceId == activeId)) {
        activeId = videoDevices.firstOrNull?.deviceId;
      }

      if (mounted) {
        setState(() {
          _cameras = videoDevices;
          _selectedCameraId = activeId;
          _initializing = false;
          _error = null;
        });
      }
    } catch (e, s) {
      reportNonFatal(e, s, during: 'starting camera for profile photo');
      if (mounted) {
        setState(() {
          _initializing = false;
          _error =
              'Could not access camera. Please ensure camera permissions are granted in System Settings.';
        });
      }
    }
  }

  Future<void> _onCameraChanged(String? newDeviceId) async {
    if (newDeviceId == null || newDeviceId == _selectedCameraId || _capturing) return;
    setState(() {
      _initializing = true;
      _selectedCameraId = newDeviceId;
    });
    await _startCamera(newDeviceId);
  }

  Future<void> _capturePhoto() async {
    final stream = _stream;
    if (stream == null || _capturing) return;
    final videoTracks = stream.getVideoTracks();
    if (videoTracks.isEmpty) {
      if (mounted) {
        setState(() {
          _error = 'No active camera feed to capture from.';
        });
      }
      return;
    }

    setState(() => _capturing = true);
    try {
      final track = videoTracks.first;
      final byteBuffer = await track.captureFrame();
      final bytes = byteBuffer.asUint8List();
      if (mounted) {
        Navigator.of(context).pop(bytes);
      }
    } catch (e, s) {
      reportNonFatal(e, s, during: 'capturing frame from camera');
      if (mounted) {
        setState(() {
          _capturing = false;
          _error = "Couldn't capture photo from camera. Try again or pick a file.";
        });
      }
    }
  }

  @override
  void dispose() {
    final stream = _stream;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        track.stop();
      }
      stream.dispose();
    }
    _renderer.dispose();
    super.dispose();
  }

  // The preview is a circle, so one side fixes both: 250, or less when the
  // dialog is narrower than that (a 320 phone leaves ~248).
  static const double _kPreviewSize = 250;

  Widget _previewCircle(double size) {
    return Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: .circle,
          color: PTColors.dialogGlassBase,
          border: Border.all(color: PTColors.primary.withValues(alpha: 0.4), width: 3),
          boxShadow: [
            BoxShadow(
              color: PTColors.primary.withValues(alpha: 0.2),
              blurRadius: 24,
              spreadRadius: 2,
            ),
          ],
        ),
        child: ClipOval(child: _buildCameraPreview()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: [
        Row(
          mainAxisAlignment: .spaceBetween,
          children: [
            Text('Take Profile Photo', style: PTText.cardHeading.copyWith(fontSize: 17)),
            PTIconButton(
              icon: Symbols.close_rounded,
              size: 32,
              iconSize: 18,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) => _previewCircle(
            constraints.maxWidth < _kPreviewSize ? constraints.maxWidth : _kPreviewSize,
          ),
        ),
        if (_cameras.isNotEmpty) ...[const SizedBox(height: 16), _buildCameraSelector()],
        if (_error != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: PTColors.white(0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: PTColors.dangerBorder.withValues(alpha: 0.3)),
            ),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: PTText.finePrint.copyWith(color: PTColors.dangerBorder, height: 1.4),
            ),
          ),
        ],
        const SizedBox(height: 24),
        Row(
          spacing: 12,
          children: [
            Expanded(
              child: PTButton(
                label: 'Cancel',
                variant: .secondary,
                height: 44,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            Expanded(
              child: PTButton(
                label: 'Capture',
                icon: Symbols.photo_camera_rounded,
                variant: .primary,
                height: 44,
                loading: _capturing,
                onPressed: (_initializing || _error != null) ? null : _capturePhoto,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCameraSelector() {
    final currentId = _selectedCameraId ?? _cameras.firstOrNull?.deviceId;
    final hasMatch = _cameras.any((c) => c.deviceId == currentId);
    final value = hasMatch ? currentId : _cameras.firstOrNull?.deviceId;

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: PTColors.white(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: PTColors.white(0.1)),
      ),
      child: Row(
        children: [
          const Icon(Symbols.videocam_rounded, size: 18, color: PTColors.textAccent),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: value,
                dropdownColor: PTColors.menuSurface,
                icon: const Icon(
                  Symbols.keyboard_arrow_down_rounded,
                  size: 18,
                  color: PTColors.textAccent,
                ),
                style: PTText.body.copyWith(fontSize: 13, color: Colors.white),
                items: [
                  for (int i = 0; i < _cameras.length; i++)
                    DropdownMenuItem<String>(
                      value: _cameras[i].deviceId,
                      child: Text(
                        _cameras[i].label.trim().isNotEmpty ? _cameras[i].label : 'Camera ${i + 1}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _capturing || _initializing || _cameras.length <= 1
                    ? null
                    : _onCameraChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (_initializing) {
      return const Center(child: PTLoader(size: 28));
    }
    if (_error != null) {
      return Center(
        child: Icon(Symbols.videocam_off_rounded, size: 48, color: PTColors.white(0.4)),
      );
    }
    return rtc.RTCVideoView(
      _renderer,
      mirror: true,
      objectFit: rtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
    );
  }
}
