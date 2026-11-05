import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:synctogether/diagnostics.dart';

// "From Photos" (board 47): the system photo picker, filtered to videos, with
// NO permission prompt and NO new package.
//
// DECISION. `image_picker` was the obvious dependency and was rejected: its iOS
// half calls `PHPhotoLibrary` authorization APIs, so App Store Connect demands
// an `NSPhotoLibraryUsageDescription` string in Info.plist even if the app
// never asks (the README says so), and the brief was "no new permission or
// usage string". What the picker itself needs is smaller than the package:
//
//   iOS      `PHPickerViewController` (iOS 14+, out-of-process, so the app is
//            never granted library access and never prompts). The chosen movie
//            is exported once into a temp folder - `.current` representation,
//            so no transcode - because the provider's file is deleted when the
//            callback returns. See `PhotoPickerChannel` in AppDelegate.swift.
//   Android  `MediaStore.ACTION_PICK_IMAGES` (the system photo picker, API 33+
//            and backported to 30+ via Play system updates), falling back to
//            `ACTION_GET_CONTENT` for `video/*`. It hands back a `content://`
//            URI with a temporary grant, no copy. See MainActivity.kt.
//
// The result goes through `LocalVideoAccess.adoptPick(origin: photos)`: on iOS
// it is a path under tmp (so `temporary`), on Android a content URI that is not
// persistable - either way `RecentVideos.record` declines it, which is the
// policy for Photos picks. Desktop has no photo library entry; the chooser
// never shows the row there.

/// What the photo picker handed back: a path (iOS temp export) or a
/// `content://` URI (Android), plus the display name.
class PhotoPick {
  const PhotoPick({this.path, this.uri, required this.name});

  final String? path;
  final String? uri;
  final String name;
}

typedef PickPhotoVideo = Future<PhotoPick?> Function();

/// Whether this build has a photo library to offer (the touch platforms).
bool get photosAvailable =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android);

const _channel = MethodChannel('app.synctogether/photo_picker');

/// Opens the system photo picker for one video. Null when the user cancelled
/// (or the native side is older than this code).
Future<PhotoPick?> pickPhotoVideo() async {
  if (kIsWeb || !(Platform.isIOS || Platform.isAndroid)) return null;
  try {
    final r = await _channel.invokeMapMethod<String, Object?>('pickVideo');
    if (r == null) return null;
    final path = r['path'] as String?;
    final uri = r['uri'] as String?;
    if (path == null && uri == null) return null;
    return PhotoPick(path: path, uri: uri, name: (r['name'] as String?) ?? '');
  } on MissingPluginException {
    return null;
  } on PlatformException catch (e, s) {
    reportNonFatal(e, s, during: 'picking a video from Photos');
    return null;
  }
}
