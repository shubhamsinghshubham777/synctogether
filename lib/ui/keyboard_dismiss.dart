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
    return GestureDetector(behavior: .translucent, onTap: dismissEditableFocus, child: child);
  }
}
