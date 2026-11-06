import 'package:flutter/widgets.dart';

import '../platform.dart';

/// Closes the soft keyboard by dropping primary focus, but only when that focus
/// belongs to an editable text. Focus on a button, the room's shortcut node or
/// anything else is left alone. Returns whether it unfocused.
bool dismissEditableFocus() {
  final primary = FocusManager.instance.primaryFocus;
  if (primary == null || primary.context?.findAncestorWidgetOfExactType<EditableText>() == null) {
    return false;
  }
  primary.unfocus();
  return true;
}

/// What else an unclaimed tap closes besides the keyboard: the inline emoji
/// picker, which stands in for it. At most one claimant at a time (one chat
/// panel's picker); [TapToDismissKeyboard] fires it after the field unfocuses.
/// Closing is the claimant's business - the picker folds shut, it does not pop.
class EmptyTapHook {
  EmptyTapHook._();

  static VoidCallback? _active;

  static void claim(VoidCallback callback) => _active = callback;

  /// A no-op unless [callback] is the current claimant, so a stale release
  /// never drops a newer panel's claim.
  static void release(VoidCallback callback) {
    if (_active == callback) _active = null;
  }

  static void fire() => _active?.call();
}

/// App-wide "tap empty space to close the keyboard", for touch platforms only.
///
/// Rule: a tap that **no other gesture claims** unfocuses an editable field.
/// This is a translucent [GestureDetector] at the root, so it takes part in the
/// gesture arena as the shallowest member and loses to anything deeper. That
/// is what keeps every other behaviour intact without enumerating it:
///  * a text field, its selection handles and toolbar claim their own taps, so
///    tapping the field or dragging a handle keeps focus;
///  * buttons fire and keep focus (the chat send button relies on it);
///  * a drag, scroll or slider gesture wins the arena, so none of them dismiss;
///  * a dialog barrier closes its dialog and nothing else.
/// The room's picture is the one tap target that wins the arena yet should
/// dismiss: its tap handler already moves focus to the shortcut node, which
/// unfocuses the field. Desktop renders the child untouched: a click on empty
/// space must not steal focus there.
class TapToDismissKeyboard extends StatelessWidget {
  const TapToDismissKeyboard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isTouchPlatform) return child;
    return GestureDetector(
      behavior: .translucent,
      onTap: () {
        dismissEditableFocus();
        EmptyTapHook.fire();
      },
      child: child,
    );
  }
}
