import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:synctogether/platform.dart';

/// Touch feedback for the few moments a phone should be felt, never heard.
///
/// The rule: a tap answers the person who made it (their reaction, their
/// play/pause, a copied invite), plus one shared moment - the room starting
/// for everyone once the last person is ready. Other people's reactions,
/// chat and presence never buzz: a phone that twitches through a film is
/// noise. Desktop and web have no haptics, so every call is a no-op there;
/// on iOS and Android the system "haptics off" setting is honoured by the OS.
abstract final class PTHaptics {
  /// Tests flip this to count calls without a platform channel.
  @visibleForTesting
  static void Function(String kind)? debugOnFire;

  static bool get _enabled => !kIsWeb && !isDesktop;

  static void _fire(String kind, Future<void> Function() call) {
    if (debugOnFire != null) {
      debugOnFire!(kind);
      return;
    }
    if (_enabled) call();
  }

  /// The lightest tick: sending a reaction, a picker detent.
  static void selection() => _fire('selection', HapticFeedback.selectionClick);

  /// A confirmed tap of your own: play/pause, a copied invite.
  static void tap() => _fire('tap', HapticFeedback.lightImpact);

  /// The shared moment: everyone is ready and the film starts.
  static void moment() => _fire('moment', HapticFeedback.mediumImpact);
}
