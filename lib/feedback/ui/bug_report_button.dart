import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../ui/bar_item.dart';
import '../../ui/booth_icons.g.dart';
import '../../ui/buttons.dart';
import '../bug_report.dart';
import '../discovery/discovery_anchor.dart';

/// The bug button that sits in every header: a Seat square with a Rail
/// hairline, never Beam (Beam is for live things).
///
/// [compact] is the 36 px desktop-bar size, which carries a tooltip with the
/// shortcut. The default is the 40 px phone square inside a 44 px hit area.
class BugReportButton extends StatelessWidget {
  const BugReportButton({super.key, this.compact = false});

  final bool compact;

  static const String label = 'Report a bug';

  @override
  Widget build(BuildContext context) => DiscoveryAnchor(child: _button(context));

  Widget _button(BuildContext context) {
    if (compact) {
      final mac = defaultTargetPlatform == .macOS;
      // The bar's item height, so it matches the chips beside it.
      final h = PTBar.height(context, touch: false);
      return PTBarItem(
        square: true,
        touch: false,
        child: PTIconButton(
          icon: BoothIcons.bug,
          size: h,
          iconSize: 18,
          tooltip: '$label (${mac ? '⌘⇧B' : 'Ctrl+Shift+B'})',
          onPressed: () => BugReport.open(context),
        ),
      );
    }
    // The bar's touch item height drawn (40 at 1x text), at least 44 px
    // tappable: the outer detector owns the touch and the button inside is only
    // the picture.
    final h = PTBar.height(context, touch: true);
    final hit = h < 44 ? 44.0 : h;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => BugReport.open(context),
        child: SizedBox(
          width: hit,
          height: hit,
          child: Center(
            // A no-op onPressed keeps the glyph at full strength; the real tap is the
            // detector above, since this square is only the picture.
            child: IgnorePointer(
              child: PTBarItem(
                square: true,
                touch: true,
                child: PTIconButton(icon: BoothIcons.bug, size: h, iconSize: 20, onPressed: () {}),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
