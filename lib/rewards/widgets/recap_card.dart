import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../diagnostics.dart';
import '../../ui/banners.dart';
import '../../ui/booth.dart';
import '../../ui/buttons.dart';
import '../../ui/glass.dart';
import '../../ui/identity.dart';
import '../../ui/pt_motion.dart';
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
        showPTSnack(context, 'Link copied. Paste it anywhere.', kind: .success);
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
          eyebrow: "Tonight's recap",
          title: 'In sync with ${recap.peakMembers - 1} other${recap.peakMembers == 2 ? '' : 's'}',
          subtitle: '${formatWatchTime(recap.length)} together, start to finish.',
          onClose: () => Navigator.of(context).pop(_url != null),
        ),
        const SizedBox(height: 20),
        // The night as a paper stub: stats on Screen with Booth ink, torn
        // along a perforation, the first award pressed onto it.
        _RecapStub(
          recap: recap,
          lead: recap.superlatives.firstOrNull,
          leadIsSelf: recap.superlatives.firstOrNull?.userId == widget.selfId,
        ),
        if (recap.superlatives.length > 1) ...[
          const SizedBox(height: 16),
          for (final (i, superlative) in recap.superlatives.skip(1).indexed)
            PTEntrance(
              delay: _awardDelay(i + 1),
              duration: PTMotion.state,
              offset: 8,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _AwardRow(
                  superlative: superlative,
                  person: widget.people[superlative.userId],
                  isSelf: superlative.userId == widget.selfId,
                  stampDelay: _awardDelay(i + 1) + const Duration(milliseconds: 120),
                ),
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

/// Awards follow the stats' count-up, one beat apart.
Duration _awardDelay(int i) => Duration(milliseconds: 500 + 110 * i);

class _RecapStub extends StatelessWidget {
  const _RecapStub({required this.recap, this.lead, this.leadIsSelf = false});

  final SessionRecap recap;
  final Superlative? lead;
  final bool leadIsSelf;

  static const countUp = Duration(milliseconds: 900);

  @override
  Widget build(BuildContext context) {
    const ink = PTColors.canvas;
    final soft = PTColors.canvas.withValues(alpha: 0.6);
    // Each value is a function of the count-up's progress, so the numbers
    // roll up from zero once as the card lands. One-shot; reduce motion
    // lands on the final numbers at once.
    final stats = <(String Function(double), String)>[
      ((t) => formatWatchTime(recap.length * t), 'WATCHED'),
      ((t) => '${(recap.reactions * t).round()}', 'REACTIONS'),
      ((t) => '${(recap.messages * t).round()}', 'MESSAGES'),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: PTColors.fg,
        borderRadius: BorderRadius.circular(PTRadius.panel),
      ),
      child: Column(
        crossAxisAlignment: .start,
        children: [
          Text('ADMIT ${recap.peakMembers} · TONIGHT', style: PTText.label.copyWith(color: soft)),
          const SizedBox(height: 10),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: reducedMotion(context) ? 1 : 0, end: 1),
            duration: countUp,
            curve: PTMotion.enter,
            builder: (context, t, _) => Wrap(
              spacing: 22,
              runSpacing: 10,
              children: [
                for (final (value, label) in stats)
                  Column(
                    crossAxisAlignment: .start,
                    spacing: 2,
                    children: [
                      Text(
                        value(t),
                        style: PTText.display.copyWith(
                          fontSize: 24,
                          letterSpacing: -0.6,
                          color: ink,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(label, style: PTText.label.copyWith(fontSize: 10, color: soft)),
                    ],
                  ),
              ],
            ),
          ),
          if (lead != null) ...[
            const SizedBox(height: 14),
            // The perforation.
            SizedBox(
              height: 1,
              width: double.infinity,
              child: CustomPaint(painter: DashedRectPainter(color: soft, dash: 5, gap: 4)),
            ),
            const SizedBox(height: 14),
            Row(
              spacing: 14,
              children: [
                PTStamp(
                  size: 52,
                  color: PTColors.liveInk,
                  angle: -0.12,
                  delay: _awardDelay(0),
                  child: Icon(superlativeIcon(lead!.key), size: 22, fill: 1),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: .start,
                    spacing: 2,
                    children: [
                      Text(
                        '${leadIsSelf ? 'You' : lead!.displayName} · ${lead!.key.title}',
                        maxLines: 2,
                        overflow: .ellipsis,
                        style: PTText.body.copyWith(fontSize: 14, fontWeight: .w600, color: ink),
                      ),
                      Text(
                        lead!.key.blurb,
                        style: PTText.finePrint.copyWith(fontSize: 11.5, color: soft),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AwardRow extends StatelessWidget {
  const _AwardRow({
    required this.superlative,
    this.person,
    this.isSelf = false,
    this.stampDelay = Duration.zero,
  });

  final Duration stampDelay;
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
            PTStamp(
              size: 34,
              color: PTColors.primary,
              angle: -0.12,
              delay: stampDelay,
              child: Icon(superlativeIcon(superlative.key), size: 17, fill: 1),
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
