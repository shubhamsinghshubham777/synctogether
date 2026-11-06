import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../ui/booth_icons.g.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:synctogether/rooms/room_models.dart';
import 'package:synctogether/sync/sync_service.dart';
import 'package:synctogether/ui/booth.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/identity.dart';
import 'package:synctogether/ui/pt_motion.dart';
import 'package:synctogether/ui/pt_theme.dart';
import 'package:synctogether/ui/responsive.dart';

import '../../rewards/rewards_models.dart';

/// What one member's readiness looks like in the roster.
class ReadinessChipStyle {
  const ReadinessChipStyle(this.label, this.color);

  final String label;
  final Color color;

  /// A member who is "ready" but holding the wrong file reads as a problem, not
  /// as progress - the gate treats them the same way.
  static ReadinessChipStyle of(PresentMember member, RoomMedia media) {
    if (media.kind == .local && member.isReady && gateMatchOf(member, media) == null) {
      return ReadinessChipStyle(
        'Wrong file · ${member.loadedFileName ?? 'nothing'}',
        PTColors.danger,
      );
    }
    return switch (member.readyStatus) {
      ReadyStatus.ready => const ReadinessChipStyle('Ready', PTColors.online),
      ReadyStatus.loading => const ReadinessChipStyle('Loading', PTColors.textAccent),
      ReadyStatus.selecting => const ReadinessChipStyle('Choosing…', PTColors.textAccent),
      ReadyStatus.none => ReadinessChipStyle('Not ready', PTColors.white(0.5)),
    };
  }
}

/// Covers the video surface while the readiness gate is shut. Scoped to the
/// video only, on purpose (D2): chat, facecams and the member list stay
/// usable while the room waits.
///
/// [reveal] drives the whole in/out animation, 0 → 1. The panel animates
/// cleanly; the scrim is a plain colour and animates freely.
class ReadinessOverlay extends StatelessWidget {
  const ReadinessOverlay({
    super.key,
    required this.headline,
    required this.members,
    required this.media,
    required this.selfId,
    required this.selfIsHost,
    required this.onLocateFile,
    required this.onKick,
    this.openFailed = false,
    this.onStartWithout,
    this.startWithoutLabel,
    this.onPickSource,
    this.pickSourceLabel = 'Choose a video',
    this.onSwitchSource,
    this.switchSourceLabel = 'Use a YouTube link instead',
    this.switchSourceShortLabel = 'YouTube link',
    this.reopenName,
    this.reopenAgo,
    this.onReopen,
    this.onPickPhotos,
    this.onPickFiles,
    this.compact = false,
    this.chromeInsets = EdgeInsets.zero,
    this.reveal = 1,
    this.premiumMembers = const {},
    this.memberFrames = const {},
    this.uploadProgressWidget,
  });

  final String headline;
  final List<PresentMember> members;
  final RoomMedia media;
  final String selfId;
  final bool selfIsHost;
  final Widget? uploadProgressWidget;

  /// Null unless *we* are the one who needs to find their copy.
  final VoidCallback? onLocateFile;

  /// The file we have already tried to open would not. Pointing at the same
  /// copy again goes nowhere, so the action becomes choosing a different video.
  final bool openFailed;
  final void Function(PresentMember member)? onKick;

  final VoidCallback? onStartWithout;
  final String? startWithoutLabel;

  /// Host only, in a room with nothing set: the way out of the empty state.
  /// Null for everyone else, who just wait (no dead-end button).
  final VoidCallback? onPickSource;
  final String pickSourceLabel;

  /// The other source. Dropped in the dense form - the room menu carries
  /// "Switch source" there - so the one button that matters always fits.
  final VoidCallback? onSwitchSource;
  final String switchSourceLabel;
  final String switchSourceShortLabel;

  /// The empty room's "Reopen (last file)" line (board 47/48): the newest entry
  /// in Recent, one tap to play it again. Null hides the line.
  final String? reopenName;

  /// Mono kicker beside it ("2H AGO").
  final String? reopenAgo;
  final VoidCallback? onReopen;

  /// Touch tablets, where the card is roomy: Photos and Files get their own
  /// buttons under the primary one (board 47, tablet empty room), skipping the
  /// chooser. Null everywhere else - the one primary button opens the chooser.
  final VoidCallback? onPickPhotos;
  final VoidCallback? onPickFiles;
  final bool compact;

  /// The part of the video box covered by floating chrome; the card sits in
  /// what is left, anchored to its bottom edge (boards 47/48).
  final EdgeInsets chromeInsets;
  final double reveal;
  final Set<String> premiumMembers;
  final Map<String, AvatarFrame> memberFrames;

  @override
  Widget build(BuildContext context) {
    final t = reveal.clamp(0.0, 1.0);
    var row = 0;
    // The scrim is full-bleed; the card keeps clear of whatever system insets
    // reach it (none, once a parent SafeArea has consumed them) and of the
    // floating chrome.
    final system = MediaQuery.paddingOf(context);
    final roomy = EdgeInsets.all(compact ? 12 : 16) + system + chromeInsets;
    return LayoutBuilder(
      builder: (context, box) {
        // Tightest: a short window or big text leaves a sliver once the chrome
        // is subtracted. The empty state's button is the one thing that must
        // stay reachable, so the headline (the button names the job) and the
        // panel's breathing room give way. The bottom keeps system and chrome
        // additive - the control bar floats above the system inset, so
        // overlapping them would put the card under the bar.
        final tight = onPickSource != null && box.maxHeight - roomy.vertical < 130;
        final padding = tight
            ? EdgeInsets.fromLTRB(
                system.left + chromeInsets.left + 4,
                math.max(system.top, chromeInsets.top) + 4,
                system.right + chromeInsets.right + 4,
                system.bottom + chromeInsets.bottom + 4,
              )
            : roomy;
        // Dense: the video box is a phone's strip (or the chrome leaves little
        // of it). A roster that could never show cannot be the reason the
        // buttons scroll out of reach - it lives in the member list anyway.
        final room = box.maxHeight - padding.vertical;
        final dense = room < 300;
        // Side-by-side buttons only while both labels fit whole; the empty
        // state's pair has longer labels, so it asks for more.
        final needed = onPickSource != null ? 310.0 : 330.0;
        // The card is capped at 460 and pads itself, so what the buttons really
        // get is that, not the whole box.
        final inner =
            math.min(460.0, box.maxWidth - padding.horizontal) -
            2 * (tight ? 8 : (compact ? 18 : 24));
        final sideBySide = inner >= MediaQuery.textScalerOf(context).scale(needed);
        return _build(
          context,
          t,
          padding,
          dense,
          sideBySide,
          room < 200 ? 2 : 3,
          () => row++,
          tight: tight,
          roomyEnough: inner >= MediaQuery.textScalerOf(context).scale(400),
        );
      },
    );
  }

  Widget _build(
    BuildContext context,
    double t,
    EdgeInsets padding,
    bool dense,
    bool sideBySide,
    int headlineLines,
    int Function() nextRow, {
    bool tight = false,
    bool roomyEnough = false,
  }) {
    // The empty room's pair reads "Choose a video | YouTube link" side by side
    // when both fit (board 48), so its secondary always uses the short label.
    final emptyRoom = onPickSource != null;
    final threeWays =
        emptyRoom &&
        !compact &&
        roomyEnough &&
        onPickPhotos != null &&
        onPickFiles != null &&
        onSwitchSource != null &&
        !tight;
    final pairRow = emptyRoom && !threeWays && onSwitchSource != null && !tight && sideBySide;
    final actions = [
      if (onPickSource != null)
        PTButton(
          label: pickSourceLabel,
          icon: pickSourceLabel.contains('YouTube') ? BoothIcons.youtube : BoothIcons.file,
          expand: true,
          onPressed: onPickSource,
        ),
      if (threeWays)
        Row(
          spacing: 8,
          children: [
            Expanded(
              child: _WayButton(label: 'From Photos', icon: BoothIcons.image, onTap: onPickPhotos!),
            ),
            Expanded(
              child: _WayButton(label: 'From Files', icon: BoothIcons.folder, onTap: onPickFiles!),
            ),
            Expanded(
              child: _WayButton(label: switchSourceShortLabel, onTap: onSwitchSource!),
            ),
          ],
        )
      // Dense and narrow, or tight: the room menu carries "Switch source".
      else if (onPickSource != null && onSwitchSource != null && !tight && (!dense || sideBySide))
        PTButton(
          label: dense || (emptyRoom && sideBySide) ? switchSourceShortLabel : switchSourceLabel,
          variant: .secondary,
          expand: true,
          onPressed: onSwitchSource,
        ),
      if (emptyRoom && onReopen != null && reopenName != null && !tight)
        _ReopenLine(name: reopenName!, ago: reopenAgo, onTap: onReopen!),
      if (onLocateFile != null)
        PTButton(
          // Just the action - the headline directly above already names the
          // file, and release names are long enough to swamp the panel.
          label: openFailed
              ? 'Choose a different video'
              : (dense ? 'Locate copy' : 'Locate your copy'),
          icon: BoothIcons.file,
          expand: true,
          onPressed: onLocateFile,
        ),
      if (onStartWithout != null)
        PTButton(
          label: dense ? 'Start anyway' : (startWithoutLabel ?? 'Start without them'),
          icon: Symbols.fast_forward_rounded,
          variant: .secondary,
          expand: true,
          onPressed: onStartWithout,
        ),
    ];
    return Container(
      color: PTColors.scrimBase.withValues(alpha: 0.7 * t),
      padding: padding,
      // Bottom-anchored, never centred (boards 47/48): the card rests a gutter
      // above the picture's bottom edge - or above the floating control bar
      // via [chromeInsets] - full width on a phone, capped and centred on a
      // roomy box. `reverse` keeps the bottom edge pinned when the card is
      // taller than the gap and scrolls instead of clipping.
      child: Align(
        alignment: .bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          // Infinite width clamps to the constraint: full width up to the cap.
          child: SizedBox(
            width: double.infinity,
            child: SingleChildScrollView(
              reverse: true,
              child: Transform.scale(
                scale: 0.96 + 0.04 * t,
                child: GlassPanel(
                  radius: compact ? 20 : 24,
                  baseColor: PTColors.surfaceBase,
                  borderColor: PTColors.white(0.14 * t),
                  shadow: false,
                  padding: EdgeInsets.all(tight ? 8 : (compact ? 18 : 24)),
                  child: Opacity(
                    opacity: t,
                    child: Column(
                      mainAxisSize: .min,
                      crossAxisAlignment: .stretch,
                      spacing: tight ? 0 : (compact ? 14 : 18),
                      children: [
                        if (!tight)
                          Row(
                            crossAxisAlignment: .start,
                            spacing: 12,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 1),
                                child: Icon(
                                  Symbols.hourglass_top_rounded,
                                  size: compact ? 19 : 22,
                                  color: PTColors.textAccent,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  headline,
                                  maxLines: dense ? headlineLines : null,
                                  overflow: dense ? .ellipsis : null,
                                  // Media names run long ("Movie.2005.1080p.BluRay…"), and
                                  // at the headline size they turn the panel into a wall
                                  // of bold text. Step down once past a sentence or so.
                                  style: PTText.body.copyWith(
                                    fontSize: headline.length > 90
                                        ? (compact ? 13 : 14)
                                        : (compact ? 14.5 : 16),
                                    fontWeight: .w600,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        if (uploadProgressWidget != null) uploadProgressWidget!,
                        if (members.isNotEmpty && !dense)
                          Column(
                            mainAxisSize: .min,
                            children: [
                              for (final member in members)
                                // Watching friends' chips flip green one by one is the
                                // "we're all here" moment; stagger the roster so it
                                // assembles rather than appearing whole.
                                PTEntrance(
                                  delay: Duration(milliseconds: 40 * nextRow()),
                                  offset: 8,
                                  child: _MemberStatusRow(
                                    member: member,
                                    media: media,
                                    premium: premiumMembers.contains(member.userId),
                                    frame: memberFrames[member.userId],
                                    isSelf: member.userId == selfId,
                                    compact: compact,
                                    // Reserve the kick column on every row, not just the
                                    // kickable ones, so the status chips share a left
                                    // edge instead of jumping about per row.
                                    reserveKickSlot: selfIsHost,
                                    onKick: selfIsHost && member.userId != selfId && !member.isHost
                                        ? () => onKick?.call(member)
                                        : null,
                                  ),
                                ),
                            ],
                          ),
                        if (pairRow)
                          // The empty room: primary and YouTube link share a row.
                          Row(
                            spacing: 10,
                            children: [for (final a in actions.take(2)) Expanded(child: a)],
                          )
                        else if (dense && sideBySide && actions.length > 1)
                          Row(spacing: 10, children: [for (final a in actions) Expanded(child: a)])
                        else
                          ...actions,
                        if (pairRow) ...actions.skip(2),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MemberStatusRow extends StatelessWidget {
  const _MemberStatusRow({
    required this.member,
    required this.media,
    required this.premium,
    this.frame,
    required this.isSelf,
    required this.compact,
    required this.reserveKickSlot,
    required this.onKick,
  });

  final PresentMember member;
  final RoomMedia media;
  final bool premium;
  final AvatarFrame? frame;
  final bool isSelf;
  final bool compact;
  final bool reserveKickSlot;
  final VoidCallback? onKick;

  static const _kickSlot = 32.0;

  @override
  Widget build(BuildContext context) {
    final status = ReadinessChipStyle.of(member, media);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        spacing: 10,
        children: [
          // The ring turns Cue and ripples once as this member clears the
          // gate - the room seeing them arrive.
          ReadyRing(
            diameter: 30,
            ready: status.color == PTColors.online,
            clip: false,
            child: PTAvatar(
              userId: member.userId,
              displayName: member.displayName,
              avatarUrl: member.avatarUrl,
              size: 30,
              premium: premium,
              frame: frame,
            ),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: member.displayName,
                children: [
                  if (isSelf)
                    TextSpan(
                      text: ' (you)',
                      style: TextStyle(fontWeight: .w400, color: PTColors.white(0.45)),
                    )
                  else if (member.privacyMode)
                    TextSpan(
                      text: ' · screen hidden',
                      style: TextStyle(fontWeight: .w400, color: PTColors.white(0.45)),
                    ),
                ],
              ),
              overflow: .ellipsis,
              style: PTText.body.copyWith(fontSize: 13.5, fontWeight: .w500),
            ),
          ),
          // Fixed-width column, left-aligned: chips vary a lot in width
          // ("Ready" vs "Wrong file · …"), and letting them size themselves
          // made every row start its chip somewhere different.
          SizedBox(
            width: compact ? 128 : 156,
            child: Align(
              alignment: .centerLeft,
              child: _StatusChip(status: status),
            ),
          ),
          if (onKick != null)
            PTIconButton(
              icon: BoothIcons.personRemove,
              glass: false,
              size: _kickSlot,
              iconSize: 17,
              tooltip: 'Remove ${member.displayName}',
              onPressed: onKick,
            )
          else if (reserveKickSlot)
            // Matches the kick button's real footprint, which grows to the
            // touch minimum on touch input.
            SizedBox(width: inputOf(context) == .touch ? kMinTouchTarget : _kickSlot),
        ],
      ),
    );
  }
}

/// Loading → Ready → Wrong file, animated. The label swaps through an
/// `AnimatedSwitcher`, so
/// a member going green reads as a change of state rather than a redraw.
/// The chip's width is fixed by its parent, so nothing reflows as labels swap.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final ReadinessChipStyle status;

  @override
  Widget build(BuildContext context) {
    // A mono readout in the status colour, not a pill - pills are for people.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: AnimatedSwitcher(
        duration: PTMotion.functional(context, PTMotion.state),
        switchInCurve: PTMotion.enter,
        switchOutCurve: PTMotion.exit,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(animation),
            child: child,
          ),
        ),
        child: Text(
          status.label.toUpperCase(),
          key: ValueKey(status.label),
          overflow: .ellipsis,
          style: PTText.label.copyWith(fontSize: 12, letterSpacing: 1, color: status.color),
        ),
      ),
    );
  }
}

/// "Reopen NAME 2H AGO": the newest Recent entry as a quiet one-tap line
/// under the empty room's choices. Cue teal because it is the thing that is
/// ready; the name is the only bold part.
class _ReopenLine extends StatelessWidget {
  const _ReopenLine({required this.name, required this.ago, required this.onTap});

  final String name;
  final String? ago;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Reopen $name',
      excludeSemantics: true,
      child: PTPressable(
        onTap: onTap,
        pressedScale: 0.99,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
          decoration: BoxDecoration(
            color: PTColors.well,
            borderRadius: BorderRadius.circular(PTRadius.control),
            border: Border.all(color: PTColors.aisle),
          ),
          child: Row(
            spacing: 10,
            children: [
              const Icon(BoothIcons.restore, size: 18, color: PTColors.online),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(
                        text: 'Reopen ',
                        style: TextStyle(color: PTColors.fgMute),
                      ),
                      TextSpan(
                        text: name,
                        style: const TextStyle(fontWeight: .w600, color: PTColors.fg),
                      ),
                    ],
                  ),
                  maxLines: 2,
                  overflow: .ellipsis,
                  style: PTText.body.copyWith(fontSize: 13),
                ),
              ),
              if (ago != null)
                Text(ago!, style: PTText.label.copyWith(fontSize: 10.5, color: PTColors.fgMute)),
            ],
          ),
        ),
      ),
    );
  }
}

/// One of the tablet empty room's three ways in (board 47): an outlined 44 pt
/// key with a Beam glyph, quieter than the primary button above it.
class _WayButton extends StatelessWidget {
  const _WayButton({required this.label, required this.onTap, this.icon});

  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: PTPressable(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PTRadius.control),
            border: Border.all(color: PTColors.rail),
          ),
          child: Row(
            mainAxisAlignment: .center,
            spacing: 8,
            children: [
              if (icon != null) Icon(icon, size: 16, color: PTColors.primary),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: PTText.body.copyWith(
                    fontSize: 13.5,
                    fontWeight: .w600,
                    color: PTColors.fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
