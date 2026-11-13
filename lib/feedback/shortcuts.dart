import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../diagnostics.dart';
import '../platform.dart';
import 'bug_report.dart';

/// "Report a bug" from anywhere on desktop.
///
/// - **Windows and Linux:** Ctrl+Shift+B, a [CallbackShortcuts] rather than a
///   raw key handler: it only sees events the focused widget left unhandled, so
///   the room's own hotkeys (`_handleKeyEvent` in room_screen.dart, which ignores
///   modified keys it does not own) win first. There is no menu bar there.
/// - **macOS:** the Help menu's "Report a Bug…" (`AppDelegate`) owns
///   Shift+Cmd+B and tells us over [menuChannel]. The key is deliberately not
///   bound here as well, or one press could open the sheet twice.
///
/// [navigatorContext] resolves the router's navigator at press time - the
/// `MaterialApp.builder` context sits *above* the Navigator, and the report
/// flow needs one to show its sheet. Before it exists (the app is still
/// starting) a press does nothing.
class BugReportShortcut extends StatefulWidget {
  const BugReportShortcut({super.key, required this.navigatorContext, required this.child});

  /// Native Help-menu item -> Dart. Method `report`, no arguments.
  @visibleForTesting
  static const menuChannel = MethodChannel('app.synctogether/bug_report_menu');

  final BuildContext? Function() navigatorContext;
  final Widget child;

  @override
  State<BugReportShortcut> createState() => _BugReportShortcutState();
}

class _BugReportShortcutState extends State<BugReportShortcut> {
  bool get _mac => !kIsWeb && defaultTargetPlatform == .macOS;

  /// The state that currently answers the menu. A remount (the splash swaps its
  /// subtree) builds the new state before the old one is disposed, so the old
  /// one must only clear the handler if it is still the owner.
  static _BugReportShortcutState? _owner;

  @override
  void initState() {
    super.initState();
    if (!_mac) return;
    _owner = this;
    BugReportShortcut.menuChannel.setMethodCallHandler(_fromMenu);
  }

  @override
  void dispose() {
    if (identical(_owner, this)) {
      _owner = null;
      BugReportShortcut.menuChannel.setMethodCallHandler(null);
    }
    super.dispose();
  }

  Future<void> _fromMenu(MethodCall call) async {
    if (call.method == 'report') _open('menu');
  }

  void _open(String source) {
    final ctx = widget.navigatorContext();
    final ready = ctx != null && ctx.mounted;
    trace(
      'bug report requested',
      category: 'feedback',
      data: {'source': source, 'ready': ready, 'already_open': BugReport.isOpen},
    );
    if (ready) BugReport.open(ctx, source: source);
  }

  @override
  Widget build(BuildContext context) {
    if (!isDesktop || _mac) return widget.child;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyB, shift: true, control: true): () =>
            _open('shortcut'),
      },
      child: widget.child,
    );
  }
}
