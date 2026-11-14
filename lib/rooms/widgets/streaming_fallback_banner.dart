import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:synctogether/ui/banners.dart';
import 'package:synctogether/ui/buttons.dart';

/// Shown once on a rejoin that fell back to the host's shared copy because the
/// copy this device remembered is gone (board "Streaming fallback notice").
/// Info-styled on purpose: nothing is broken, the room is just streaming.
class StreamingFallbackBanner extends StatelessWidget {
  const StreamingFallbackBanner({required this.onUseMyCopy, required this.onDismiss, super.key});

  final VoidCallback onUseMyCopy;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => PTBanner(
    kind: .info,
    icon: Symbols.cloud_rounded,
    title: 'Streaming the shared copy',
    subtitle: "Your own copy isn't on this device any more. Pick it again to watch from your own storage.",
    trailing: PTButton(
      label: 'Use my copy',
      variant: .secondary,
      height: 38,
      expand: false,
      onPressed: onUseMyCopy,
    ),
    onDismiss: onDismiss,
  );
}
