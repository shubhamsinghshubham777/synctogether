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
    if (_running == next) {
      // Same type as last time, but the OS may have refused or killed the
      // service since; ask native for the truth and restart if it is gone.
      if (await _nativeRunning()) return;
      trace('background call service vanished; restarting', category: 'av');
      _running = null;
    }
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

  /// Whether the native service really holds its foreground notification.
  /// Assumes yes when the channel cannot answer, so a flaky query never
  /// causes a restart loop.
  Future<bool> _nativeRunning() async {
    try {
      return await _channel.invokeMethod<bool>('isRunning') ?? true;
    } catch (e, s) {
      reportNonFatal(e, s, during: 'querying the background call service');
      return true;
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

/// Reasons the screen is being held awake. The wakelock is one global switch,
/// so independent holders (picture playing, a long upload) must not switch it
/// off under each other: it is on while any reason is held, off when none is.
class ScreenAwake {
  ScreenAwake._();

  static final Set<String> _holds = {};

  /// Swappable for tests; defaults to the real wakelock.
  @visibleForTesting
  static Future<void> Function(bool enable) apply = (enable) => WakelockPlus.toggle(enable: enable);

  @visibleForTesting
  static Set<String> get holds => Set.unmodifiable(_holds);

  @visibleForTesting
  static void reset() => _holds.clear();

  static Future<void> hold(String reason) => _change(() => _holds.add(reason));

  static Future<void> release(String reason) => _change(() => _holds.remove(reason));

  /// Holds or releases [reason] to match [awake].
  static Future<void> set(String reason, bool awake) => awake ? hold(reason) : release(reason);

  static Future<void> _change(bool Function() mutate) async {
    final before = _holds.isNotEmpty;
    final changed = mutate();
    final after = _holds.isNotEmpty;
    // Edges only; an upload's repeated holds must not hammer the platform.
    if (!changed || before == after) return;
    trace(
      'screen wakelock ${after ? 'on' : 'off'}',
      category: 'av',
      data: {'holds': _holds.toList()},
    );
    try {
      await apply(after);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'toggling the screen wakelock');
    }
  }
}

/// Applies [shouldHoldScreenAwake]'s verdict as the 'playback' hold.
/// media_kit_video's `Video` widget only holds a wakelock on web, so native
/// phones must do it here.
Future<void> setScreenAwake(bool awake) => ScreenAwake.set('playback', awake);
