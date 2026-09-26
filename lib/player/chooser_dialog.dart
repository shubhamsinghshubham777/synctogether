import 'package:flutter/material.dart';
import '../ui/booth_icons.g.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:media_kit/media_kit.dart';
import 'package:synctogether/player/track_label.dart';
import 'package:synctogether/player/youtube/pt_youtube_controller.dart';
import 'package:synctogether/ui/glass.dart';
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
    this.onStyle,
  });

  final String type;
  final Iterable<T> values;
  final ValueChanged<T> onChosen;
  final T? selected;
  final VoidCallback? onAddFromFile;

  /// Opens the subtitle style sheet; listed under the tracks when set.
  final VoidCallback? onStyle;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      spacing: 14,
      children: [
        GlassDialogHeader(eyebrow: 'Tracks', title: type),
        // No inner scroller: showGlassDialog already scrolls the body within a
        // keyboard-aware height, and a nested 320px one outgrew that on short
        // windows, leaving the last row unreachable below the safe edge.
        Column(
          spacing: 6,
          children: [
            ...values.map<Widget?>((value) {
              final label = formatTrackLabel(value);
              if (label.isEmpty) return null;
              final isSelected = isTrackSelected(value, selected);
              IconData? icon;
              if (value is SubtitleTrack) {
                if (value.id == 'no') icon = BoothIcons.subtitlesOff;
                if (value.id == 'auto') icon = Symbols.auto_mode_rounded;
              } else if (value is AudioTrack) {
                if (value.id == 'no') icon = BoothIcons.volumeOff;
                if (value.id == 'auto') icon = Symbols.auto_mode_rounded;
              } else if (value is PTYouTubeCaptionTrack) {
                if (value.isOff) icon = BoothIcons.subtitlesOff;
              }
              return _TrackRow(
                label: label,
                icon: icon,
                isSelected: isSelected,
                onTap: () => onChosen(value),
              );
            }).nonNulls,
            if (values.any((v) => v is SubtitleTrack && isBitmapSubtitle(v)))
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
                child: Text(
                  'Picture tracks are images from the disc and keep their own look. '
                  'Pick a text track to use your subtitle style.',
                  style: PTText.caption,
                ),
              ),
            if (onAddFromFile != null || onStyle != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Divider(color: PTColors.rail, height: 1),
              ),
            if (onAddFromFile != null)
              _TrackRow(
                label: 'Add from file…',
                icon: BoothIcons.file,
                isSelected: false,
                onTap: onAddFromFile!,
              ),
            if (onStyle != null)
              _TrackRow(
                label: 'Subtitle style…',
                icon: Symbols.format_paint_rounded,
                isSelected: false,
                onTap: onStyle!,
              ),
          ],
        ),
      ],
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({required this.label, required this.isSelected, required this.onTap, this.icon});

  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    // Only the chosen track is outlined; the rest read as a plain list.
    return DialogOptionRow(
      label: label,
      icon: icon,
      selected: isSelected,
      borderless: !isSelected,
      onTap: onTap,
      labelStyle: PTText.body.copyWith(
        fontSize: 14.5,
        color: isSelected ? PTColors.fg : PTColors.white(0.8),
      ),
    );
  }
}
