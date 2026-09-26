import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/inputs.dart';
import 'package:synctogether/ui/pt_theme.dart';

class MediaSharingPromptResult {
  const MediaSharingPromptResult({required this.shouldShare, required this.rememberChoice});

  final bool shouldShare;
  final bool rememberChoice;
}

Future<MediaSharingPromptResult?> showMediaSharingPromptDialog({
  required BuildContext context,
  required String fileName,
  required int fileSize,
}) {
  return showGlassDialog<MediaSharingPromptResult>(
    context: context,
    barrierDismissible: false,
    width: 440,
    builder: (context) => _MediaSharingPromptDialog(fileName: fileName, fileSize: fileSize),
  );
}

class _MediaSharingPromptDialog extends StatefulWidget {
  const _MediaSharingPromptDialog({required this.fileName, required this.fileSize});

  final String fileName;
  final int fileSize;

  @override
  State<_MediaSharingPromptDialog> createState() => _MediaSharingPromptDialogState();
}

class _MediaSharingPromptDialogState extends State<_MediaSharingPromptDialog> {
  bool _rememberChoice = false;

  String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }

  void _pop(bool share) => Navigator.of(
    context,
  ).pop(MediaSharingPromptResult(shouldShare: share, rememberChoice: _rememberChoice));

  @override
  Widget build(BuildContext context) {
    final sizeFormatted = _formatSize(widget.fileSize);
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: [
        const GlassDialogHeader(eyebrow: 'Projection', title: 'Share with the room?'),
        const SizedBox(height: 16),
        // The file, as a dashed mono ticket stub: name ellipsized, size right.
        CustomPaint(
          painter: const DashedRectPainter(color: PTColors.rail, radius: PTRadius.control),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              spacing: 10,
              children: [
                Icon(Symbols.draft_rounded, size: 17, color: PTColors.white(0.6)),
                Expanded(
                  child: Text(
                    widget.fileName,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: PTText.mono.copyWith(fontSize: 13, color: PTColors.fg),
                  ),
                ),
                Text(sizeFormatted, style: PTText.mono.copyWith(fontSize: 12)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        // Removal is queued, not instant (pending_r2_deletions), so the copy
        // says "removed when the room closes" rather than promising a moment.
        Text(
          'We upload it once, so seats without a copy can stream it. '
          "It's removed when the room closes.",
          style: PTText.body.copyWith(fontSize: 14, color: PTColors.white(0.7), height: 1.5),
        ),
        const SizedBox(height: 12),
        PTCheckTile(
          label: 'Remember my choice (change it in your profile)',
          value: _rememberChoice,
          onChanged: (v) => setState(() => _rememberChoice = v),
        ),
        const SizedBox(height: 18),
        PTButtonBar(
          buttons: [
            PTButton(
              maxLines: 2,
              label: 'Play locally',
              variant: .secondary,
              height: 44,
              onPressed: () => _pop(false),
            ),
            PTButton(
              maxLines: 2,
              label: 'Share with room',
              icon: Symbols.cloud_upload_rounded,
              height: 44,
              onPressed: () => _pop(true),
            ),
          ],
        ),
      ],
    );
  }
}
