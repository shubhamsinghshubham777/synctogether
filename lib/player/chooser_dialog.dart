import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:media_kit/media_kit.dart';
import 'package:synctogether/player/track_label.dart';
import 'package:synctogether/player/youtube/pt_youtube_controller.dart';
import 'package:synctogether/ui/pt_theme.dart';

/// Body for [showGlassDialog]: audio/subtitle track picker styled per the
/// "Subtitles" dialog in the redesign.
class ChooserDialog<T> extends StatelessWidget {
  const ChooserDialog({
    super.key,
    required this.type,
    required this.values,
    required this.onChosen,
    this.selected,
    this.onAddFromFile,
  });

  final String type;
  final Iterable<T> values;
  final ValueChanged<T> onChosen;
  final T? selected;
  final VoidCallback? onAddFromFile;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      spacing: 14,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Text(type, style: PTText.cardHeading),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: SingleChildScrollView(
            child: Column(
              spacing: 6,
              children: [
                ...values.map<Widget?>((value) {
                  final label = formatTrackLabel(value);
                  if (label.isEmpty) return null;
                  final isSelected = isTrackSelected(value, selected);
                  IconData? icon;
                  if (value is SubtitleTrack) {
                    if (value.id == 'no') icon = Symbols.subtitles_off_rounded;
                    if (value.id == 'auto') icon = Symbols.auto_mode_rounded;
                  } else if (value is AudioTrack) {
                    if (value.id == 'no') icon = Symbols.volume_off_rounded;
                    if (value.id == 'auto') icon = Symbols.auto_mode_rounded;
                  } else if (value is PTYouTubeCaptionTrack) {
                    if (value.isOff) icon = Symbols.subtitles_off_rounded;
                  }
                  return _TrackRow(
                    label: label,
                    icon: icon,
                    isSelected: isSelected,
                    onTap: () => onChosen(value),
                  );
                }).nonNulls,
                if (onAddFromFile != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Divider(color: PTColors.white(0.12), height: 1),
                  ),
                  _TrackRow(
                    label: 'Add from File...',
                    icon: Symbols.file_open_rounded,
                    isSelected: false,
                    onTap: onAddFromFile!,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TrackRow extends StatefulWidget {
  const _TrackRow({required this.label, required this.isSelected, required this.onTap, this.icon});

  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  State<_TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends State<_TrackRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? PTColors.primary.withValues(alpha: 0.22)
                : _hovered
                ? PTColors.white(0.07)
                : Colors.transparent,
            border: Border.all(
              color: widget.isSelected
                  ? const Color(0xFFA78BFA).withValues(alpha: 0.45)
                  : Colors.transparent,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              if (widget.icon != null) ...[
                Icon(
                  widget.icon,
                  size: 18,
                  color: widget.isSelected ? PTColors.textAccent : PTColors.white(0.6),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  widget.label,
                  style: PTText.body.copyWith(
                    fontSize: 14.5,
                    color: widget.isSelected ? Colors.white : PTColors.white(0.8),
                  ),
                ),
              ),
              if (widget.isSelected)
                const Icon(
                  Symbols.check_circle_rounded,
                  size: 18,
                  fill: 1,
                  color: PTColors.textAccent,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
