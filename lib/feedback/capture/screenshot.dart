import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:synctogether/diagnostics.dart';
import 'package:synctogether/mock/store_capture.dart' show storeCaptureBoundaryKey;

const kScreenshotMaxBytes = 1500000;

/// PNG of the app window via the root RepaintBoundary (the same one the store
/// screenshots use). Starts at up to 2x and steps the pixel ratio down until the
/// file fits [maxBytes]. Null when there is nothing to capture.
///
/// Video textures (media_kit) can come out black; that is a known limit and the
/// summary says so.
Future<Uint8List?> captureAppScreenshot({int maxBytes = kScreenshotMaxBytes}) async {
  final boundary = storeCaptureBoundaryKey.currentContext?.findRenderObject();
  if (boundary is! RenderRepaintBoundary) return null;
  final dpr = ui.PlatformDispatcher.instance.views.isEmpty
      ? 1.0
      : ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
  Future<Uint8List?> encode(double ratio) async {
    final image = await boundary.toImage(pixelRatio: ratio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  try {
    return await fitScreenshot(encode, startRatio: dpr.clamp(1.0, 2.0), maxBytes: maxBytes);
  } catch (e, s) {
    reportNonFatal(e, s, during: 'capturing a bug report screenshot');
    return null;
  }
}

/// The pixel-ratio ladder, split out so the size cap is testable without a
/// render tree. Returns the first encoding within [maxBytes], else the smallest
/// attempt is dropped (null) rather than uploading something huge.
Future<Uint8List?> fitScreenshot(
  Future<Uint8List?> Function(double ratio) encode, {
  required double startRatio,
  required int maxBytes,
}) async {
  for (final ratio in {startRatio, 1.0, 0.75, 0.5}) {
    if (ratio > startRatio) continue;
    final bytes = await encode(ratio);
    if (bytes == null) return null;
    if (bytes.length <= maxBytes) return bytes;
  }
  return null;
}
