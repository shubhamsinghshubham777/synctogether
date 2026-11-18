import 'package:material_ui/material_ui.dart';

import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/pt_theme.dart';

/// Picture-in-picture is switched off for this app in system settings (board
/// 96, edge frame B). Only the OS can turn it on, so the one button goes to
/// the right settings page.
class PipOffDialog extends StatelessWidget {
  const PipOffDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: [
        GlassDialogHeader(
          eyebrow: 'Picture-in-picture',
          title: 'Picture-in-picture is off for SyncTogether',
          onClose: () => Navigator.of(context).pop(false),
        ),
        const SizedBox(height: 14),
        Text(
          'Turn it on in Settings and the film will shrink to a corner when you leave.',
          style: PTText.body.copyWith(fontSize: 13.5, color: PTColors.white(0.6)),
        ),
        const SizedBox(height: 20),
        PTButtonBar(
          buttons: [
            PTButton(
              label: 'Not now',
              variant: .secondary,
              onPressed: () => Navigator.of(context).pop(false),
            ),
            PTButton(label: 'Open settings', onPressed: () => Navigator.of(context).pop(true)),
          ],
        ),
      ],
    );
  }
}
