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
    width: 380,
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

  @override
  void initState() {
    super.initState();
    _startCamera();
  }

  Future<void> _startCamera() async {
    try {
      await _renderer.initialize();
      final stream = await rtc.navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': {'facingMode': 'user', 'width': 720, 'height': 720},
      });
      if (!mounted) {
        for (final track in stream.getTracks()) {
          track.stop();
        }
        await stream.dispose();
        await _renderer.dispose();
        return;
      }
      _stream = stream;
      _renderer.srcObject = stream;
      setState(() {
        _initializing = false;
        _error = null;
      });
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

  Future<void> _capturePhoto() async {
    final stream = _stream;
    if (stream == null || _capturing) return;
    final videoTracks = stream.getVideoTracks();
    if (videoTracks.isEmpty) return;

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
        Center(
          child: Container(
            width: 260,
            height: 260,
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
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: PTColors.white(0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
            ),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: PTText.finePrint.copyWith(color: Colors.redAccent, height: 1.4),
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
