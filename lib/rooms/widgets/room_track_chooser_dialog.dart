import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:synctogether/player/chooser_dialog.dart';
import 'package:synctogether/player/subtitles/subtitle_style_dialog.dart';
import 'package:synctogether/player/youtube/pt_youtube_controller.dart';
import 'package:synctogether/ui/glass.dart';

/// Displays audio and subtitle track chooser dialogs for MediaKit playback.
Future<void> showRoomTrackChooser({
  required BuildContext context,
  required Player player,
  required bool subtitles,
  required VoidCallback onSubtitlesChanged,
  required VoidCallback onAddExternalSubtitle,
  bool hasSubtitleStyle = false,
  void Function(String message)? onInfo,
}) async {
  final tracks = player.state.tracks;
  if (!subtitles && tracks.audio.isEmpty) {
    onInfo?.call('No audio tracks in this video.');
    return;
  }
  final subTracks = tracks.subtitle.isNotEmpty
      ? tracks.subtitle
      : [SubtitleTrack.no(), SubtitleTrack.auto()];
  await showGlassDialog(
    context: context,
    width: 380,
    builder: (dialogContext) => subtitles
        ? ChooserDialog<SubtitleTrack>(
            type: 'Subtitles',
            values: subTracks,
            selected: player.state.track.subtitle,
            onChosen: (track) async {
              await player.setSubtitleTrack(track);
              onSubtitlesChanged();
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            onAddFromFile: () {
              Navigator.of(dialogContext).pop();
              onAddExternalSubtitle();
            },
            onStyle: !hasSubtitleStyle
                ? null
                : () {
                    Navigator.of(dialogContext).pop();
                    unawaited(showSubtitleStyleDialog(context));
                  },
          )
        : ChooserDialog<AudioTrack>(
            type: 'Audio',
            values: tracks.audio,
            selected: player.state.track.audio,
            onChosen: (track) async {
              await player.setAudioTrack(track);
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
          ),
  );
}

/// Displays caption track chooser dialog for YouTube loopback playback.
Future<void> showRoomYouTubeCaptionChooser({
  required BuildContext context,
  required PTYouTubeController controller,
}) async {
  final tracks = controller.captionTracks;
  await showGlassDialog(
    context: context,
    width: 380,
    builder: (dialogContext) => ChooserDialog<PTYouTubeCaptionTrack>(
      type: 'Subtitles',
      values: tracks,
      selected: controller.selectedCaptionTrack,
      onChosen: (track) {
        controller.setCaptionTrack(track);
        if (dialogContext.mounted) Navigator.of(dialogContext).pop();
      },
    ),
  );
}
