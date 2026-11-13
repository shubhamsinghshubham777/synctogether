import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/diagnostics.dart';

import '../platform.dart';
import '../ui/responsive.dart';
import 'bug_report.dart';
import 'accelerometer_shake_source.dart';
import 'shake_source.dart';

/// Shake your phone, get the bug report (board 86). Phones only: no tablets,
/// no desktop (which has the shortcut and the bar button).
///
/// The shake source (Apple's gesture on iOS, the accelerometer on Android) is
/// subscribed only while all of these hold, so an idle app costs no battery: this is a phone, the setting is on, the app is in the foreground and
/// [attach] has been given the router. A shake is then the same tap as the bug
/// button - a light haptic, and `BugReport.open` takes the screenshot first.
///
/// Three things silence it: [registerBlocker] (the room says "fullscreen video
/// is playing"), a report already open (the guard in `BugReport`), and anything
/// before the app is up (the splash, the login page).
class ShakeToReport with WidgetsBindingObserver {
  ShakeToReport({
    this._prefs,
    ShakeSource Function()? source,
    Duration Function()? clock,
    Future<bool> Function()? phoneProbe,
    bool? touchOverride,
  }) : _source = source ?? defaultSource,
       _clock = clock ?? _stopwatchClock(),
       _phoneProbe = phoneProbe ?? _isPhone,
       _touch = touchOverride;

  static ShakeToReport instance = ShakeToReport();

  static const _kEnabled = 'feedback.shake_enabled';
  static const _kIntro = 'feedback.shake_intro_answered';

  /// The app is mounted this long before a shake can count: the splash
  /// (1.8 s) is an overlay over a live router, and a report taken through it
  /// would photograph the logo.
  static const settle = Duration(milliseconds: 2500);

  /// One shake opens one sheet, however long the shake lasts.
  static const cooldown = Duration(seconds: 2);

  /// iOS asks the system, which already knows what a shake is and costs no
  /// sensor power. Everything else reads the accelerometer. The factories exist
  /// so a test can prove the other one is never built.
  static ShakeSource defaultSource({
    TargetPlatform? platform,
    ShakeSource Function()? native,
    ShakeSource Function()? accelerometer,
  }) {
    return (platform ?? defaultTargetPlatform) == TargetPlatform.iOS
        ? (native ?? NativeShakeSource.new)()
        : (accelerometer ?? AccelerometerShakeSource.new)();
  }

  SharedPreferences? _prefs;
  final ShakeSource Function() _source;
  final Duration Function() _clock;
  final Future<bool> Function() _phoneProbe;
  final bool? _touch;

  final List<bool Function()> _blockers = [];
  StreamSubscription<void>? _sub;
  Duration? _lastShakeAt;
  GoRouter? _router;
  Duration? _firstAttachAt;
  int _attachments = 0;
  bool _foreground = true;
  bool _phone = false;
  bool _observing = false;
  bool _loaded = false;

  /// Whether shake opens a report. On until the user turns it off.
  final ValueNotifier<bool> enabled = ValueNotifier(true);

  /// True once a shake has been used and the user has not yet said whether to
  /// keep it: the host draws the one-time banner. Never set while a report is open.
  final ValueNotifier<bool> introPending = ValueNotifier(false);

  /// Whether this device can shake at all (a phone, with a sensor); the
  /// Profile row only exists when it can.
  final ValueNotifier<bool> available = ValueNotifier(false);

  bool _introAnswered = false;
  bool get introAnswered => _introAnswered;

  bool get _isTouch => _touch ?? isTouchPlatform;
  bool get listening => _sub != null;

  /// Reads the saved setting. Safe to call twice.
  Future<void> load() async {
    if (_loaded) return;
    try {
      _prefs ??= await SharedPreferences.getInstance();
      enabled.value = _prefs?.getBool(_kEnabled) ?? true;
      _introAnswered = _prefs?.getBool(_kIntro) ?? false;
      _loaded = true;
    } catch (e, s) {
      reportNonFatal(e, s, during: 'loading shake setting');
    }
  }

  /// Hands over the router so a shake can find the navigator. Called by the
  /// app root; [detach] undoes it. Remounts (the splash swaps its subtree)
  /// are fine: only the first attach starts the settle clock.
  Future<void> attach(GoRouter router) async {
    _router = router;
    _attachments++;
    _firstAttachAt ??= _clock();
    if (!_isTouch) return;
    if (!_observing) {
      _observing = true;
      WidgetsBinding.instance.addObserver(this);
    }
    await load();
    try {
      _phone = await _phoneProbe();
    } on MissingPluginException {
      // No device-info plugin on this platform or host: not a phone we can
      // shake. Expected, so not a report.
      _phone = false;
    } catch (e, s) {
      reportNonFatal(e, s, during: 'checking phone for shake');
      _phone = false;
    }
    available.value = _phone;
    enabled.removeListener(_sync);
    enabled.addListener(_sync);
    _sync();
  }

  /// Counted: a remount mounts the new host before the old one is disposed, so
  /// the old host's detach must not undo the new host's attach.
  void detach(GoRouter router) {
    if (!identical(_router, router)) return;
    if (_attachments > 0) _attachments--;
    if (_attachments > 0) return;
    _router = null;
    _sync();
  }

  /// Registers "do not react to shakes right now" for something that knows
  /// better than we do, e.g. the room while a film plays fullscreen. Evaluated
  /// when a shake happens, never per frame. Returns the unregister.
  VoidCallback registerBlocker(bool Function() blocked) {
    _blockers.add(blocked);
    return () => _blockers.remove(blocked);
  }

  /// The Profile toggle and the banner's "Turn off".
  Future<void> setEnabled(bool value) async {
    if (enabled.value == value) return;
    enabled.value = value;
    trace('shake to report ${value ? 'on' : 'off'}', category: 'feedback');
    try {
      await (_prefs ??= await SharedPreferences.getInstance()).setBool(_kEnabled, value);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'saving shake setting');
    }
  }

  /// The banner's answer, once ever. "Keep it" leaves the setting alone;
  /// "Turn off" flips it.
  Future<void> answerIntro({required bool keep}) async {
    introPending.value = false;
    _introAnswered = true;
    try {
      await (_prefs ??= await SharedPreferences.getInstance()).setBool(_kIntro, true);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'saving shake intro answer');
    }
    trace('shake intro answered', category: 'feedback', data: {'keep': keep});
    if (!keep) await setEnabled(false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  /// What keeps the sensor off right now, or null when it should be on. Traced
  /// on change only, so the breadcrumbs say which condition failed.
  String? _whyNot() {
    if (!_isTouch) return 'not a touch platform';
    if (!_phone) return 'not a phone';
    if (!enabled.value) return 'turned off';
    if (!_foreground) return 'in the background';
    if (_router == null) return 'no router';
    return null;
  }

  String? _tracedState;

  void _sync() {
    final why = _whyNot();
    final want = why == null;
    final state = want ? 'listening' : 'off: $why';
    if (state != _tracedState) {
      _tracedState = state;
      trace(
        want ? 'shake listening started' : 'shake not listening',
        category: 'feedback',
        data: want ? null : {'why': why},
      );
    }
    if (want && _sub == null) {
      _sub = _source().shakes.listen(
        (_) => unawaited(_onShake()),
        onError: (Object e, StackTrace st) {
          reportNonFatal(e, st, during: 'listening for a shake');
          _stop();
        },
      );
    } else if (!want && _sub != null) {
      _stop();
    }
  }

  void _stop() {
    unawaited(_sub?.cancel());
    _sub = null;
  }

  /// Why a shake would be ignored right now, or null if it may open a report.
  @visibleForTesting
  String? ignoreReason() {
    final router = _router;
    if (router == null) return 'no router';
    final up = _firstAttachAt;
    if (up == null || _clock() - up < settle) return 'starting up';
    if (router.routerDelegate.currentConfiguration.uri.path == '/login') return 'login';
    if (BugReport.isOpen) return 'report open';
    if (_blockers.any((b) => b())) return 'immersive playback';
    return null;
  }

  Future<void> _onShake() async {
    if (ignoreReason() != null) return;
    final last = _lastShakeAt;
    if (last != null && _clock() - last < cooldown) return;
    final ctx = _router?.routerDelegate.navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    _lastShakeAt = _clock();
    unawaited(HapticFeedback.lightImpact());
    trace('shake opened bug report', category: 'feedback');
    await BugReport.open(ctx, source: 'shake');
    if (!_introAnswered) introPending.value = true;
  }

  static Duration Function() _stopwatchClock() {
    final sw = Stopwatch()..start();
    return () => sw.elapsed;
  }

  /// A phone, folded or not. An iPhone Duo's inner display is tablet-sized but
  /// it is still an iPhone, so iOS asks the device, not the window. Android has
  /// no such flag: a small display or a hinge sensor means phone.
  static Future<bool> _isPhone() async {
    final info = DeviceInfoPlugin();
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        final ios = await info.iosInfo;
        return ios.model.toLowerCase().contains('iphone') ||
            ios.utsname.machine.toLowerCase().startsWith('iphone');
      case TargetPlatform.android:
        final android = await info.androidInfo;
        if (android.systemFeatures.contains('android.hardware.sensor.hinge_angle')) return true;
        final view = WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
        if (view == null) return false;
        return (view.physicalSize / view.devicePixelRatio).shortestSide < kTabletMinShortestSide;
      default:
        return false;
    }
  }
}
