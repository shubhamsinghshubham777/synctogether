import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/window/app_window.dart';

/// An in-memory [AppWindow]: state lives in fields and transitions are fired by
/// hand, so a test drives fullscreen and maximize with no native window.
class FakeAppWindow implements AppWindow {
  FakeAppWindow({this.fullScreen = false, this.maximized = false});

  bool fullScreen;
  bool maximized;
  final List<AppWindowListener> listeners = [];
  final List<String> calls = [];

  /// Installs this fake as the app's window and restores the real one after.
  FakeAppWindow install() {
    final previous = AppWindow.instance;
    AppWindow.instance = this;
    addTearDown(() => AppWindow.instance = previous);
    return this;
  }

  void enterFullScreen() {
    fullScreen = true;
    for (final l in List.of(listeners)) {
      l.onWindowEnterFullScreen();
    }
  }

  void leaveFullScreen() {
    fullScreen = false;
    for (final l in List.of(listeners)) {
      l.onWindowLeaveFullScreen();
    }
  }

  @override
  Future<void> configure({required Size minimumSize}) async => calls.add('configure');

  @override
  Future<bool> isFullScreen() async => fullScreen;

  @override
  Future<void> setFullScreen(bool value) async {
    calls.add('setFullScreen($value)');
    value ? enterFullScreen() : leaveFullScreen();
  }

  @override
  Future<bool> isMaximized() async => maximized;

  @override
  Future<void> minimize() async => calls.add('minimize');

  @override
  Future<void> maximize() async {
    calls.add('maximize');
    maximized = true;
    for (final l in List.of(listeners)) {
      l.onWindowMaximize();
    }
  }

  @override
  Future<void> unmaximize() async {
    calls.add('unmaximize');
    maximized = false;
    for (final l in List.of(listeners)) {
      l.onWindowUnmaximize();
    }
  }

  @override
  Future<void> close() async => calls.add('close');

  @override
  Future<void> setSize(Size size) async => calls.add('setSize($size)');

  @override
  Future<void> center() async => calls.add('center');

  @override
  void addListener(AppWindowListener listener) => listeners.add(listener);

  @override
  void removeListener(AppWindowListener listener) => listeners.remove(listener);
}
