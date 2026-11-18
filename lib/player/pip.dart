import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../diagnostics.dart';

/// What this device says about picture-in-picture (board 96, frames A and B).
class PipSupport {
  const PipSupport({this.supported = false, this.enabled = false});

  /// The OS and device offer it at all (Android 8+ with the feature). When
  /// false the PiP key is hidden, not disabled.
  final bool supported;

  /// The person has not switched it off for this app in system settings.
  final bool enabled;

  static const none = PipSupport();
}

/// A button on the small window.
enum PipAction { playPause, back }

/// Picture-in-picture for the room. Native side: `Pip.kt` (channel
/// `app.synctogether/pip`). Android only for now: elsewhere every call is a
/// quiet no-op and [support] says "not supported", so nothing is promised
/// where it does not exist.
class PictureInPicture {
  PictureInPicture({MethodChannel? channel, bool Function()? platformOk})
    : _channel = channel ?? const MethodChannel('app.synctogether/pip'),
      _platformOk = platformOk ?? (() => !kIsWeb && defaultTargetPlatform == .android);

  static PictureInPicture instance = PictureInPicture();

  final MethodChannel _channel;
  final bool Function() _platformOk;

  /// Whether the room is shown in the small window right now.
  final ValueNotifier<bool> inPip = ValueNotifier(false);

  final _actions = StreamController<PipAction>.broadcast();
  Stream<PipAction> get actions => _actions.stream;

  bool _listening = false;
  ({bool armed, int w, int h, bool playing})? _sent;

  bool get platformSupported => _platformOk();

  void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'event') return;
      final m = Map<String, Object?>.from(call.arguments as Map);
      switch (m['type']) {
        case 'mode':
          final now = m['inPip'] as bool? ?? false;
          if (now != inPip.value) {
            trace('picture-in-picture ${now ? 'entered' : 'left'}', category: 'ui');
          }
          inPip.value = now;
        case 'action':
          final a = switch (m['id']) {
            'playPause' => PipAction.playPause,
            'back' => PipAction.back,
            _ => null,
          };
          if (a != null) _actions.add(a);
      }
    });
  }

  /// Asked fresh each time: the person can switch it off in Settings while the
  /// room is open.
  Future<PipSupport> support() async {
    if (!_platformOk()) return PipSupport.none;
    _listen();
    try {
      final m = await _channel.invokeMethod<Map>('support');
      return PipSupport(
        supported: m?['supported'] as bool? ?? false,
        enabled: m?['enabled'] as bool? ?? false,
      );
    } on MissingPluginException {
      return PipSupport.none;
    } catch (e, s) {
      reportNonFatal(e, s, during: 'asking about picture-in-picture');
      return PipSupport.none;
    }
  }

  /// Arms (or disarms) entering when the app is left, and sets what the small
  /// window shows: its shape and the play/pause key. Only crosses the channel
  /// when something changed.
  Future<void> configure({
    required bool armed,
    required int w,
    required int h,
    required bool playing,
  }) async {
    if (!_platformOk()) return;
    final next = (armed: armed, w: w, h: h, playing: playing);
    if (_sent == next) return;
    _sent = next;
    _listen();
    try {
      await _channel.invokeMethod<void>('configure', {
        'armed': armed,
        'w': w,
        'h': h,
        'playing': playing,
      });
    } on MissingPluginException {
      // No native side: nothing to arm.
    } catch (e, s) {
      _sent = null;
      reportNonFatal(e, s, during: 'configuring picture-in-picture');
    }
  }

  /// Go into the small window now (the PiP key). False when the OS refused.
  Future<bool> enter() async {
    if (!_platformOk()) return false;
    _listen();
    try {
      final ok = await _channel.invokeMethod<bool>('enter') ?? false;
      trace('picture-in-picture requested', category: 'ui', data: {'entered': ok});
      return ok;
    } on MissingPluginException {
      return false;
    } catch (e, s) {
      reportNonFatal(e, s, during: 'entering picture-in-picture');
      return false;
    }
  }

  /// Dismisses the small window (the room ended, or the person was removed).
  Future<void> close() async {
    if (!_platformOk()) return;
    try {
      await _channel.invokeMethod<void>('close');
    } catch (_) {}
  }

  /// The per-app picture-in-picture page in system settings.
  Future<bool> openSettings() async {
    if (!_platformOk()) return false;
    try {
      return await _channel.invokeMethod<bool>('openSettings') ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// Whether leaving the app should shrink the room into the small window: this
/// device offers it, the person left it on, and there is a film to show (an
/// empty window helps nobody - board 96, frame C).
bool pipArmed({required PipSupport support, required bool hasFilm, required bool inRoom}) =>
    support.supported && support.enabled && hasFilm && inRoom;

/// The two words the small window can afford, or null when the picture says it
/// all. In the order the room would trouble the person with them: a room that
/// is gone, then a lost connection, then a pause (board 96 frames D to G).
({String title, String? subtitle})? pipNotice({
  required bool connected,
  required bool playing,
  required String? evicted,
  String? pausedBy,
}) {
  if (evicted != null) {
    final removed = evicted == 'kicked' || evicted == 'banned';
    return removed
        ? (title: 'You were removed', subtitle: 'Tap to see why')
        : (title: 'The room ended', subtitle: 'Tap to return');
  }
  if (!connected) return (title: 'Reconnecting…', subtitle: 'The picture will catch up');
  if (!playing) {
    return (title: 'Paused', subtitle: pausedBy == null ? null : '$pausedBy paused the film');
  }
  return null;
}
