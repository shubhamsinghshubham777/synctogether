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
}

class ChannelPushBridge implements PushBridge {
  ChannelPushBridge() {
    _channel.setMethodCallHandler(_fromNative);
  }

  static const _channel = MethodChannel('app.synctogether/push');
  final _tokens = StreamController<PushToken>.broadcast();
  final _taps = StreamController<String?>.broadcast();

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
    _taps.close();
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
