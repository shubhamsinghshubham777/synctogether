import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:synctogether/ui/banners.dart';
import 'package:synctogether/ui/buttons.dart';

/// Our Room only: the film one of you shared was kept for a while after the last
/// session and has now been released, so there is nothing to stream. Info-styled:
/// nothing is broken, the film just needs a copy again (board "Our Room media
/// retention"). Replaces what used to be a silent "Locate your copy".
class SharedCopyExpiredBanner extends StatelessWidget {
  const SharedCopyExpiredBanner({
    required this.subtitle,
    required this.onPickMyCopy,
    required this.onDismiss,
    super.key,
  });

  final String subtitle;
  final VoidCallback onPickMyCopy;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => PTBanner(
    kind: .warning,
    icon: Symbols.cloud_off_rounded,
    title: 'The shared copy was removed',
    subtitle: subtitle,
    trailing: PTButton(
      label: 'Pick my copy',
      variant: .secondary,
      height: 38,
      expand: false,
      onPressed: onPickMyCopy,
    ),
    onDismiss: onDismiss,
  );
}
