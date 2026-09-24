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
        const GlassDialogHeader(
          title: 'Share with room?',
          leading: Icon(Symbols.cloud_upload_rounded, size: 22, color: PTColors.textAccent),
          spacing: 10,
        ),
        const SizedBox(height: 12),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Share '),
              TextSpan(
                text: widget.fileName,
                style: PTText.body.copyWith(fontSize: 14, fontWeight: .w600, color: Colors.white),
              ),
              TextSpan(text: ' ($sizeFormatted) with everyone in the room?'),
            ],
          ),
          style: PTText.body.copyWith(fontSize: 14, color: PTColors.white(0.7), height: 1.5),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: PTColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: PTColors.accentBorder.withValues(alpha: 0.2)),
          ),
          child: Row(
            spacing: 10,
            crossAxisAlignment: .start,
            children: [
              const Icon(Symbols.info_rounded, size: 18, color: PTColors.textAccent),
              Expanded(
                child: Text(
                  'Sharing uploads the file to the cloud so room members can watch '
                  'seamlessly without needing a local copy.',
                  style: PTText.body.copyWith(fontSize: 12.5, color: PTColors.white(0.8)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        PTCheckTile(
          label: 'Remember my choice (you can change it in Profile settings)',
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
