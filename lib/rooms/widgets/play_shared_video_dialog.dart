import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:synctogether/player/youtube/youtube_links.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/loader.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/pt_theme.dart';

class PlaySharedVideoDialog extends StatelessWidget {
  const PlaySharedVideoDialog({super.key, required this.videoId, required this.sharedBy});

  final String videoId;
  final String sharedBy;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: [
        GlassDialogHeader(
          eyebrow: 'Requested from the floor',
          title: 'Play this video?',
          onClose: () => Navigator.of(context).pop(false),
        ),
        const SizedBox(height: 16),
        Row(
          spacing: 12,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(PTRadius.control),
              child: SizedBox(
                width: 96,
                height: 54,
                child: DecoratedBox(
                  decoration: const BoxDecoration(color: PTColors.ink),
                  child: Image.network(
                    youtubeThumbnailUrl(videoId),
                    fit: .cover,
                    loadingBuilder: (context, child, progress) =>
                        progress == null ? child : const Center(child: PTLoader(size: 16)),
                    errorBuilder: (context, _, _) => Center(
                      child: Icon(
                        Symbols.play_arrow_rounded,
                        size: 22,
                        fill: 1,
                        color: PTColors.white(0.6),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                spacing: 3,
                children: [
                  Text(
                    '$sharedBy shared it in chat',
                    maxLines: 2,
                    overflow: .ellipsis,
                    style: PTText.body.copyWith(
                      fontSize: 14,
                      fontWeight: .w600,
                      color: PTColors.fg,
                    ),
                  ),
                  Text('YOUTUBE', style: PTText.label),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'Everyone in the room switches over to it.',
          style: PTText.body.copyWith(fontSize: 13.5, color: PTColors.white(0.6)),
        ),
        const SizedBox(height: 20),
        PTButtonBar(
          buttons: [
            PTButton(
              maxLines: 2,
              label: 'Not now',
              variant: .secondary,
              onPressed: () => Navigator.of(context).pop(false),
            ),
            PTButton(
              maxLines: 2,
              label: 'Play it',
              icon: Symbols.play_arrow_rounded,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ],
    );
  }
}
