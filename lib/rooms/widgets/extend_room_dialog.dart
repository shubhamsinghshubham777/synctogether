import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:synctogether/auth/auth_service.dart';
import 'package:synctogether/platform.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/pt_motion.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/pt_theme.dart';

class ExtendRoomDialog extends StatefulWidget {
  const ExtendRoomDialog({
    super.key,
    required this.options,
    required this.headroomMinutes,
    this.endsAt,
    this.now = DateTime.now,
  });

  final List<int> options;
  final int headroomMinutes;

  /// When the room's lights come up. Drives the "LIGHTS UP IN m:ss" line;
  /// without it the status row shows only the bank.
  final DateTime? endsAt;

  /// The clock [endsAt] is compared against - pass `RoomService.serverNow`
  /// so the countdown agrees with the room's.
  final DateTime Function() now;

  @override
  State<ExtendRoomDialog> createState() => _ExtendRoomDialogState();
}

class _ExtendRoomDialogState extends State<ExtendRoomDialog> {
  late int _selected = widget.options.first;

  // A once-a-second rebuild of one line while the dialog is open - a timer,
  // not an animation ticker, and cancelled with the dialog.
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    if (widget.endsAt != null) {
      _clock = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final endsAt = widget.endsAt;
    final left = endsAt?.difference(widget.now());
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      spacing: 14,
      children: [
        GlassDialogHeader(
          eyebrow: 'Room time',
          title: 'Extend room',
          onClose: () => Navigator.of(context).pop(),
        ),
        // The mono status row: how long until the lights come up (Signal -
        // it is on air), and how much time the room still has to spend.
        Row(
          spacing: 12,
          children: [
            if (left != null) ...[
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(color: PTColors.ember, shape: .circle),
              ),
              Flexible(
                child: Text(
                  'Lights up in ${countdownLabel(left)}'.toUpperCase(),
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: PTText.label.copyWith(color: PTColors.ember, fontWeight: .w600),
                ),
              ),
            ],
            Expanded(
              child: Text(
                '${_label(widget.headroomMinutes)} in the bank'.toUpperCase(),
                textAlign: .end,
                maxLines: 1,
                overflow: .ellipsis,
                style: PTText.label,
              ),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final minutes in widget.options)
              _Choice(
                label: _label(minutes),
                selected: _selected == minutes,
                onTap: () => setState(() => _selected = minutes),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: PTButtonBar(
            spacing: 11,
            buttons: [
              PTButton(
                maxLines: 2,
                label: 'Not now',
                variant: .secondary,
                height: 48,
                onPressed: () => Navigator.of(context).pop(),
              ),
              PTButton(
                maxLines: 2,
                label: 'Add ${spelledDuration(_selected)}',
                height: 48,
                onPressed: () => Navigator.of(context).pop(_selected),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// "m:ss" (or "h:mm:ss") to the lights coming up, never negative.
  @visibleForTesting
  static String countdownLabel(Duration left) {
    final s = left.isNegative ? 0 : left.inSeconds;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = (s % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$sec' : '$m:$sec';
  }

  /// The primary button spells the choice out: "15 minutes", "1 hour 30 minutes".
  @visibleForTesting
  static String spelledDuration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    final hours = h == 0 ? null : '$h ${h == 1 ? 'hour' : 'hours'}';
    final mins = m == 0 ? null : '$m ${m == 1 ? 'minute' : 'minutes'}';
    return [?hours, ?mins].join(' ');
  }

  static String _label(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: PTMotion.functional(context, PTMotion.hover),
          curve: PTMotion.enter,
          constraints: const BoxConstraints(minWidth: 52, minHeight: 40),
          // No `alignment`: a Container with one expands to its parent, which
          // made every chip a full-width row inside the Wrap.
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          // A square segment, not a pill: Beam edge when chosen, Rail otherwise.
          decoration: BoxDecoration(
            color: selected ? PTColors.aisle : Colors.transparent,
            border: Border.all(color: selected ? PTColors.primary : PTColors.rail),
            borderRadius: BorderRadius.circular(PTRadius.control),
          ),
          child: Text(
            label,
            textAlign: .center,
            style: PTText.mono.copyWith(
              fontSize: 14,
              fontWeight: selected ? .w600 : .w400,
              color: selected ? PTColors.primary : PTColors.white(0.75),
            ),
          ),
        ),
      ),
    );
  }
}

class PremiumTeaseDialog extends StatelessWidget {
  const PremiumTeaseDialog({
    super.key,
    required this.headline,
    required this.body,
    required this.perks,
    this.onNotify,
    this.onUpgrade,
    this.onSignIn,
    this.onSignInApple,
    this.desktopOverride,
  });

  final String headline;
  final String body;
  final List<String> perks;
  final VoidCallback? onNotify;
  final VoidCallback? onUpgrade;
  final VoidCallback? onSignIn;
  final VoidCallback? onSignInApple;
  final bool? desktopOverride;

  bool get _isDesktop => desktopOverride ?? isDesktop;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      spacing: 14,
      children: [
        // A guest is one sign-in away, so theirs is a plain invitation; a
        // member is looking at Patron seats, the one place Brass is spent.
        // "Coming soon" only where the dialog really is the waitlist - when
        // there is an upgrade to take, it is not coming, it is here.
        if (onSignIn == null)
          Row(
            spacing: 10,
            children: [
              const DialogTag('Patron', tone: DialogTagTone.premium),
              Flexible(
                child: Text(
                  (onUpgrade == null ? 'Coming soon' : 'Patron seats').toUpperCase(),
                  textScaler: dialogHeadingScaler(context),
                  style: PTText.label,
                ),
              ),
            ],
          ),
        GlassDialogHeader(
          eyebrow: onSignIn == null ? null : 'Take your seat',
          title: headline,
          subtitle: body,
          titleGap: 6,
          subtitleStyle: PTText.body.copyWith(
            fontSize: 14,
            color: PTColors.white(0.62),
            height: 1.5,
          ),
        ),
        // Hairline-ruled perks, a programme rather than a feature grid.
        Column(
          crossAxisAlignment: .stretch,
          children: [
            for (final (i, perk) in perks.indexed)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  border: Border(
                    top: i == 0 ? const BorderSide(color: PTColors.rail) : BorderSide.none,
                    bottom: const BorderSide(color: PTColors.rail),
                  ),
                ),
                child: Row(
                  spacing: 10,
                  children: [
                    Icon(
                      Symbols.check_rounded,
                      size: 17,
                      color: onSignIn == null ? PTColors.premium : PTColors.online,
                    ),
                    Expanded(
                      child: Text(
                        perk,
                        style: PTText.body.copyWith(fontSize: 13.5, color: PTColors.white(0.8)),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: onSignIn == null ? _teaseActions(context) : _signInActions(context),
        ),
      ],
    );
  }

  Widget _teaseActions(BuildContext context) {
    if (_isDesktop) {
      // The label says what the button does: a real upgrade where one is
      // wired, the waitlist only where that is all there is.
      return Row(
        spacing: 16,
        children: [
          DialogTextButton(label: 'Maybe later', onPressed: () => Navigator.of(context).pop()),
          Expanded(
            child: PTButton(
              maxLines: 2,
              label: onUpgrade != null ? 'Get a Patron seat' : 'Keep me posted',
              height: 48,
              onPressed: () {
                Navigator.of(context).pop();
                (onUpgrade ?? onNotify)?.call();
              },
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      spacing: 11,
      children: [
        const DialogNote(
          icon: Symbols.info_rounded,
          child: Text('Subscriptions are managed on our website.'),
        ),
        PTButton(
          maxLines: 2,
          label: 'Close',
          variant: .secondary,
          height: 48,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _signInActions(BuildContext context) {
    final hasApple = AuthService.instance.isAppleSupported && onSignInApple != null;
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      spacing: 11,
      children: [
        if (hasApple)
          AppleButton(
            label: 'Sign in with Apple',
            onPressed: () {
              Navigator.of(context).pop();
              onSignInApple?.call();
            },
          ),
        if (onSignIn != null)
          GoogleButton(
            label: 'Sign in with Google',
            onPressed: () {
              Navigator.of(context).pop();
              onSignIn?.call();
            },
          ),
        // Apple stays beside Google: on Apple platforms Sign in with Apple
        // must be offered wherever another social sign-in is.
        Center(
          child: DialogTextButton(
            label: 'Maybe later',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ],
    );
  }
}
