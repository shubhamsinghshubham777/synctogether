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
        GlassDialogHeader(
          title: 'That was a good one',
          titleStyle: PTText.screenTitle.copyWith(fontSize: 21),
          subtitle:
              '${formatWatchTime(recap.length)} in sync with '
              '${recap.peakMembers - 1} other${recap.peakMembers == 2 ? '' : 's'}.',
          onClose: () => Navigator.of(context).pop(_url != null),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final stats = [
              (Symbols.schedule_rounded, formatWatchTime(recap.length), 'watched'),
              (Symbols.mood_rounded, '${recap.reactions}', 'reactions'),
              (Symbols.forum_rounded, '${recap.messages}', 'messages'),
            ];
            // Three tiles need ~80px each at the reader's text size; short of
            // that they become full-width rows rather than truncated numbers.
            final stacked = constraints.maxWidth < MediaQuery.textScalerOf(context).scale(240);
            if (stacked) {
              return Column(
                spacing: 8,
                children: [
                  for (final (icon, value, label) in stats)
                    _Stat(icon: icon, value: value, label: label, inline: true),
                ],
              );
            }
            return Row(
              spacing: 10,
              children: [
                for (final (icon, value, label) in stats)
                  Expanded(
                    child: _Stat(icon: icon, value: value, label: label),
                  ),
              ],
            );
          },
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
          maxLines: 2,
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
  const _Stat({required this.icon, required this.value, required this.label, this.inline = false});

  /// A full-width row (icon, value, label) for a narrow card.
  final bool inline;
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
      padding: inline
          ? const EdgeInsets.symmetric(vertical: 10, horizontal: 14)
          : const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: inline
          ? Row(
              spacing: 10,
              children: [
                Icon(icon, size: 17, color: PTColors.textAccent),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: value, style: PTText.cardHeading.copyWith(fontSize: 15)),
                        TextSpan(text: '  $label', style: PTText.finePrint.copyWith(fontSize: 11)),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : Column(
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
    final winner = Row(
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
        Flexible(
          child: Text(
            isSelf ? 'You' : superlative.displayName,
            maxLines: 1,
            overflow: .ellipsis,
            style: PTText.finePrint.copyWith(fontSize: 12, color: PTColors.white(0.8)),
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // Beside the award while there is room for both; under its blurb on
        // a narrow card, where a 150px name column would squeeze the title.
        final below = constraints.maxWidth < MediaQuery.textScalerOf(context).scale(340);
        return Row(
          spacing: 12,
          crossAxisAlignment: below ? .start : .center,
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
                  if (below) Padding(padding: const EdgeInsets.only(top: 6), child: winner),
                ],
              ),
            ),
            // A winner's name is user input of any length; cap it so the
            // award title keeps the room and the name ellipsizes instead.
            if (!below)
              ConstrainedBox(constraints: const BoxConstraints(maxWidth: 150), child: winner),
          ],
        );
      },
    );
  }
}
