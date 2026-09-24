import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:synctogether/player/youtube/youtube_links.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/inputs.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/pt_theme.dart';

/// Body for [showGlassDialog]; pops the validated URL string.
class YouTubeUrlDialog extends StatefulWidget {
  const YouTubeUrlDialog({super.key});

  @override
  State<YouTubeUrlDialog> createState() => _YouTubeUrlDialogState();
}

class _YouTubeUrlDialogState extends State<YouTubeUrlDialog> {
  final _controller = TextEditingController();
  String? _errorMessage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submitUrl() {
    final url = _controller.text.trim();
    if (url.isEmpty) {
      setState(() => _errorMessage = 'Paste a link first.');
      return;
    }
    final videoId = youtubeVideoId(url);
    if (videoId == null) {
      setState(() => _errorMessage = "Hmm, that doesn't look like a YouTube link.");
      return;
    }
    Navigator.of(context).pop(canonicalYouTubeUrl(videoId));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      spacing: 16,
      children: [
        Row(
          crossAxisAlignment: .start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                spacing: 5,
                children: [
                  Text(
                    'Paste a YouTube link',
                    textScaler: dialogHeadingScaler(context),
                    style: PTText.screenTitle.copyWith(fontSize: 20),
                  ),
                  Text(
                    'It switches for everyone in the room.',
                    style: PTText.body.copyWith(fontSize: 13.5, color: PTColors.white(0.55)),
                  ),
                ],
              ),
            ),
          ],
        ),
        PTTextField(
          controller: _controller,
          hint: 'youtube.com/watch?v=…',
          prefixIcon: Symbols.link_rounded,
          autofocus: true,
          errorText: _errorMessage,
          onChanged: (_) {
            if (_errorMessage != null) setState(() => _errorMessage = null);
          },
          onSubmitted: (_) => _submitUrl(),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            PTButton(
              maxLines: 2,
              label: 'Load video',
              trailingIcon: Symbols.arrow_forward_rounded,
              height: 46,
              onPressed: _submitUrl,
            ),
            // Playback here is always signed-out, so a Premium account's
            // ad-free benefit does not carry over. Saying so is the honest
            // answer: the only way to sign in would be a Google login inside
            // an embedded webview, which Google forbids and which asks people
            // to type their password into a container we control.
            Row(
              spacing: 8,
              children: [
                Icon(Symbols.info_rounded, size: 16, color: PTColors.white(0.45)),
                Expanded(
                  child: Text(
                    'Videos play signed out, so YouTube may show ads even if you have Premium.',
                    style: PTText.finePrint.copyWith(color: PTColors.white(0.5)),
                  ),
                ),
              ],
            ),
            PTButton(
              maxLines: 2,
              label: 'Cancel',
              variant: .secondary,
              height: 46,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ],
    );
  }
}
