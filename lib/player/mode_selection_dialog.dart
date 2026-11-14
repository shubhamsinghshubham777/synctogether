import 'package:material_ui/material_ui.dart';

import '../ui/booth_icons.g.dart';

import 'package:synctogether/ui/pt_motion.dart';
import 'package:synctogether/ui/pt_theme.dart';

import 'package:flutter/services.dart';
import 'package:synctogether/ui/glass.dart';

enum InitialMode { local, youtube }

/// Body for [showGlassDialog]: "What are we watching?" source chooser.
class ModeSelectionDialog extends StatelessWidget {
  const ModeSelectionDialog({super.key});

  /// The close button and Esc do what a close button does, on every platform:
  /// put the picker away. Leaving is the header's back arrow and the room menu,
  /// and the empty room behind this dialog offers the same two sources, so
  /// closing is never a dead end. (It used to open "Leave the room?" on desktop,
  /// under a tooltip that said "Leave room" - a close icon that quits.)
  void _handleClose(BuildContext context) => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    // The panel lands first, then its contents settle into it.
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => _handleClose(context)},
      child: Focus(
        autofocus: true,
        child: Column(
          mainAxisSize: .min,
          children: [
            PTEntrance(
              duration: PTMotion.state,
              offset: 8,
              child: GlassDialogHeader(
                eyebrow: 'Now showing',
                title: 'What are we watching?',
                closeIconSize: 20,
                closeTooltip: 'Close',
                onClose: () => _handleClose(context),
              ),
            ),
            const SizedBox(height: 8),
            PTEntrance(
              delay: const Duration(milliseconds: 40),
              duration: PTMotion.state,
              offset: 8,
              child: Align(
                alignment: .centerLeft,
                child: Text(
                  'Pick a source. Everyone stays in sync either way.',
                  style: PTText.body.copyWith(fontSize: 13.5, color: PTColors.white(0.6)),
                ),
              ),
            ),
            const SizedBox(height: 18),
            for (final (i, option) in [
              (BoothIcons.file, 'Local file', 'Everyone opens their own copy', InitialMode.local),
              (
                BoothIcons.youtube,
                'YouTube',
                'Paste a link, it plays for the room',
                InitialMode.youtube,
              ),
            ].indexed)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
                child: PTEntrance(
                  delay: Duration(milliseconds: 80 + 40 * i),
                  duration: PTMotion.state,
                  offset: 8,
                  child: DialogOptionRow(
                    icon: option.$1,
                    label: option.$2,
                    description: option.$3,
                    chevron: true,
                    iconTile: true,
                    onTap: () => Navigator.of(context).pop(option.$4),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
