import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// `find.byTooltip` matches the in-SDK `Tooltip`, which this app no longer
/// builds; this finds the `material_ui` one by its message.
Finder byUiTooltip(String message) => find.byWidgetPredicate(
  (w) => w is Tooltip && w.message == message,
  description: 'material_ui Tooltip "$message"',
);
