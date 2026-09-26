import 'package:flutter/material.dart';
import '../ui/booth_icons.g.dart';
import 'package:synctogether/player/youtube/youtube_links.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/inputs.dart';
import 'package:synctogether/ui/glass.dart';

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
        const GlassDialogHeader(
          eyebrow: 'Now showing · YouTube',
          title: 'Paste a YouTube link',
          subtitle: 'It switches for everyone in the room.',
          titleGap: 5,
        ),
        PTTextField(
          controller: _controller,
          hint: 'youtube.com/watch?v=…',
          prefixIcon: BoothIcons.link,
          autofocus: true,
          errorText: _errorMessage,
          onChanged: (_) {
            if (_errorMessage != null) setState(() => _errorMessage = null);
          },
          onSubmitted: (_) => _submitUrl(),
        ),
        // Playback here is always signed-out, so a Premium account's
        // ad-free benefit does not carry over. Saying so is the honest
        // answer: the only way to sign in would be a Google login inside
        // an embedded webview, which Google forbids and which asks people
        // to type their password into a container we control.
        const DialogNote(
          icon: BoothIcons.info,
          child: Text('Plays signed out, so YouTube may show ads even if you pay for Premium.'),
        ),
        PTButtonBar(
          buttons: [
            PTButton(
              maxLines: 2,
              label: 'Cancel',
              variant: .secondary,
              height: 46,
              onPressed: () => Navigator.of(context).pop(),
            ),
            PTButton(
              maxLines: 2,
              label: 'Load video',
              trailingIcon: BoothIcons.arrowForward,
              height: 46,
              onPressed: _submitUrl,
            ),
          ],
        ),
      ],
    );
  }
}
