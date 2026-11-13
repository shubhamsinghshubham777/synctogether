import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../diagnostics.dart';
import '../platform.dart';

/// Cmd+, (macOS) / Ctrl+, (Windows, Linux) opens the profile from anywhere
/// outside a room - the platform convention for preferences.
///
/// - **macOS:** the app menu's "Preferences…" item (`ProfileMenuChannel` in
///   MainFlutterWindow.swift) owns Cmd+, and tells us over [menuChannel]. The
///   key is deliberately not bound here as well, or one press could fire twice.
/// - **Windows and Linux:** a [CallbackShortcuts]; there is no menu bar.
///
/// [open] decides whether the press is welcome (it is not inside a room, where
/// the room's own hotkeys and layout own the screen) and navigates.
class ProfileShortcut extends StatefulWidget {
  const ProfileShortcut({super.key, required this.open, required this.child});

  /// Native app-menu item -> Dart. Method `open`, no arguments.
  @visibleForTesting
  static const menuChannel = MethodChannel('app.synctogether/profile_menu');

  final void Function() open;
  final Widget child;

  @override
  State<ProfileShortcut> createState() => _ProfileShortcutState();
}

class _ProfileShortcutState extends State<ProfileShortcut> {
  bool get _mac => !kIsWeb && defaultTargetPlatform == .macOS;

  /// A remount builds the new state before the old one is disposed, so the old
  /// one must only clear the handler if it is still the owner.
  static _ProfileShortcutState? _owner;

  @override
  void initState() {
    super.initState();
    if (!_mac) return;
    _owner = this;
    ProfileShortcut.menuChannel.setMethodCallHandler(_fromMenu);
  }

  @override
  void dispose() {
    if (identical(_owner, this)) {
      _owner = null;
      ProfileShortcut.menuChannel.setMethodCallHandler(null);
    }
    super.dispose();
  }

  Future<void> _fromMenu(MethodCall call) async {
    if (call.method == 'open') _open('menu');
  }

  void _open(String source) {
    trace('profile shortcut', category: 'ui', data: {'source': source});
    widget.open();
  }

  @override
  Widget build(BuildContext context) {
    if (!isDesktop || _mac) return widget.child;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.comma, control: true): () => _open('key'),
      },
      child: widget.child,
    );
  }
}
