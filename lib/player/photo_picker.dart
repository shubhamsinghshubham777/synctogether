import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:synctogether/diagnostics.dart';
import 'package:synctogether/player/photo_exports.dart';
import 'package:synctogether/rooms/local_media_store.dart';

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
//            is exported once into `Application Support/PhotosPicks` - `.current`
//            representation, so no transcode - because the provider's file is
//            deleted when the callback returns. Not tmp: iOS purges that while
//            the app is closed, which lost the pick before a rejoin. Retention
//            is `PhotoExports` (photo_exports.dart). See `PhotoPickerChannel`
//            in AppDelegate.swift.
//   Android  `MediaStore.ACTION_PICK_IMAGES` (the system photo picker, API 33+
//            and backported to 30+ via Play system updates), falling back to
//            `ACTION_GET_CONTENT` for `video/*`. It hands back a `content://`
//            URI with a temporary grant (it dies with the process). A persistable
//            grant is taken when the provider allows it; otherwise the video is
//            copied into app-private `filesDir/PhotosPicks`. See PhotoPicker.kt.
//
// The result goes through `LocalVideoAccess.adoptPick(origin: photos)`: a path
// under `PhotosPicks` (durable for the room that picked it, so a rejoin reopens
// it) or, on Android when the grant persisted, a content URI. `RecentVideos`
// still declines Photos picks: the export is kept days, not forever. Desktop has no photo library entry; the chooser
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
    unawaited(sweepPhotoExports(playing: path));
    return PhotoPick(path: path, uri: uri, name: (r['name'] as String?) ?? '');
  } on MissingPluginException {
    return null;
  } on PlatformException catch (e, s) {
    reportNonFatal(e, s, during: 'picking a video from Photos');
    return null;
  }
}

/// Applies the Photos-export retention policy against the rooms this device
/// still remembers. At launch and after each pick; never throws.
Future<void> sweepPhotoExports({String? playing}) async {
  if (!photosAvailable) return;
  final remembered = await LocalMediaStore.instance.rememberedPaths();
  await PhotoExports.instance.sweep(referenced: remembered, playing: playing);
}
