import 'package:flutter/material.dart';

import '../ui/booth_icons.g.dart';
import '../ui/glass.dart';
import '../ui/identity.dart';
import '../ui/pt_motion.dart';
import '../ui/pt_theme.dart';
import 'pair_logic.dart';
import 'pair_models.dart';

/// `// LABEL` kicker over a section.
class PairKicker extends StatelessWidget {
  const PairKicker(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: PTText.label.copyWith(color: color ?? PTColors.fgMute));
}

/// A Seat panel with the pair screens' standard padding.
class PairPanel extends StatelessWidget {
  const PairPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.live = false,
    this.brass = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Beam hairline: the one lit thing on the screen.
  final bool live;

  /// Brass hairline: a Patron-gated surface.
  final bool brass;

  @override
  Widget build(BuildContext context) => GlassPanel(
    padding: padding,
    borderColor: live
        ? PTColors.primary.withValues(alpha: 0.35)
        : brass
        ? PTColors.premiumBorder.withValues(alpha: 0.5)
        : null,
    child: child,
  );
}

/// A tappable row inside a panel: glyph, title, optional value, chevron.
class PairRow extends StatelessWidget {
  const PairRow({
    super.key,
    required this.icon,
    required this.title,
    this.value,
    this.valueColor,
    this.onTap,
    this.destructive = false,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? value;
  final Color? valueColor;
  final VoidCallback? onTap;
  final bool destructive;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? PTColors.danger : PTColors.fg;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        spacing: 12,
        children: [
          Icon(icon, size: 20, color: destructive ? PTColors.danger : PTColors.fgDim),
          Expanded(
            child: Text(
              title,
              style: PTText.body.copyWith(color: color, fontSize: 15),
              maxLines: 2,
              overflow: .ellipsis,
            ),
          ),
          // Flexible, not fixed: at a large text size on a narrow screen the
          // value gives way (and ellipsizes) before the title does.
          ?(value == null
              ? null
              : Flexible(
                  child: Text(
                    value!,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: PTText.mono.copyWith(fontSize: 12, color: valueColor ?? PTColors.fgMute),
                  ),
                )),
          ?trailing,
          if (onTap != null && trailing == null)
            const Icon(BoothIcons.chevronRight, size: 16, color: PTColors.fgMute),
        ],
      ),
    );
    if (onTap == null) return row;
    return Semantics(
      button: true,
      label: title,
      child: PTPressable(onTap: onTap, pressedScale: 0.985, child: row),
    );
  }
}

class PairDivider extends StatelessWidget {
  const PairDivider({super.key});

  @override
  Widget build(BuildContext context) => const Divider(height: 1, color: PTColors.rail);
}

/// The two avatars side by side, you then them.
class PairAvatars extends StatelessWidget {
  const PairAvatars({
    super.key,
    required this.myId,
    required this.myName,
    this.myAvatarUrl,
    required this.partner,
    this.size = 44,
    this.partnerOnline,
  });

  final String myId;
  final String myName;
  final String? myAvatarUrl;
  final PairPartner partner;
  final double size;
  final bool? partnerOnline;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size * 1.7,
    height: size,
    child: Stack(
      children: [
        PTAvatar(
          userId: myId,
          displayName: myName,
          avatarUrl: myAvatarUrl,
          size: size,
          ringColor: PTColors.glassBase,
        ),
        Positioned(
          left: size * 0.7,
          child: PTAvatar(
            userId: partner.id,
            displayName: partner.displayName,
            avatarUrl: partner.avatarUrl,
            size: size,
            presence: partnerOnline,
            ringColor: PTColors.glassBase,
          ),
        ),
      ],
    ),
  );
}

/// Your person's clock - and nothing at all when it is the same clock as yours.
class PartnerClockLine extends StatelessWidget {
  const PartnerClockLine({super.key, required this.partner, this.now});

  final PairPartner partner;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final at = now ?? DateTime.now();
    if (!shouldShowPartnerTime(partner.timezone, at)) return const SizedBox.shrink();
    final wall = wallClockIn(partner.timezone, at)!;
    final diff = offsetFromMe(partner.timezone, at)!;
    return Row(
      spacing: 10,
      children: [
        const Icon(BoothIcons.globe, size: 18, color: PTColors.fgDim),
        // City over its offset, the clock on the right: nothing here has to
        // truncate, however long the zone name or the text size.
        Expanded(
          child: Column(
            crossAxisAlignment: .start,
            spacing: 1,
            children: [
              Text(
                cityOfZone(partner.timezone),
                maxLines: 1,
                overflow: .ellipsis,
                style: PTText.body.copyWith(color: PTColors.fg, fontSize: 14),
              ),
              Text(
                offsetLabel(diff),
                maxLines: 1,
                overflow: .ellipsis,
                style: PTText.caption.copyWith(color: PTColors.fgMute, fontSize: 12),
              ),
            ],
          ),
        ),
        Text(formatClock(wall), style: PTText.mono.copyWith(fontSize: 15, color: PTColors.fg)),
      ],
    );
  }
}

/// A small mono pill: ONLINE, 14 MIN, SAM IN.
class PairPill extends StatelessWidget {
  const PairPill(this.text, {super.key, this.color = PTColors.online, this.fill});

  final String text;
  final Color color;
  final Color? fill;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: fill ?? PTColors.bannerSuccess,
      borderRadius: BorderRadius.circular(PTRadius.pill),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Text(
      text.toUpperCase(),
      style: PTText.mono.copyWith(fontSize: 10, letterSpacing: 1, color: color),
    ),
  );
}

/// A Brass PATRON tag for gated surfaces.
class PatronTag extends StatelessWidget {
  const PatronTag({super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(2),
      border: Border.all(color: PTColors.premiumBorder),
    ),
    child: Text(
      'PATRON',
      style: PTText.mono.copyWith(fontSize: 9, letterSpacing: 1, color: PTColors.premium),
    ),
  );
}

/// A dim notice line with an optional leading glyph.
class PairNote extends StatelessWidget {
  const PairNote(this.text, {super.key, this.center = false, this.color});

  final String text;
  final bool center;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: center ? TextAlign.center : TextAlign.start,
    style: PTText.finePrint.copyWith(color: color ?? PTColors.fgMute, height: 1.5),
  );
}

/// A mono "tag" chip: LOCAL FILE, YOUTUBE.
class PairTag extends StatelessWidget {
  const PairTag(this.text, {super.key, this.color = PTColors.fgSoft});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: PTColors.aisle, borderRadius: BorderRadius.circular(2)),
    child: Text(
      text.toUpperCase(),
      style: PTText.mono.copyWith(fontSize: 9, letterSpacing: 1, color: color),
    ),
  );
}
