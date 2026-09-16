import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../diagnostics.dart';
import '../../ui/banners.dart';
import '../../ui/buttons.dart';
import '../../ui/glass.dart';
import '../../ui/identity.dart';
import '../../ui/pt_theme.dart';
import '../reward_icons.dart';
import '../rewards_logic.dart';
import '../rewards_models.dart';
import '../rewards_service.dart';

/// What the recap dialog needs to render, resolved by the room: names and
/// avatars for the superlative winners, and the session's own tallies.
class RecapPerson {
  const RecapPerson({required this.userId, required this.displayName, this.avatarUrl, this.frame});

  final String userId;
  final String displayName;
  final String? avatarUrl;
  final AvatarFrame? frame;
}

/// Shown when a session ends. Returns true if the user shared it.
///
/// This is the artefact the whole word-of-mouth loop is built on, so its one
/// call to action is a *link* rather than an image: a PNG in the clipboard is
/// not something desktop Flutter can produce (`Clipboard.setData` is text-only)
/// and a share sheet is not something desktop reliably has. The web page is the
/// share surface; this dialog's job is to mint the URL.
Future<bool> showRecapDialog({
  required BuildContext context,
  required SessionRecap recap,
  required Map<String, RecapPerson> people,
  required String selfId,
}) async {
  final shared = await showGlassDialog<bool>(
    context: context,
    width: 470,
    padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
    builder: (context) => _RecapBody(recap: recap, people: people, selfId: selfId),
  );
  return shared ?? false;
}

class _RecapBody extends StatefulWidget {
  const _RecapBody({required this.recap, required this.people, required this.selfId});

  final SessionRecap recap;
  final Map<String, RecapPerson> people;
  final String selfId;

  @override
  State<_RecapBody> createState() => _RecapBodyState();
}

class _RecapBodyState extends State<_RecapBody> {
  bool _sharing = false;
  String? _url;

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final url = await RewardsService.instance.shareRecap(widget.recap);
      if (!mounted) return;
      if (url == null) {
        showPTSnack(context, "Couldn't put that together. Give it another try.");
        setState(() => _sharing = false);
        return;
      }
      setState(() {
        _url = url;
        _sharing = false;
      });
      await Clipboard.setData(ClipboardData(text: url));
      final opened = await launchUrl(Uri.parse(url), mode: .externalApplication);
      if (!opened) {
        trace('recap browser launch refused', category: 'rewards');
      }
      if (mounted) {
        showPTSnack(context, 'Link copied - paste it anywhere.', kind: .success);
      }
    } on RewardsFailure catch (failure) {
      if (!mounted) return;
      setState(() => _sharing = false);
      showPTSnack(context, failure.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recap = widget.recap;
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                spacing: 2,
                children: [
                  Text('That was a good one', style: PTText.screenTitle.copyWith(fontSize: 21)),
                  Text(
                    '${formatWatchTime(recap.length)} in sync with '
                    '${recap.peakMembers - 1} other${recap.peakMembers == 2 ? '' : 's'}.',
                    style: PTText.caption,
                  ),
                ],
              ),
            ),
            PTIconButton(
              icon: Symbols.close_rounded,
              iconSize: 18,
              size: 36,
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).pop(_url != null),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          spacing: 10,
          children: [
            Expanded(
              child: _Stat(
                icon: Symbols.schedule_rounded,
                value: formatWatchTime(recap.length),
                label: 'watched',
              ),
            ),
            Expanded(
              child: _Stat(
                icon: Symbols.mood_rounded,
                value: '${recap.reactions}',
                label: 'reactions',
              ),
            ),
            Expanded(
              child: _Stat(
                icon: Symbols.forum_rounded,
                value: '${recap.messages}',
                label: 'messages',
              ),
            ),
          ],
        ),
        if (recap.superlatives.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            "Tonight's awards",
            style: PTText.finePrint.copyWith(
              fontSize: 11,
              letterSpacing: 0.7,
              fontWeight: .w600,
              color: PTColors.white(0.5),
            ),
          ),
          const SizedBox(height: 10),
          for (final superlative in recap.superlatives)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _AwardRow(
                superlative: superlative,
                person: widget.people[superlative.userId],
                isSelf: superlative.userId == widget.selfId,
              ),
            ),
        ],
        const SizedBox(height: 22),
        PTButton(
          label: _url != null ? 'Copy link again' : 'Share this',
          icon: _url != null ? Symbols.link_rounded : Symbols.ios_share_rounded,
          loading: _sharing,
          onPressed: _sharing
              ? null
              : _url != null
              ? () => Clipboard.setData(ClipboardData(text: _url!))
              : _share,
        ),
        const SizedBox(height: 10),
        Text(
          _url ??
              'Makes a page you can post anywhere. Nothing about what you watched '
                  'goes on it, and anyone who has not turned on a public profile '
                  'stays anonymous.',
          textAlign: .center,
          style: PTText.finePrint.copyWith(
            fontSize: 11,
            color: PTColors.white(_url != null ? 0.7 : 0.45),
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.value, required this.label});

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: 14,
      opacity: 0.4,
      blur: 16,
      shadow: false,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Column(
        spacing: 4,
        children: [
          Icon(icon, size: 17, color: PTColors.textAccent),
          Text(
            value,
            maxLines: 1,
            overflow: .ellipsis,
            style: PTText.cardHeading.copyWith(fontSize: 15),
          ),
          Text(label, style: PTText.finePrint.copyWith(fontSize: 10)),
        ],
      ),
    );
  }
}

class _AwardRow extends StatelessWidget {
  const _AwardRow({required this.superlative, this.person, this.isSelf = false});

  final Superlative superlative;
  final RecapPerson? person;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: 12,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: .circle,
            color: PTColors.primary.withValues(alpha: 0.14),
          ),
          alignment: .center,
          child: Icon(
            superlativeIcon(superlative.key),
            size: 17,
            fill: 1,
            color: PTColors.textAccent,
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: .start,
            children: [
              Text(
                superlative.key.title,
                style: PTText.body.copyWith(fontSize: 14, fontWeight: .w600),
              ),
              Text(superlative.key.blurb, style: PTText.finePrint.copyWith(fontSize: 11)),
            ],
          ),
        ),
        Row(
          mainAxisSize: .min,
          spacing: 7,
          children: [
            PTAvatar(
              userId: superlative.userId,
              displayName: superlative.displayName,
              avatarUrl: person?.avatarUrl,
              frame: person?.frame,
              size: 24,
            ),
            Text(
              isSelf ? 'You' : superlative.displayName,
              style: PTText.finePrint.copyWith(fontSize: 12, color: PTColors.white(0.8)),
            ),
          ],
        ),
      ],
    );
  }
}
