import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:synctogether/ui/pt_motion.dart';
import 'package:synctogether/ui/pt_theme.dart';

import 'package:flutter/services.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/glass.dart';

enum InitialMode { local, youtube, leave }

/// Body for [showGlassDialog]: "What are we watching?" source chooser.
class ModeSelectionDialog extends StatelessWidget {
  const ModeSelectionDialog({super.key});

  Future<void> _handleClose(BuildContext context) async {
    final confirmed = await showGlassDialog<bool>(
      context: context,
      width: 380,
      builder: (dialogContext) => Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        spacing: 14,
        children: [
          const GlassDialogHeader(eyebrow: 'Intermission', title: 'Leave the room?'),
          Text(
            'Are you sure you want to leave this room? You will return to the lobby.',
            style: PTText.body.copyWith(fontSize: 14, color: PTColors.white(0.65), height: 1.5),
          ),
          PTButtonBar(
            buttons: [
              PTButton(
                maxLines: 2,
                label: 'Stay',
                variant: .secondary,
                height: 42,
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              PTButton(
                maxLines: 2,
                label: 'Leave room',
                variant: .destructive,
                icon: Symbols.logout_rounded,
                height: 42,
                onPressed: () => Navigator.of(dialogContext).pop(true),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      Navigator.of(context).pop(InitialMode.leave);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The glass shell lands first, then its contents settle into it.
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
                closeTooltip: 'Leave room',
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
              (
                Symbols.video_file_rounded,
                'Local file',
                'Everyone opens their own copy',
                InitialMode.local,
              ),
              (
                Symbols.smart_display_rounded,
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
