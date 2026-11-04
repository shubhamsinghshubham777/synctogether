import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:synctogether/diagnostics.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps a room's call alive while the app is backgrounded on a phone.
///
/// Android kills a backgrounded process's microphone and camera unless a
/// foreground service of the matching type is running, so the room starts one
/// (`CallForegroundService`, native) for as long as it holds a LiveKit
/// session. iOS needs no service: `UIBackgroundModes: audio` in Info.plist
/// keeps the audio session - playback and capture - running.
///
/// Every method is a no-op off Android, and never throws: a failure to start
/// the service must not take the room down with it.
class BackgroundCall {
  BackgroundCall({MethodChannel? channel, bool Function()? supported})
    : _channel = channel ?? const MethodChannel('app.synctogether/background_call'),
      _supported = supported ?? (() => !kIsWeb && defaultTargetPlatform == .android);

  final MethodChannel _channel;
  final bool Function() _supported;

  /// What the native service was last told, so [update] only crosses the
  /// channel when the service type actually has to change.
  ({bool mic, bool cam})? _running;

  bool get isRunning => _running != null;

  /// Starts the service, or re-types it when [mic]/[cam] changed. The service
  /// always declares media playback; microphone and camera are added only
  /// while they are really capturing, because Android 14 refuses a service
  /// type whose runtime permission is not held.
  Future<void> update({required bool mic, required bool cam, required String title}) async {
    if (!_supported()) return;
    final next = (mic: mic, cam: cam);
    if (_running == next) return;
    final wasRunning = isRunning;
    _running = next;
    try {
      await _channel.invokeMethod<void>('start', {'mic': mic, 'cam': cam, 'title': title});
      if (!wasRunning) {
        trace('background call service started', category: 'av', data: {'mic': mic, 'cam': cam});
      }
    } catch (e, s) {
      // Forget the attempt so the next change retries.
      _running = null;
      reportNonFatal(e, s, during: 'starting the background call service');
    }
  }

  Future<void> stop() async {
    if (!_supported() || _running == null) return;
    _running = null;
    try {
      await _channel.invokeMethod<void>('stop');
      trace('background call service stopped', category: 'av');
    } catch (e, s) {
      reportNonFatal(e, s, during: 'stopping the background call service');
    }
  }
}

/// Whether the screen should be held awake: a phone, in a room, with picture
/// actually playing. A paused room lets the display sleep as normal.
bool shouldHoldScreenAwake({required bool mobile, required bool inRoom, required bool playing}) =>
    mobile && inRoom && playing;

/// Applies [shouldHoldScreenAwake]'s verdict. media_kit_video's `Video`
/// widget only holds a wakelock on web, so native phones must do it here.
Future<void> setScreenAwake(bool awake) async {
  try {
    await WakelockPlus.toggle(enable: awake);
  } catch (e, s) {
    reportNonFatal(e, s, during: 'toggling the screen wakelock');
  }
}
