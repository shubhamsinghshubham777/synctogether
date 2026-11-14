import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

/// The drag handle widget, re-exported so the bar needs no direct import.
export 'package:window_manager/window_manager.dart' show DragToMoveArea;

/// Everything the app asks of its one OS window, behind one seam.
///
/// window_manager 0.7 is a thin binding over a native core and has no method
/// channel to stub, so no screen talks to it directly: they all go through
/// [AppWindow.instance], which a test swaps for a [FakeAppWindow]-style double.
/// This file is the only importer of `package:window_manager`.
abstract interface class AppWindow {
  /// The window every screen uses. Replace in tests, restore afterwards.
  static AppWindow instance = NativeAppWindow();

  /// Hidden title bar with the native window buttons, and the minimum size the
  /// responsive layout needs. Run once at startup, before the first frame.
  Future<void> configure({required Size minimumSize});

  Future<bool> isFullScreen();
  Future<void> setFullScreen(bool value);
  Future<bool> isMaximized();
  Future<void> minimize();
  Future<void> maximize();
  Future<void> unmaximize();

  /// Asks the window to close, the way its own close button does.
  Future<void> close();

  /// Sizes the whole frame, title bar included.
  Future<void> setSize(Size size);
  Future<void> center();

  void addListener(AppWindowListener listener);
  void removeListener(AppWindowListener listener);
}

/// Window transitions a screen can react to. Every callback is optional.
mixin AppWindowListener {
  void onWindowEnterFullScreen() {}
  void onWindowLeaveFullScreen() {}
  void onWindowMaximize() {}
  void onWindowUnmaximize() {}
  void onWindowRestore() {}
}

/// The real window. Outside a running desktop app (widget tests, a platform
/// with no window) the native library is not loaded and every call degrades to
/// "no": not fullscreen, not maximized, nothing happens.
class NativeAppWindow implements AppWindow {
  final ObserverList<AppWindowListener> _listeners = ObserverList<AppWindowListener>();
  Window? _window;
  ListenerId? _nativeListener;

  Window? get _target {
    try {
      return _window ??= WindowManager.instance.getCurrent();
    } on ArgumentError {
      return null;
    }
  }

  @override
  Future<void> configure({required Size minimumSize}) async {
    final window = _target;
    if (window == null) return;
    window.minimumSize = minimumSize.toNative();
    window.titleBarStyle = TitleBarStyle.hidden;
    window.isWindowControlButtonsVisible = true;
  }

  @override
  Future<bool> isFullScreen() async => _target?.isFullScreen ?? false;

  @override
  Future<void> setFullScreen(bool value) async => _target?.isFullScreen = value;

  @override
  Future<bool> isMaximized() async => _target?.isMaximized ?? false;

  @override
  Future<void> minimize() async => _target?.minimize();

  @override
  Future<void> maximize() async => _target?.maximize();

  @override
  Future<void> unmaximize() async => _target?.unmaximize();

  @override
  Future<void> close() async => _target?.close();

  @override
  Future<void> setSize(Size size) async => _target?.setSize(size.toNative(), false);

  @override
  Future<void> center() async => _target?.center();

  @override
  void addListener(AppWindowListener listener) {
    _listeners.add(listener);
    _nativeListener ??= _target?.addListener(_dispatch);
  }

  @override
  void removeListener(AppWindowListener listener) {
    _listeners.remove(listener);
    final id = _nativeListener;
    if (_listeners.isEmpty && id != null) {
      _target?.removeListener(id);
      _nativeListener = null;
    }
  }

  void _dispatch(WindowEvent event) {
    // A copy: a callback may remove itself (a screen disposing on a transition).
    for (final l in List<AppWindowListener>.of(_listeners)) {
      switch (event) {
        case WindowEnteredFullScreenEvent():
          l.onWindowEnterFullScreen();
        case WindowExitedFullScreenEvent():
          l.onWindowLeaveFullScreen();
        case WindowMaximizedEvent():
          l.onWindowMaximize();
        case WindowRestoredEvent():
          l.onWindowRestore();
        default:
          break;
      }
    }
  }
}
