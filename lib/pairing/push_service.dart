import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart'
    show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../analytics.dart';
import '../diagnostics.dart';
import '../env.dart';
import 'pair_links.dart';

enum PushPermission {
  /// Never asked, or the platform will not say yet.
  unknown,
  granted,
  denied,

  /// This build or this machine cannot receive push at all (a self-hosted fork
  /// with no credentials, an unpackaged Windows run, a browser). The UI then
  /// offers nothing rather than a switch that cannot work.
  unsupported,
}

/// What a device hands us to be reached at.
@immutable
class PushToken {
  const PushToken({required this.platform, required this.token, this.environment = 'production'});

  /// `ios`, `macos`, `android` or `windows`.
  final String platform;
  final String token;

  /// APNs has a sandbox gateway a debug build's token only works on.
  final String environment;
}

/// A push that arrived while the app was open and that the app presents itself
/// (as a banner) instead of leaving to the system.
@immutable
class ForegroundPush {
  const ForegroundPush({required this.kind, required this.title, required this.body, this.route});

  final String kind;
  final String title;
  final String body;
  final String? route;
}

/// The native side of push, behind an interface so everything above it is
/// testable with no device. One implementation talks to a method channel that
/// every platform's runner answers (APNs on iOS and macOS, FCM on Android, WNS
/// on Windows); a test brings its own.
abstract class PushBridge {
  /// Hands the native side what it needs before anything else (Android's
  /// Firebase options). Null options mean "this build has no push".
  Future<void> configure(Map<String, String>? firebase);

  Future<PushPermission> permission();

  /// Asks the OS. This is the one call that shows a system prompt, so it is only
  /// ever made because a person just turned something on.
  Future<PushPermission> request();

  Future<PushToken?> token();
  Stream<PushToken> get tokenChanges;

  /// Routes carried by notifications the person tapped while the app was alive.
  Stream<String?> get taps;

  /// The route of the notification whose tap launched the app, if any.
  Future<String?> launchRoute();

  Future<void> openSettings();

  /// Pushes of the kinds the app shows itself while it is in front. The native
  /// side suppresses the system banner for these and hands them here instead.
  Stream<ForegroundPush> get foreground;

  /// Whether the Android "Rooms" channel has been silenced in system settings
  /// (always false elsewhere: only Android lets a person silence one kind).
  Future<bool> roomsChannelSilenced();

  /// Opens that channel's own page in system settings (Android; elsewhere the
  /// app's notification page).
  Future<void> openRoomsChannelSettings();
}

class ChannelPushBridge implements PushBridge {
  ChannelPushBridge() {
    _channel.setMethodCallHandler(_fromNative);
  }

  static const _channel = MethodChannel('app.synctogether/push');
  final _tokens = StreamController<PushToken>.broadcast();
  final _taps = StreamController<String?>.broadcast();
  final _foreground = StreamController<ForegroundPush>.broadcast();

  String get _platform => switch (defaultTargetPlatform) {
    TargetPlatform.iOS => 'ios',
    TargetPlatform.macOS => 'macos',
    TargetPlatform.android => 'android',
    TargetPlatform.windows => 'windows',
    _ => 'unsupported',
  };

  Future<dynamic> _fromNative(MethodCall call) async {
    switch (call.method) {
      case 'token':
        final m = (call.arguments as Map).cast<String, dynamic>();
        _tokens.add(
          PushToken(
            platform: _platform,
            token: m['token'] as String,
            environment: m['environment'] as String? ?? 'production',
          ),
        );
      case 'tap':
        _taps.add((call.arguments as Map?)?['route'] as String?);
      case 'foreground':
        final m = (call.arguments as Map).cast<String, dynamic>();
        _foreground.add(
          ForegroundPush(
            kind: m['kind'] as String? ?? '',
            title: m['title'] as String? ?? '',
            body: m['body'] as String? ?? '',
            route: m['route'] as String?,
          ),
        );
    }
  }

  Future<T?> _call<T>(String method, [Object? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<void> configure(Map<String, String>? firebase) =>
      _call<void>('configure', {'firebase': firebase});

  PushPermission _parse(String? v) => switch (v) {
    'granted' => PushPermission.granted,
    'denied' => PushPermission.denied,
    'unknown' => PushPermission.unknown,
    _ => PushPermission.unsupported,
  };

  @override
  Future<PushPermission> permission() async => _parse(await _call<String>('permission'));

  @override
  Future<PushPermission> request() async => _parse(await _call<String>('request'));

  @override
  Future<PushToken?> token() async {
    final m = await _call<Map>('token');
    if (m == null || m['token'] == null) return null;
    return PushToken(
      platform: _platform,
      token: m['token'] as String,
      environment: m['environment'] as String? ?? 'production',
    );
  }

  @override
  Stream<PushToken> get tokenChanges => _tokens.stream;

  @override
  Stream<String?> get taps => _taps.stream;

  @override
  Future<String?> launchRoute() => _call<String>('launchRoute');

  @override
  Future<void> openSettings() => _call<void>('openSettings');

  @override
  Stream<ForegroundPush> get foreground => _foreground.stream;

  @override
  Future<bool> roomsChannelSilenced() async => await _call<bool>('roomsChannelSilenced') ?? false;

  @override
  Future<void> openRoomsChannelSettings() async {
    try {
      await _channel.invokeMethod<void>('openRoomsChannelSettings');
    } on MissingPluginException {
      // Only Android has per-channel pages; elsewhere the app's own is the nearest.
      await openSettings();
    }
  }
}

/// Registers a device with the server. Injected so tests need no Supabase.
typedef PushRegistrar = Future<void> Function(PushToken token);
typedef PushUnregistrar = Future<void> Function(String token);

Future<void> _registerWithSupabase(PushToken t) => Supabase.instance.client.rpc(
  'register_push_token',
  params: {'p_platform': t.platform, 'p_token': t.token, 'p_environment': t.environment},
);

Future<void> _unregisterWithSupabase(String token) =>
    Supabase.instance.client.rpc('unregister_push_token', params: {'p_token': token});

/// Push notifications, end to end on the device: ask only when a person turned
/// something on, keep the server's copy of this device's token fresh, and hand
/// taps to the app.
///
/// It never prompts on its own. [start] only reads the permission and, if it was
/// already granted, registers - so a person who never turns anything on is never
/// asked, and the prompt arrives at the moment its reason is obvious.
class PushService extends ChangeNotifier {
  PushService({this._bridge, PushRegistrar? register, PushUnregistrar? unregister})
    : _register = register ?? _registerWithSupabase,
      _unregister = unregister ?? _unregisterWithSupabase;

  static PushService instance = PushService();

  PushBridge? _bridge;
  PushBridge get _b => _bridge ??= ChannelPushBridge();
  final PushRegistrar _register;
  final PushUnregistrar _unregister;

  PushPermission _permission = PushPermission.unknown;
  PushPermission get permission => _permission;

  /// Whether push can work at all here, so the UI can leave the switches out.
  bool get supported => _permission != PushPermission.unsupported;

  bool get enabled => _permission == PushPermission.granted;

  String? _registeredToken;
  bool _started = false;
  StreamSubscription<PushToken>? _tokenSub;
  StreamSubscription<String?>? _tapSub;
  final _taps = StreamController<PushTarget?>.broadcast();
  StreamSubscription<ForegroundPush>? _foregroundSub;
  final _foreground = StreamController<ForegroundPush>.broadcast();

  /// Pushes the app shows itself while it is open (someone took a seat), so the
  /// system banner and ours never both appear.
  Stream<ForegroundPush> get foreground => _foreground.stream;

  bool _roomsSilenced = false;

  /// The Android "Rooms" channel is set to silent in system settings.
  bool get roomsSilenced => _roomsSilenced;

  /// What a tapped notification means. `null` is a tap on something we no longer
  /// recognise, which still opens the app to the lobby.
  Stream<PushTarget?> get taps => _taps.stream;

  /// The target of the notification that launched the app, once.
  Future<PushTarget?> takeLaunchTarget() async {
    try {
      return pushTargetForRoute(await _b.launchRoute());
    } catch (_) {
      return null;
    }
  }

  /// Wires the bridge and registers an already-permitted device. Safe to call
  /// again; only the first does anything.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      await _b.configure(Env.firebaseOptions);
      _permission = await _b.permission();
      _tapSub = _b.taps.listen((route) => _taps.add(pushTargetForRoute(route)));
      _tokenSub = _b.tokenChanges.listen((t) => unawaited(_send(t)));
      _foregroundSub = _b.foreground.listen(_foreground.add);
      _roomsSilenced = await _b.roomsChannelSilenced();
      _watchFocus();
      notifyListeners();
      if (enabled) await _registerCurrent();
    } catch (e, s) {
      _started = false;
      reportNonFatal(e, s, during: 'starting push');
    }
  }

  _FocusWatcher? _focus;

  /// Re-read the permission whenever the app comes back to the front. A person
  /// who switches to System Settings (or the phone's Settings) to allow
  /// notifications returns to an app that would otherwise keep offering to turn
  /// them on until they tapped it again.
  void _watchFocus() {
    if (_focus != null) return;
    try {
      _focus = _FocusWatcher(() => unawaited(refreshPermission()));
      WidgetsBinding.instance.addObserver(_focus!);
    } catch (_) {
      // No binding (a plain unit test): nothing to watch.
      _focus = null;
    }
  }

  /// Look at the permission again and act on a change: newly allowed registers
  /// this device at once, newly refused updates every switch that offers it.
  Future<void> refreshPermission() async {
    if (!_started) return;
    try {
      final silenced = await _b.roomsChannelSilenced();
      if (silenced != _roomsSilenced) {
        _roomsSilenced = silenced;
        notifyListeners();
      }
      final latest = await _b.permission();
      if (latest == _permission) return;
      final before = _permission;
      _permission = latest;
      trace(
        'push permission changed',
        category: 'room',
        data: {'from': before.name, 'to': latest.name},
      );
      notifyListeners();
      if (enabled) await _registerCurrent();
    } catch (e, s) {
      reportNonFatal(e, s, during: 'refreshing the push permission');
    }
  }

  /// Called on every sign-in: starts on first use, and on a later sign-in
  /// (another account on the same device) registers this device for the new
  /// account if it is already permitted. Never prompts.
  Future<void> onSignedIn() async {
    await start();
    if (enabled && _registeredToken == null) await _registerCurrent();
  }

  /// A person turned a notification on: ask the OS now, and register if they
  /// agree. Returns the resulting permission so the caller can explain a "no".
  Future<PushPermission> enable() async {
    try {
      await start();
      if (_permission == PushPermission.unsupported) return _permission;
      _permission = await _b.request();
      notifyListeners();
      if (enabled) {
        Analytics.instance.track('push_enabled', {'platform': defaultTargetPlatform.name});
        await _registerCurrent();
      }
    } catch (e, s) {
      reportNonFatal(e, s, during: 'turning push on');
    }
    return _permission;
  }

  Future<void> openSettings() => _b.openSettings();

  Future<void> openRoomsChannelSettings() => _b.openRoomsChannelSettings();

  /// A device that is allowed but never produced a token (no Google services, a
  /// flaky connection at first launch). The settings screen offers a retry.
  bool get registrationFailed => enabled && _registeredToken == null && _started;

  /// Asks for a fresh token and registers it. Returns whether one is on file now.
  Future<bool> retryRegistration() async {
    try {
      await _registerCurrent();
    } catch (e, s) {
      reportNonFatal(e, s, during: 'retrying push registration');
    }
    notifyListeners();
    return _registeredToken != null;
  }

  Future<void> _registerCurrent() async {
    final token = await _b.token();
    if (token != null) await _send(token);
  }

  Future<void> _send(PushToken token) async {
    if (token.token == _registeredToken) return;
    try {
      await _register(token);
      _registeredToken = token.token;
      trace('push token registered', category: 'room', data: {'platform': token.platform});
    } catch (e, s) {
      reportNonFatal(e, s, during: 'registering the push token');
    }
  }

  /// Signed out: this device must stop being reachable as that account.
  Future<void> forgetDevice() async {
    final token = _registeredToken;
    _registeredToken = null;
    if (token == null) return;
    try {
      await _unregister(token);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'unregistering the push token');
    }
  }

  @override
  void dispose() {
    _tokenSub?.cancel();
    _tapSub?.cancel();
    _foregroundSub?.cancel();
    _taps.close();
    _foreground.close();
    final focus = _focus;
    if (focus != null) {
      try {
        WidgetsBinding.instance.removeObserver(focus);
      } catch (_) {}
    }
    super.dispose();
  }
}

/// Calls back when the app is brought to the front.
class _FocusWatcher with WidgetsBindingObserver {
  _FocusWatcher(this._onResumed);

  final VoidCallback _onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _onResumed();
  }
}
