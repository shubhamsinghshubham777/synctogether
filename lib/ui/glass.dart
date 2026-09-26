import 'dart:math' as math;
import 'booth_icons.g.dart';

import 'package:flutter/material.dart';

import 'buttons.dart';

import 'pt_motion.dart';
import 'pt_theme.dart';

/// A Booth Light panel: an opaque Seat surface with a hairline Rail border.
///
/// The name survives from the glass system so every call site keeps working,
/// but nothing blurs any more - elevation is lightness (Seat -> Aisle), not a
/// BackdropFilter. That also retires the old trap where fading a panel made
/// its blur sample an empty layer, and the per-frame cost of blurring over
/// playing video.
///
/// [opacity] and [blur] are accepted for compatibility and ignored: a
/// translucent panel with no blur would let the video bleed through the text.
/// Radii are normalised onto the Booth scale ([PTRadius]): pills stay pills,
/// anything else becomes a tight panel corner.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.radius = PTRadius.panel,
    this.opacity = 1,
    this.blur = 0,
    this.baseColor,
    this.borderColor,
    this.padding,
    this.shadow = false,
    this.clipBehavior = Clip.antiAlias,
  });

  /// Dialog panel: the same surface, lifted off the scrim by a soft shadow.
  const GlassPanel.dialog({
    super.key,
    required this.child,
    this.radius = PTRadius.panel,
    this.opacity = 1,
    this.blur = 0,
    this.baseColor = PTColors.dialogGlassBase,
    this.borderColor,
    this.padding,
    this.shadow = true,
    this.clipBehavior = Clip.antiAlias,
  });

  final Widget child;
  final double radius;
  final double opacity;
  final double blur;
  final Color? baseColor;
  final Color? borderColor;
  final EdgeInsetsGeometry? padding;
  final bool shadow;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(boothRadius(radius));
    return Container(
      padding: padding,
      clipBehavior: clipBehavior,
      decoration: BoxDecoration(
        color: baseColor ?? PTColors.glassBase,
        borderRadius: borderRadius,
        border: Border.all(color: borderColor ?? PTColors.rail),
        boxShadow: shadow
            ? const [BoxShadow(color: PTColors.shadowSoft, blurRadius: 40, offset: Offset(0, 16))]
            : null,
      ),
      child: child,
    );
  }
}

/// Maps a legacy radius onto the Booth scale: pills stay pills, small
/// corners stay small, everything else becomes [PTRadius.panel].
@visibleForTesting
double boothRadius(double radius) {
  if (radius >= 100) return radius;
  if (radius <= PTRadius.control) return radius;
  return PTRadius.panel;
}

class GlassPill extends StatelessWidget {
  const GlassPill({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
    this.onTap,
    this.opacity = 0.55,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    // Named for its old shape. Booth Light keeps full pills for people and
    // presence only, so chrome chips take the panel corner.
    final pill = GlassPanel(radius: PTRadius.panel, padding: padding, child: child);
    if (onTap == null) return pill;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: PTPressable(onTap: onTap, child: pill),
    );
  }
}

/// The booth: a flat, warm canvas behind the lobby, login and profile. No
/// glow or wash - the room is dark, and the only light in it is the one thing
/// that is live.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: PTColors.screenBg),
      child: child,
    );
  }
}

/// Shows a dialog with the standard dark scrim + blur, glass shell provided by
/// [GlassPanel.dialog]. All redesigned dialogs go through this.
///
/// The shell owns fitting the dialog to the screen, so call sites only pick a
/// [width]:
/// - a 16px gutter on every side (plus safe area), so [width] is a cap, never
///   a demand - a 430 dialog on a 320 phone is 288 wide;
/// - the height stops at the keyboard, and follows it as it animates;
/// - the body scrolls by default. Pass `scrollable: false` for a body that
///   manages its own scrolling with a `Flexible`/`Expanded` child - those need
///   a bounded height, which a scroll view cannot give them;
/// - the default horizontal padding (and any explicit padding over 20) drops
///   to 20 below 400 logical pixels of screen width;
/// - `sheetOnCompact: true` presents it as a bottom sheet under 480 width, for
///   long forms that read better thumb-side on a phone.
/// - `dimBackground: false` drops the scrim and the backdrop blur, for a
///   dialog whose point is what is behind it (the subtitle style sheet previews
///   on the live video); [alignment] then docks it beside that content.
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  double width = 430,
  EdgeInsetsGeometry? padding,
  bool scrollable = true,
  bool sheetOnCompact = false,
  bool dimBackground = true,
  AlignmentGeometry alignment = Alignment.center,
}) {
  bool isSheet(BuildContext context) =>
      sheetOnCompact && MediaQuery.sizeOf(context).width < kGlassSheetBreakpoint;

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: 'dialog',
    barrierColor: dimBackground ? PTColors.barrier : PTColors.scrimClear,
    transitionDuration: PTMotion.panel,
    pageBuilder: (context, _, _) {
      final mq = MediaQuery.of(context);
      final sheet = isSheet(context);
      final bodyPadding = glassDialogPadding(padding, mq.size.width);
      Widget body(EdgeInsets extra) {
        final p = bodyPadding + extra;
        return scrollable
            ? SingleChildScrollView(padding: p, child: builder(context))
            : Padding(padding: p, child: builder(context));
      }

      if (sheet) return _GlassSheet(mq: mq, body: body);
      final inset = glassDialogInsets(mq);
      return AnimatedPadding(
        duration: PTMotion.functional(context, PTMotion.state),
        curve: PTMotion.enter,
        padding: inset,
        child: MediaQuery.removeViewInsets(
          context: context,
          removeBottom: true,
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            removeBottom: true,
            removeLeft: true,
            removeRight: true,
            child: Align(
              alignment: alignment,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: width),
                child: Material(
                  type: .transparency,
                  child: GlassPanel.dialog(child: body(EdgeInsets.zero)),
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: PTMotion.enter,
        reverseCurve: PTMotion.exit,
      );
      // Scale for a centred dialog, slide for a sheet - house lights, not a
      // pop. The scrim darkens the room; nothing blurs behind it.
      final Widget moved = isSheet(context)
          ? SlideTransition(
              position: Tween(begin: const Offset(0, 0.12), end: Offset.zero).animate(curved),
              child: child,
            )
          : ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(curved), child: child);
      return FadeTransition(opacity: curved, child: moved);
    },
  );
}

/// The compact form of a `sheetOnCompact` dialog: full width, docked to the
/// bottom edge (or the keyboard's top), 6px top corners over a Rail top edge,
/// and a drag handle - a downward fling dismisses it like any sheet. The
/// bottom safe area pads the content rather than the surface, so the Seat
/// runs under the home indicator while the actions stay above it.
/// Finds the compact sheet's surface in tests.
@visibleForTesting
const kGlassSheetKey = ValueKey('glass-sheet');

class _GlassSheet extends StatelessWidget {
  const _GlassSheet({required this.mq, required this.body});

  final MediaQueryData mq;
  final Widget Function(EdgeInsets extra) body;

  @override
  Widget build(BuildContext context) {
    final keyboard = mq.viewInsets.bottom;
    final keyboardUp = keyboard > mq.viewPadding.bottom;
    return AnimatedPadding(
      duration: PTMotion.functional(context, PTMotion.state),
      curve: PTMotion.enter,
      padding: EdgeInsets.only(
        top: mq.viewPadding.top + _gutter,
        bottom: keyboardUp ? keyboard : 0,
      ),
      child: MediaQuery.removeViewInsets(
        context: context,
        removeBottom: true,
        child: MediaQuery.removePadding(
          context: context,
          removeTop: true,
          removeBottom: true,
          removeLeft: true,
          removeRight: true,
          child: Align(
            alignment: .bottomCenter,
            child: Material(
              type: .transparency,
              child: Container(
                key: kGlassSheetKey,
                clipBehavior: Clip.antiAlias,
                decoration: const BoxDecoration(
                  color: PTColors.dialogGlassBase,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(PTRadius.panel)),
                  border: Border(top: BorderSide(color: PTColors.rail)),
                  boxShadow: [
                    BoxShadow(color: PTColors.shadowSoft, blurRadius: 40, offset: Offset(0, -8)),
                  ],
                ),
                child: Column(
                  mainAxisSize: .min,
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragEnd: (d) {
                        if ((d.primaryVelocity ?? 0) > 300) Navigator.of(context).maybePop();
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 2),
                        child: Center(
                          child: Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: PTColors.rail,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Flexible(
                      child: body(
                        EdgeInsets.only(
                          left: mq.viewPadding.left,
                          right: mq.viewPadding.right,
                          bottom: keyboardUp ? 0 : mq.viewPadding.bottom,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Below this width a `sheetOnCompact` dialog presents as a bottom sheet.
const double kGlassSheetBreakpoint = 480;

/// Below this width dialog padding tightens to [_compactHorizontalPadding].
const double kGlassCompactPaddingBreakpoint = 400;
const double _compactHorizontalPadding = 20;
const double _gutter = 16;

/// Space kept clear around a glass dialog: a 16px gutter inside the safe area,
/// and above the keyboard when it is up (the keyboard covers the bottom safe
/// area, so the two are not added).
@visibleForTesting
EdgeInsets glassDialogInsets(MediaQueryData mq) {
  final bottom = mq.viewInsets.bottom > mq.viewPadding.bottom
      ? mq.viewInsets.bottom
      : mq.viewPadding.bottom;
  return EdgeInsets.fromLTRB(
    mq.viewPadding.left + _gutter,
    mq.viewPadding.top + _gutter,
    mq.viewPadding.right + _gutter,
    bottom + _gutter,
  );
}

/// The dialog body's padding at [screenWidth]: the caller's (or the 32/30
/// default), with horizontal padding capped at 20 on narrow screens.
@visibleForTesting
EdgeInsets glassDialogPadding(EdgeInsetsGeometry? padding, double screenWidth) {
  final base = (padding ?? const EdgeInsets.symmetric(horizontal: 32, vertical: 30)).resolve(
    TextDirection.ltr,
  );
  if (screenWidth >= kGlassCompactPaddingBreakpoint) return base;
  return base.copyWith(
    left: base.left > _compactHorizontalPadding ? _compactHorizontalPadding : base.left,
    right: base.right > _compactHorizontalPadding ? _compactHorizontalPadding : base.right,
  );
}

/// Text scale for a dialog's heading. Headings follow the reader's text size
/// at half the rate past 1.0x - Android 14's non-linear font scaling, applied
/// by hand - so 2.0x body copy gets a 1.5x title. A title is already large; at
/// full 2.0x on a phone it breaks mid-word and pushes the content off screen.
TextScaler dialogHeadingScaler(BuildContext context) {
  final factor = MediaQuery.textScalerOf(context).scale(100) / 100;
  return TextScaler.linear(factor <= 1 ? factor : 1 + (factor - 1) / 2);
}

/// The title block every glass dialog opens with: an optional [leading] tile,
/// a [title] with an optional [subtitle], and an optional close button.
///
/// While the title fits on one line the leading tile, title and close button
/// share a centre line - the original design. Once it wraps, all three pin to
/// the top instead, so the close button stays in the corner rather than
/// floating halfway down a three-line heading.
class GlassDialogHeader extends StatelessWidget {
  const GlassDialogHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.eyebrowColor,
    this.subtitle,
    this.leading,
    this.onClose,
    this.closeTooltip = 'Close',
    this.centered = false,
    this.titleStyle,
    this.subtitleStyle,
    this.subtitleWidget,
    this.closeSize = 36,
    this.closeIconSize = 18,
    this.spacing = 12,
    this.titleGap = 2,
    this.closeGlass = false,
  });

  /// Whether the close button draws its glass disc.
  final bool closeGlass;

  /// Space between the title and its subtitle.
  final double titleGap;

  final String title;

  /// A mono uppercase kicker above the title (`// EYEBROW`), the Booth Light
  /// replacement for the old tinted icon tile. Pass it in any case; it is
  /// uppercased here.
  final String? eyebrow;

  /// Signal for a refusal, Brass for a Patron prompt; muted by default.
  final Color? eyebrowColor;
  final String? subtitle;

  /// Replaces [subtitle] when the line needs more than plain text.
  final Widget? subtitleWidget;
  final Widget? leading;
  final VoidCallback? onClose;
  final String closeTooltip;

  /// Centres the title (and balances the close button with a spacer).
  final bool centered;
  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;
  final double closeSize;
  final double closeIconSize;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final style =
        titleStyle ?? PTText.screenTitle.copyWith(fontSize: 22, height: 1.1, letterSpacing: -0.6);
    final scaler = dialogHeadingScaler(context);
    final align = centered ? TextAlign.center : TextAlign.start;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Room the title actually gets: the row minus the close button (twice
        // when centred, for the balancing spacer). The leading tile's width is
        // unknown here, so a leading header decides on the title alone.
        final reserved = onClose == null ? 0.0 : (closeSize + spacing) * (centered ? 2 : 1);
        final painter =
            TextPainter(
              text: TextSpan(text: title, style: style),
              textScaler: scaler,
              textDirection: TextDirection.ltr,
            )..layout(
              maxWidth: math.max(0, constraints.maxWidth - reserved - (leading != null ? 56 : 0)),
            );
        final wraps = painter.computeLineMetrics().length > 1;
        painter.dispose();

        final text = Column(
          crossAxisAlignment: centered ? .center : .start,
          mainAxisSize: .min,
          spacing: titleGap,
          children: [
            if (eyebrow != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  eyebrow!.toUpperCase(),
                  textAlign: align,
                  textScaler: scaler,
                  style: PTText.label.copyWith(color: eyebrowColor),
                ),
              ),
            Text(title, textAlign: align, textScaler: scaler, style: style),
            if (subtitleWidget != null)
              subtitleWidget!
            else if (subtitle != null)
              Text(subtitle!, textAlign: align, style: subtitleStyle ?? PTText.caption),
          ],
        );
        return Row(
          // An eyebrow makes the block two lines, so the close button pins to
          // the top corner beside it rather than floating mid-block.
          crossAxisAlignment: wraps || eyebrow != null ? .start : .center,
          spacing: spacing,
          children: [
            if (leading != null) leading!,
            // The balancing spacer only earns its width while the title fits
            // one line; once it wraps, the title gets that width back.
            if (centered && onClose != null && !wraps) SizedBox(width: closeSize),
            Expanded(child: text),
            if (onClose != null)
              PTIconButton(
                icon: BoothIcons.close,
                iconSize: closeIconSize,
                size: closeSize,
                tooltip: closeTooltip,
                glass: closeGlass,
                onPressed: onClose,
              ),
          ],
        );
      },
    );
  }
}

/// What a [DialogNote] is about, which decides its rule colour.
enum DialogNoteTone { neutral, premium, danger, live }

/// A note inside a dialog: a Rail-outlined box (Brass for Patron, Signal for
/// a warning) instead of the old tinted Beam fill. Tinted boxes read as
/// buttons in Booth Light, where fill is spent on the one lit control.
class DialogNote extends StatelessWidget {
  const DialogNote({
    super.key,
    required this.child,
    this.icon,
    this.tone = DialogNoteTone.neutral,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  });

  final Widget child;
  final IconData? icon;
  final DialogNoteTone tone;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final (Color border, Color ink) = switch (tone) {
      DialogNoteTone.neutral => (PTColors.rail, PTColors.white(0.6)),
      DialogNoteTone.premium => (PTColors.premiumBorder, PTColors.premium),
      DialogNoteTone.danger => (PTColors.dangerBorder.withValues(alpha: 0.6), PTColors.danger),
      DialogNoteTone.live => (PTColors.accentBorderSoft, PTColors.primary),
    };
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(PTRadius.panel),
        border: Border.all(color: border),
      ),
      child: DefaultTextStyle.merge(
        style: PTText.body.copyWith(fontSize: 13, height: 1.45, color: PTColors.white(0.78)),
        child: icon == null
            ? child
            : Row(
                crossAxisAlignment: .start,
                spacing: 10,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(icon, size: 18, color: ink),
                  ),
                  Expanded(child: child),
                ],
              ),
      ),
    );
  }
}

/// A selectable row in a dialog list: square-cornered ([PTRadius.control]),
/// hairline-ruled, with a Beam edge and check when selected. Replaces the old
/// rounded pill chips and tinted cards - pills are for people now.
class DialogOptionRow extends StatefulWidget {
  const DialogOptionRow({
    super.key,
    required this.label,
    required this.onTap,
    this.description,
    this.icon,
    this.selected = false,
    this.trailing,
    this.chevron = false,
    this.labelStyle,
    this.iconTile = false,
    this.borderless = false,
  });

  /// Sets [icon] on a 36px Booth tile in Beam, for a row that is one of a
  /// few big choices (the source picker) rather than an item in a list.
  final bool iconTile;

  /// Drops the Rail hairline while unselected: the row only earns an edge
  /// (Beam) when it is the selected one. For long lists of options.
  final bool borderless;

  final String label;
  final String? description;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;

  /// Replaces the check mark / chevron on the right.
  final Widget? trailing;

  /// Shows a chevron (a row that leads somewhere) when not selected.
  final bool chevron;
  final TextStyle? labelStyle;

  @override
  State<DialogOptionRow> createState() => _DialogOptionRowState();
}

class _DialogOptionRowState extends State<DialogOptionRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final selected = widget.selected;
    final lit = selected || (_hovered && enabled);
    final trailing =
        widget.trailing ??
        (selected
            ? const Icon(BoothIcons.check, size: 18, color: PTColors.primary)
            : widget.chevron
            ? Icon(BoothIcons.chevronRight, size: 18, color: PTColors.white(0.4))
            : null);
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: PTPressable(
          onTap: widget.onTap,
          pressedScale: 0.99,
          child: AnimatedContainer(
            duration: PTMotion.functional(context, PTMotion.hover),
            curve: PTMotion.enter,
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            decoration: BoxDecoration(
              color: lit ? PTColors.aisle : Colors.transparent,
              borderRadius: BorderRadius.circular(PTRadius.control),
              border: Border.all(
                color: selected
                    ? PTColors.primary
                    : widget.borderless
                    ? Colors.transparent
                    : PTColors.rail,
              ),
            ),
            child: Opacity(
              opacity: enabled ? 1 : 0.45,
              child: Row(
                spacing: 12,
                children: [
                  if (widget.icon != null && widget.iconTile)
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: PTColors.canvas,
                        borderRadius: BorderRadius.circular(PTRadius.control),
                      ),
                      child: Icon(widget.icon, size: 20, color: PTColors.primary),
                    )
                  else if (widget.icon != null)
                    Icon(
                      widget.icon,
                      size: 20,
                      color: selected ? PTColors.primary : PTColors.white(0.7),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: .start,
                      mainAxisSize: .min,
                      spacing: 2,
                      children: [
                        Text(
                          widget.label,
                          style:
                              widget.labelStyle ??
                              PTText.body.copyWith(
                                fontSize: 14.5,
                                fontWeight: .w600,
                                color: selected ? PTColors.fg : PTColors.white(0.88),
                              ),
                        ),
                        if (widget.description != null)
                          Text(widget.description!, style: PTText.caption.copyWith(fontSize: 12.5)),
                      ],
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A quiet dialog action: underlined text, no box. For "Maybe later",
/// "Reset" and the Brass Patron nudge - the things a dialog offers beside
/// its one lit button without competing with it.
class DialogTextButton extends StatefulWidget {
  const DialogTextButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color,
    this.underline = true,
    this.fontSize = 14,
    this.textAlign = TextAlign.center,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Defaults to Screen; pass [PTColors.premium] for a Patron nudge.
  final Color? color;
  final bool underline;
  final double fontSize;
  final TextAlign textAlign;

  @override
  State<DialogTextButton> createState() => _DialogTextButtonState();
}

class _DialogTextButtonState extends State<DialogTextButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final ink = widget.color ?? PTColors.fg;
    return Semantics(
      button: true,
      enabled: enabled,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: ConstrainedBox(
            // A touch-sized hit area around a text-sized label.
            constraints: const BoxConstraints(minHeight: 36),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: AnimatedOpacity(
                duration: PTMotion.functional(context, PTMotion.hover),
                opacity: !enabled ? 0.4 : (_hovered ? 1 : 0.88),
                child: Text(
                  widget.label,
                  textAlign: widget.textAlign,
                  style: PTText.body.copyWith(
                    fontSize: widget.fontSize,
                    fontWeight: .w600,
                    color: ink,
                    decoration: widget.underline ? TextDecoration.underline : null,
                    decorationColor: ink.withValues(alpha: 0.6),
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

/// What a [DialogTag] marks, which decides its ink.
enum DialogTagTone { neutral, premium, host }

/// A small square mono tag: HOST (inverted paper), PATRON (Brass hairline),
/// PICTURE (Rail). Uppercased here.
class DialogTag extends StatelessWidget {
  const DialogTag(this.label, {super.key, this.tone = DialogTagTone.neutral});

  final String label;
  final DialogTagTone tone;

  @override
  Widget build(BuildContext context) {
    final (Color? fill, Color border, Color ink) = switch (tone) {
      DialogTagTone.neutral => (null, PTColors.rail, PTColors.white(0.55)),
      DialogTagTone.premium => (null, PTColors.premiumBorder, PTColors.premium),
      DialogTagTone.host => (PTColors.fg, PTColors.fg, PTColors.canvas),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        style: PTText.label.copyWith(
          fontSize: 9.5,
          letterSpacing: 1.1,
          fontWeight: .w600,
          color: ink,
        ),
      ),
    );
  }
}

/// A dashed hairline outline - a rounded rect, or a circle with [circle] -
/// for a file stub or a crop guide. Static; it paints once.
class DashedRectPainter extends CustomPainter {
  const DashedRectPainter({
    required this.color,
    this.radius = 0,
    this.circle = false,
    this.dash = 4,
    this.gap = 3,
    this.strokeWidth = 1,
  });

  final Color color;
  final double radius;
  final bool circle;
  final double dash;
  final double gap;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(strokeWidth / 2);
    final path = Path();
    if (circle) {
      path.addOval(rect);
    } else {
      path.addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + gap) {
        canvas.drawPath(metric.extractPath(d, math.min(d + dash, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(DashedRectPainter old) =>
      old.color != color || old.radius != radius || old.circle != circle;
}
