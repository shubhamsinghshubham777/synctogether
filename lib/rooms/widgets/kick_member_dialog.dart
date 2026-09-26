import 'package:flutter/material.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/identity.dart';
import 'package:synctogether/ui/inputs.dart';
import 'package:synctogether/ui/pt_theme.dart';

/// Body for [showGlassDialog]. Pops `true` to remove and let them back in,
/// `false` to remove and bar them for the life of the room, null to cancel -
/// the per-kick choice of D9, rather than a room-wide ban setting.
///
/// The checkbox asks the question the other way round ("keep the door
/// shut"), so it defaults off and the pop is its inverse: `ban = keepShut`,
/// `allowRejoin = !keepShut` - exactly the old "let them rejoin" default.
class KickMemberDialog extends StatefulWidget {
  const KickMemberDialog({super.key, required this.displayName, this.userId, this.avatarUrl});

  final String displayName;

  /// For the member row's avatar; falls back to the name for its colour.
  final String? userId;
  final String? avatarUrl;

  @override
  State<KickMemberDialog> createState() => _KickMemberDialogState();
}

class _KickMemberDialogState extends State<KickMemberDialog> {
  bool _keepShut = false;

  void _close() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      spacing: 16,
      children: [
        GlassDialogHeader(
          eyebrow: 'Ushering out',
          // A display name is user input of any length, so the title names
          // them only in the member row below, where it can ellipsize.
          title: 'Show ${widget.displayName} out?',
          subtitle: 'Back to the lobby. Nobody else is told.',
          titleGap: 6,
          onClose: _close,
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: PTColors.aisle,
            borderRadius: BorderRadius.circular(PTRadius.control),
          ),
          child: Row(
            spacing: 12,
            children: [
              PTAvatar(
                userId: widget.userId ?? widget.displayName,
                displayName: widget.displayName,
                avatarUrl: widget.avatarUrl,
                size: 32,
              ),
              Expanded(
                child: Text(
                  widget.displayName,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: PTText.body.copyWith(fontSize: 15, fontWeight: .w600),
                ),
              ),
            ],
          ),
        ),
        PTCheckTile(
          label: "Keep the door shut: they can't rejoin with the code",
          value: _keepShut,
          onChanged: (v) => setState(() => _keepShut = v),
        ),
        PTButtonBar(
          buttons: [
            PTButton(maxLines: 2, label: 'Cancel', variant: .secondary, onPressed: _close),
            PTButton(
              maxLines: 2,
              label: 'Show them out',
              variant: .destructive,
              onPressed: () => Navigator.of(context).pop(!_keepShut),
            ),
          ],
        ),
      ],
    );
  }
}
