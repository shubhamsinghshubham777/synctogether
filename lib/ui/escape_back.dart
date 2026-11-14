import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:synctogether/nav.dart';
import 'package:synctogether/platform.dart';

/// Desktop: Escape does what the page's back button does (Telegram-style).
///
/// Wrap the `Scaffold` of any page that shows a back button. Dialogs, sheets
/// and popovers are separate routes whose focus never passes through this
/// widget, so Escape still closes those first. While a text field is being
/// edited the first Escape only leaves the field, so a half-typed value is
/// never thrown away by a stray press.
class PTEscapeBack extends StatefulWidget {
  const PTEscapeBack({super.key, required this.child, this.onBack});

  final Widget child;

  /// Overrides [goBack] for pages whose back button does something else.
  final VoidCallback? onBack;

  @override
  State<PTEscapeBack> createState() => _PTEscapeBackState();
}

class _PTEscapeBackState extends State<PTEscapeBack> {
  final _focus = FocusNode(debugLabel: 'PTEscapeBack', skipTraversal: true);

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!isDesktop) return widget.child;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          final focus = FocusManager.instance.primaryFocus;
          final editing = focus?.context?.findAncestorWidgetOfExactType<EditableText>() != null;
          if (editing) {
            // Hand focus back to this page, not to nowhere - otherwise the next
            // Escape never reaches the shortcut below.
            _focus.requestFocus();
            return;
          }
          (widget.onBack ?? () => goBack(context))();
        },
      },
      child: Focus(focusNode: _focus, autofocus: true, child: widget.child),
    );
  }
}
