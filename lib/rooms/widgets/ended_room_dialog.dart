import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:synctogether/rooms/room_models.dart';
import 'package:synctogether/ui/buttons.dart';
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
      crossAxisAlignment: .start,
      spacing: 14,
      children: [
        Row(
          spacing: 13,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: PTColors.white(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: PTColors.white(0.12)),
              ),
              child: Icon(Symbols.timer_off_rounded, size: 22, fill: 1, color: PTColors.white(0.5)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                spacing: 2,
                children: [
                  Text('Watch session ended', style: PTText.cardHeading),
                  Text(
                    room.name,
                    style: PTText.mono.copyWith(fontSize: 12, color: PTColors.textAccent),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        Text(
          'Free watch rooms are session-based and close once the party wraps up. '
          'You can start a fresh room anytime, or upgrade to Premium to keep rooms saved permanently with dedicated invite links.',
          style: PTText.body.copyWith(fontSize: 13.5, color: PTColors.white(0.65), height: 1.5),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: PTColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFA78BFA).withValues(alpha: 0.2)),
          ),
          child: Row(
            spacing: 10,
            children: [
              const Icon(Symbols.workspace_premium_rounded, size: 20, color: PTColors.textAccent),
              Expanded(
                child: Text(
                  'Premium keeps up to 20 rooms saved forever.',
                  style: PTText.body.copyWith(fontSize: 12.5, color: PTColors.white(0.85)),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            spacing: 8,
            children: [
              Row(
                spacing: 10,
                children: [
                  Expanded(
                    child: PTButton(
                      label: 'Start fresh room',
                      icon: Symbols.add_rounded,
                      variant: .primary,
                      height: 44,
                      onPressed: () {
                        Navigator.of(context).pop();
                        onStartFresh();
                      },
                    ),
                  ),
                  Expanded(
                    child: PTButton(
                      label: 'Get Premium',
                      icon: Symbols.workspace_premium_rounded,
                      variant: .secondary,
                      height: 44,
                      onPressed: () {
                        Navigator.of(context).pop();
                        onUpgrade();
                      },
                    ),
                  ),
                ],
              ),
              if (isOwner)
                Center(
                  child: TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: PTColors.white(0.45),
                      textStyle: PTText.caption.copyWith(fontSize: 12),
                    ),
                    onPressed: () {
                      Navigator.of(context).pop();
                      onDelete();
                    },
                    child: const Text('Remove from list'),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
