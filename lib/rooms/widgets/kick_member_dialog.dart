import 'package:flutter/material.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/inputs.dart';
import 'package:synctogether/ui/pt_theme.dart';

/// Body for [showGlassDialog]. Pops `true` to remove and let them back in,
/// `false` to remove and bar them for the life of the room, null to cancel -
/// the per-kick choice of D9, rather than a room-wide ban setting.
class KickMemberDialog extends StatefulWidget {
  const KickMemberDialog({super.key, required this.displayName});

  final String displayName;

  @override
  State<KickMemberDialog> createState() => _KickMemberDialogState();
}

class _KickMemberDialogState extends State<KickMemberDialog> {
  bool _allowRejoin = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: [
        // A display name is user input of any length - one long word breaks
        // mid-letter if it has to wrap - so it gets two lines at most and an
        // ellipsis past that, instead of a five-line heading.
        Text(
          'Remove ${widget.displayName}?',
          textAlign: .center,
          maxLines: 2,
          overflow: .ellipsis,
          textScaler: dialogHeadingScaler(context),
          style: PTText.screenTitle.copyWith(fontSize: 20),
        ),
        const SizedBox(height: 8),
        Text(
          "They'll be taken back to the lobby.",
          textAlign: .center,
          style: PTText.body.copyWith(fontSize: 13.5, color: PTColors.white(0.55)),
        ),
        const SizedBox(height: 18),
        PTCheckTile(
          label: 'Let them rejoin with the room code',
          value: _allowRejoin,
          onChanged: (v) => setState(() => _allowRejoin = v),
        ),
        const SizedBox(height: 18),
        PTButtonBar(
          buttons: [
            PTButton(
              maxLines: 2,
              label: 'Cancel',
              variant: .secondary,
              onPressed: () => Navigator.of(context).pop(),
            ),
            PTButton(
              maxLines: 2,
              label: 'Remove',
              variant: .destructive,
              onPressed: () => Navigator.of(context).pop(_allowRejoin),
            ),
          ],
        ),
      ],
    );
  }
}
