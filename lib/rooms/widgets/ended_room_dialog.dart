import 'package:flutter/material.dart';
import '../../ui/booth_icons.g.dart';
import 'package:synctogether/rooms/room_models.dart';
import 'package:synctogether/ui/booth.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/pt_theme.dart';

class EndedRoomDialog extends StatelessWidget {
  const EndedRoomDialog({
    super.key,
    required this.room,
    required this.onStartFresh,
    this.onUpgrade,
    required this.onDelete,
    this.onResume,
    this.isOwner = true,
  });

  final Room room;
  final VoidCallback onStartFresh;

  /// Null where the build may not sell Premium (see `canSellPremium`).
  final VoidCallback? onUpgrade;
  final VoidCallback onDelete;

  /// Set while the room is still inside its resume window and the viewer is a
  /// host: starts a new session on the same room, code and members.
  final VoidCallback? onResume;
  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      spacing: 14,
      children: [
        Row(
          spacing: 16,
          // Top-aligned: a heading that wraps keeps its stamp by the first line.
          crossAxisAlignment: .start,
          children: [
            const PTStamp(
              size: 64,
              angle: -0.14,
              child: Column(
                mainAxisSize: .min,
                children: [
                  Text(
                    'FIN',
                    style: TextStyle(
                      fontFamily: PTFonts.display,
                      fontWeight: .w800,
                      fontSize: 18,
                      height: 1,
                    ),
                  ),
                  Text(
                    'ROOM',
                    style: TextStyle(fontFamily: PTFonts.mono, fontSize: 7, letterSpacing: 1),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                spacing: 4,
                children: [
                  Text(
                    '${room.code} · closed'.toUpperCase(),
                    style: PTText.label,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'That show has closed.',
                    textScaler: dialogHeadingScaler(context),
                    style: PTText.screenTitle.copyWith(fontSize: 24, height: 1.05),
                  ),
                ],
              ),
            ),
          ],
        ),
        Text(
          onResume != null
              ? 'This room is still kept, so you can pick up where you left off.'
              : 'Free rooms run one session. Open a fresh one for the next film.',
          style: PTText.body.copyWith(fontSize: 14, color: PTColors.white(0.65), height: 1.5),
        ),
        if (onResume case final resume?)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: PTButton(
              maxLines: 2,
              label: 'Resume this room',
              icon: BoothIcons.play,
              height: 46,
              onPressed: () {
                Navigator.of(context).pop();
                resume();
              },
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: PTButton(
            maxLines: 2,
            label: 'Open a fresh room',
            icon: BoothIcons.add,
            variant: onResume != null ? .secondary : .primary,
            height: 46,
            onPressed: () {
              Navigator.of(context).pop();
              onStartFresh();
            },
          ),
        ),
        // The Patron nudge is Brass text, never a second lit button.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          children: [
            if (onUpgrade case final upgrade?)
              DialogTextButton(
                label: 'Patron: 20 saved rooms',
                color: PTColors.premium,
                underline: false,
                fontSize: 13,
                onPressed: () {
                  Navigator.of(context).pop();
                  upgrade();
                },
              ),
            if (isOwner)
              DialogTextButton(
                label: 'Remove from list',
                fontSize: 13,
                onPressed: () {
                  Navigator.of(context).pop();
                  onDelete();
                },
              ),
          ],
        ),
      ],
    );
  }
}
