import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:synctogether/player/youtube/youtube_auth_dialog.dart';
import 'package:synctogether/player/youtube/youtube_links.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/inputs.dart';
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
  bool _signedInToYouTube = false;

  @override
  void initState() {
    super.initState();
    _checkYouTubeAuth();
  }

  Future<void> _checkYouTubeAuth() async {
    try {
      final cookies = await CookieManager.instance().getCookies(
        url: WebUri('https://www.youtube.com'),
      );
      final hasAuth = cookies.any(
        (c) => c.name == 'LOGIN_INFO' || c.name == 'SID' || c.name == 'SAPISID',
      );
      if (mounted) {
        setState(() => _signedInToYouTube = hasAuth);
      }
    } catch (_) {}
  }

  Future<void> _disconnectYouTube() async {
    await CookieManager.instance().deleteAllCookies();
    if (mounted) {
      setState(() => _signedInToYouTube = false);
    }
  }

  Future<void> _connectYouTube() async {
    await YouTubeAuthDialog.show(context);
    await _checkYouTubeAuth();
  }

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
                  Text('Paste a YouTube link', style: PTText.screenTitle.copyWith(fontSize: 20)),
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
              label: 'Load video',
              trailingIcon: Symbols.arrow_forward_rounded,
              height: 46,
              onPressed: _submitUrl,
            ),
            if (_signedInToYouTube)
              Row(
                children: [
                  Expanded(
                    child: Tooltip(
                      message:
                          'Signed in to YouTube. If your account has YouTube Premium, ad-free playback will automatically apply.',
                      child: InkWell(
                        onTap: _connectYouTube,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          height: 46,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: const Color(0x1F34D399),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0x4434D399)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Symbols.check_circle_rounded,
                                color: Color(0xFF34D399),
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'YouTube Account Connected',
                                  style: PTText.body.copyWith(
                                    color: const Color(0xFF34D399),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PTButton(
                    label: 'Log Out',
                    icon: Symbols.logout_rounded,
                    variant: .secondary,
                    height: 46,
                    expand: false,
                    onPressed: _disconnectYouTube,
                  ),
                ],
              )
            else
              Tooltip(
                message:
                    'Sign in with your Google account. If you have YouTube Premium, ad-free playback will automatically apply.',
                child: PTButton(
                  label: 'Sign in to YouTube (for Premium)',
                  icon: Symbols.account_circle_rounded,
                  variant: .secondary,
                  height: 46,
                  onPressed: _connectYouTube,
                ),
              ),
            PTButton(
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
