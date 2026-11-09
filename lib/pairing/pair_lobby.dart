import 'dart:async';

import 'package:flutter/material.dart';

import '../nav.dart';
import '../profile/profile_service.dart';
import '../ui/banners.dart';
import '../ui/booth_icons.g.dart';
import '../ui/buttons.dart';
import '../ui/pt_motion.dart';
import '../ui/pt_theme.dart';
import 'pair_logic.dart';
import 'pair_models.dart';
import 'pair_screen.dart';
import 'pair_service.dart';
import 'pair_widgets.dart';

/// Everything pairing adds to the lobby, in one place so the lobby's four
/// layouts each carry a single line: a pairing request when one is waiting,
/// then Our Room (or the date night that is about to start), then the reunion
/// countdown - or, for a signed-in person who has not paired, one quiet way in.
///
/// Renders nothing for a guest and nothing while the pair has not loaded, so a
/// slow network never flashes an empty card.
class PairLobbySection extends StatelessWidget {
  const PairLobbySection({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PairService.instance,
      builder: (context, _) {
        final svc = PairService.instance;
        if (!svc.isSignedInAccount || !svc.loaded) return const SizedBox.shrink();

        // The gap that separates this from the forms below lives here, so a
        // guest - who sees nothing - does not get a double one.
        final gap = compact ? 22.0 : 36.0;
        final banner = svc.bannerInvite;
        if (!svc.isPaired) {
          return Padding(
            padding: EdgeInsets.only(bottom: gap),
            child: banner != null ? PairRequestBanner(invite: banner) : const PairTeaser(),
          );
        }

        final pair = svc.pair!;
        final now = DateTime.now().toUtc();
        final night = featuredNight(now, svc.nights);
        final reunion = pair.reunionOn == null
            ? null
            : reunionView(pair.reunionOn!, DateTime.now());
        return Padding(
          padding: EdgeInsets.only(bottom: gap),
          child: Column(
            crossAxisAlignment: .stretch,
            spacing: 12,
            children: [
              OurRoomCard(pair: pair, online: svc.partnerOnline, night: night, compact: compact),
              if (reunion != null && reunion.phase != ReunionPhase.past)
                ReunionCard(view: reunion, label: pair.reunionLabel),
            ],
          ),
        );
      },
    );
  }
}

/// "Sam wants to pair with you" - for an invite this person opened and has not
/// answered. Pair answers in place; Not now only stops the nagging for this run
/// (the invite itself lives its 48 hours).
class PairRequestBanner extends StatefulWidget {
  const PairRequestBanner({super.key, required this.invite});

  final PairInvite invite;

  @override
  State<PairRequestBanner> createState() => _PairRequestBannerState();
}

class _PairRequestBannerState extends State<PairRequestBanner> {
  bool _busy = false;

  Future<void> _accept() async {
    setState(() => _busy = true);
    try {
      await PairService.instance.acceptInvite(widget.invite.code);
      if (mounted) showPTSnack(context, 'You two are paired.', kind: .success);
    } catch (e) {
      if (mounted) {
        showPTSnack(context, PairErrorCode.fromError(e).message, kind: .error);
        setState(() => _busy = false);
      }
    }
  }

  String _sent(DateTime? at) {
    if (at == null) return 'Waiting for you';
    final d = DateTime.now().toUtc().difference(at);
    if (d.inMinutes < 2) return 'Just now';
    if (d.inHours < 1) return 'Sent ${d.inMinutes} min ago';
    if (d.inHours < 24) return 'Sent ${d.inHours} h ago';
    return 'Sent ${d.inDays} d ago';
  }

  @override
  Widget build(BuildContext context) {
    final inv = widget.invite;
    return PairPanel(
      live: true,
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 12,
        children: [
          Row(
            spacing: 12,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: PTColors.aisle,
                child: Text(
                  inv.inviter.displayName.characters.first.toUpperCase(),
                  style: PTText.cardHeading,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  spacing: 2,
                  children: [
                    Text(
                      '${inv.inviter.displayName} wants to pair with you',
                      style: PTText.cardHeading.copyWith(fontSize: 17, height: 1.15),
                    ),
                    Text(
                      _sent(inv.createdAt),
                      style: PTText.caption.copyWith(color: PTColors.fgSoft),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Row(
            spacing: 10,
            children: [
              Expanded(
                child: PTButton(
                  label: 'Not now',
                  variant: .secondary,
                  height: 42,
                  onPressed: _busy ? null : () => PairService.instance.dismissBanner(inv.code),
                ),
              ),
              Expanded(
                child: PTButton(label: 'Pair', height: 42, loading: _busy, onPressed: _accept),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A signed-in person with nobody paired: one line, never a banner.
class PairTeaser extends StatelessWidget {
  const PairTeaser({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Pair with your person',
      child: PTPressable(
        onTap: () => openPage(context, '/lobby/pair'),
        pressedScale: 0.985,
        child: PairPanel(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            spacing: 12,
            children: [
              const Icon(BoothIcons.heart, size: 20, color: PTColors.primary),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  spacing: 2,
                  children: [
                    Text(
                      'Watching with your person?',
                      style: PTText.panelHeading.copyWith(fontSize: 15),
                    ),
                    Text(
                      'A private room that is always yours. Got a code? Enter it inside.',
                      style: PTText.caption.copyWith(color: PTColors.fgSoft),
                    ),
                  ],
                ),
              ),
              const Icon(BoothIcons.chevronRight, size: 16, color: PTColors.fgMute),
            ],
          ),
        ),
      ),
    );
  }
}

/// The lobby's anchor for a pair: Our Room, with a Call button only while the
/// partner is actually on. In the last quarter hour before a date night it
/// becomes that night's card and takes Beam - amber is for live things.
class OurRoomCard extends StatefulWidget {
  const OurRoomCard({
    super.key,
    required this.pair,
    required this.online,
    this.night,
    this.compact = false,
  });

  final PairInfo pair;
  final bool online;
  final DateNight? night;
  final bool compact;

  @override
  State<OurRoomCard> createState() => _OurRoomCardState();
}

class _OurRoomCardState extends State<OurRoomCard> {
  Timer? _tick;
  bool _calling = false;

  @override
  void initState() {
    super.initState();
    // A minute is the finest thing the card says ("14 min"), so a minute is the
    // finest it needs to re-render.
    if (widget.night != null) {
      _tick = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _call() async {
    setState(() => _calling = true);
    try {
      await openOurRoom(context, call: true);
    } finally {
      if (mounted) setState(() => _calling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ProfileService.instance.profile;
    final partner = widget.pair.partner;
    final night = widget.night;
    final now = DateTime.now().toUtc();
    final imminent = night != null && isNightImminent(now, night);
    final live = widget.online || imminent;
    final first = (me?.displayName ?? 'You').split(' ').first;

    return PairPanel(
      live: live,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 14,
        children: [
          Row(
            children: [
              Expanded(
                child: PairKicker(
                  night == null ? 'Our Room' : 'Date night · ${night.title}',
                  color: live ? PTColors.primary : null,
                  oneLine: true,
                ),
              ),
              // The way back to the pair hub, said in words: the names row below
              // is a target too, but nothing about it says so.
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Semantics(
                    button: true,
                    excludeSemantics: true,
                    label: 'Your person',
                    child: PTPressable(
                      onTap: () => openPage(context, '/lobby/pair'),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisSize: .min,
                          spacing: 2,
                          children: [
                            Flexible(
                              child: Text(
                                'Your person',
                                maxLines: 1,
                                overflow: .ellipsis,
                                style: PTText.caption.copyWith(
                                  color: PTColors.link,
                                  fontWeight: .w500,
                                ),
                              ),
                            ),
                            // The label is mostly lowercase, so its optical centre is the
                            // x-height, a pixel below the glyph's own centre.
                            Transform.translate(
                              offset: const Offset(0, 1),
                              child: const Icon(
                                BoothIcons.chevronRight,
                                size: 14,
                                color: PTColors.link,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (night != null && imminent) ...[
                const SizedBox(width: 8),
                PairPill(
                  '${countdownTo(night.startsAt, now).minutes.clamp(0, 99)} min',
                  color: PTColors.primary,
                  fill: PTColors.pillWarning,
                ),
              ],
            ],
          ),
          Row(
            spacing: 14,
            children: [
              PairAvatars(
                myId: me?.id ?? '',
                myName: me?.displayName ?? 'You',
                myAvatarUrl: me?.avatarUrl,
                partner: partner,
                size: 44,
                partnerOnline: widget.online ? true : null,
              ),
              Expanded(
                child: Text(
                  '$first & ${partner.displayName.split(' ').first}',
                  style: PTText.cardHeading.copyWith(fontSize: widget.compact ? 22 : 24, height: 1),
                  maxLines: 1,
                  overflow: .ellipsis,
                ),
              ),
            ],
          ),
          Row(
            spacing: 8,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.online ? PTColors.online : PTColors.away,
                ),
              ),
              Expanded(
                child: Text(
                  widget.online
                      ? '${partner.displayName.split(' ').first} is on${_clock(partner)}'
                      : "${partner.displayName.split(' ').first} isn't on right now${_clock(partner)}",
                  style: PTText.body.copyWith(
                    fontSize: 14,
                    color: widget.online ? PTColors.online : PTColors.fgSoft,
                  ),
                  maxLines: 2,
                  overflow: .ellipsis,
                ),
              ),
            ],
          ),
          // The film its planner attached: ready, or on its way. Said only when it
          // is true and the night is close, so the card never promises early.
          if (night != null && imminent && night.attachmentReady)
            Row(
              spacing: 8,
              children: [
                const Icon(BoothIcons.check, size: 16, color: PTColors.online),
                Expanded(
                  child: Text(
                    'Your movie is ready',
                    style: PTText.caption.copyWith(color: PTColors.online),
                  ),
                ),
              ],
            )
          else if (night != null && imminent && night.hasFile && !night.fileStopped)
            Row(
              spacing: 8,
              children: [
                const Icon(BoothIcons.cloudUpload, size: 16, color: PTColors.warning),
                Expanded(
                  child: Text(
                    'Your movie is still arriving (${night.uploadPercent}%)',
                    style: PTText.caption.copyWith(color: PTColors.warning),
                  ),
                ),
              ],
            ),
          if (widget.online)
            LayoutBuilder(
              builder: (context, box) {
                // Two labels need roughly 300 px at normal size and grow with
                // the text; when they would not both fit, they stack.
                final scale = MediaQuery.textScalerOf(context).scale(15) / 15;
                final stack = box.maxWidth < 300 * scale.clamp(1.0, 2.0);
                final call = PTButton(
                  label: 'Call ${partner.displayName.split(' ').first}',
                  icon: BoothIcons.phone,
                  loading: _calling,
                  onPressed: _call,
                );
                final open = PTButton(
                  label: 'Open Our Room',
                  variant: .secondary,
                  onPressed: () => openOurRoom(context),
                );
                return stack
                    ? Column(crossAxisAlignment: .stretch, spacing: 10, children: [call, open])
                    : Row(
                        spacing: 10,
                        children: [
                          Expanded(child: call),
                          Expanded(child: open),
                        ],
                      );
              },
            )
          else
            PTButton(label: 'Open Our Room', onPressed: () => openOurRoom(context)),
        ],
      ),
    );
  }

  String _clock(PairPartner p) {
    final now = DateTime.now();
    if (!shouldShowPartnerTime(p.timezone, now)) return '';
    return ' · ${formatClock(wallClockIn(p.timezone, now)!)} there';
  }
}

/// "47 days until we are together" - a card, not a chip, because it is the
/// emotional anchor of the whole feature.
class ReunionCard extends StatelessWidget {
  const ReunionCard({super.key, required this.view, this.label});

  final ReunionView view;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final live = view.phase == ReunionPhase.today;
    final soon = view.phase == ReunionPhase.tomorrow;
    final (big, unit, kicker) = switch (view.phase) {
      ReunionPhase.today => ('0', 'days', 'Together'),
      ReunionPhase.tomorrow => ('1', 'day', 'Tomorrow'),
      _ => ('${view.daysLeft}', view.daysLeft == 1 ? 'day' : 'days', 'Until we are together'),
    };
    final line = switch (view.phase) {
      ReunionPhase.today => label ?? 'Today. Enjoy it.',
      ReunionPhase.tomorrow => label ?? 'Tomorrow. Pack the good headphones.',
      _ => label ?? '',
    };
    return PairPanel(
      live: live || soon,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 10,
        children: [
          Row(
            children: [
              Expanded(child: PairKicker(kicker, color: live || soon ? PTColors.primary : null)),
              const Icon(BoothIcons.reunion, size: 18, color: PTColors.fgDim),
            ],
          ),
          Row(
            crossAxisAlignment: .baseline,
            textBaseline: TextBaseline.alphabetic,
            spacing: 10,
            children: [
              Text(
                big,
                // A display numeral, clamped like the lobby headline: it is
                // already 64 px, and at 2x it outgrows a cover display.
                textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
                style: PTText.display.copyWith(
                  fontSize: 64,
                  height: 0.9,
                  color: live || soon ? PTColors.primary : PTColors.fg,
                ),
              ),
              Flexible(
                child: Text(
                  unit,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: PTText.body.copyWith(fontSize: 18, color: PTColors.fgSoft),
                ),
              ),
            ],
          ),
          if (line.isNotEmpty) Text(line, style: PTText.caption.copyWith(color: PTColors.fgSoft)),
        ],
      ),
    );
  }
}
