import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// System bars for a dark-only app drawn edge-to-edge: transparent bars with
/// light icons, and no contrast scrim - Android 10+ otherwise paints a
/// translucent white one behind 3-button navigation.
///
/// Lives here rather than in `main.dart` because the room restores it when it
/// leaves immersive playback.
const kSystemUiStyle = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: .light, // Android
  statusBarBrightness: .dark, // iOS: dark content behind -> light glyphs
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarDividerColor: Colors.transparent,
  systemNavigationBarIconBrightness: .light,
  systemNavigationBarContrastEnforced: false,
  systemStatusBarContrastEnforced: false,
);
