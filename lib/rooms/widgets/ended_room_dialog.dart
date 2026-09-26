import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
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
    required this.onUpgrade,
    required this.onDelete,
    this.isOwner = true,
  });

  final Room room;
  final VoidCallback onStartFresh;
  final VoidCallback onUpgrade;
  final VoidCallback onDelete;
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
          'Free rooms run one session. Open a fresh one for the next film.',
          style: PTText.body.copyWith(fontSize: 14, color: PTColors.white(0.65), height: 1.5),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: PTButton(
            maxLines: 2,
            label: 'Open a fresh room',
            icon: Symbols.add_rounded,
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
            DialogTextButton(
              label: 'Patron: 20 saved rooms',
              color: PTColors.premium,
              underline: false,
              fontSize: 13,
              onPressed: () {
                Navigator.of(context).pop();
                onUpgrade();
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
