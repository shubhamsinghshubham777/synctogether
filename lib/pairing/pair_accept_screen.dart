import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_service.dart';
import '../diagnostics.dart';
import '../profile/profile_service.dart';
import '../ui/banners.dart';
import '../ui/booth_icons.g.dart';
import '../ui/buttons.dart';
import '../ui/identity.dart';
import '../ui/loader.dart';
import '../ui/pt_theme.dart';
import 'pair_models.dart';
import 'pair_page.dart';
import 'pair_prompts.dart';
import 'pair_service.dart';
import 'pair_widgets.dart';

/// Where a `synctogether://pair/<code>` link (or a typed pair code) lands: who
/// is asking, what pairing gives you, and one button.
class PairAcceptScreen extends StatefulWidget {
  const PairAcceptScreen({super.key, required this.code});

  final String code;

  @override
  State<PairAcceptScreen> createState() => _PairAcceptScreenState();
}

class _PairAcceptScreenState extends State<PairAcceptScreen> {
  PairInvite? _invite;
  PairErrorCode? _problem;
  bool _loading = true;
  bool _accepting = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (!PairService.instance.isSignedInAccount) {
      // A guest can read the invite, not answer it. Park the code so it is still
      // here when they come back from signing in.
      PairService.instance.pendingPairCode = widget.code;
    }
    try {
      final invite = await PairService.instance.previewInvite(widget.code);
      if (!mounted) return;
      setState(() {
        _invite = invite;
        _loading = false;
        _problem = switch (invite.status) {
          // Whatever the invite says, there is nobody left to pair with.
          _
              when invite.inviterPaired &&
                  !invite.isMine &&
                  invite.status != PairInviteStatus.accepted =>
            PairErrorCode.partnerAlreadyPaired,
          PairInviteStatus.expired => PairErrorCode.inviteExpired,
          PairInviteStatus.accepted => PairErrorCode.inviteUsed,
          PairInviteStatus.cancelled => PairErrorCode.inviteCancelled,
          PairInviteStatus.pending when invite.isMine => PairErrorCode.cannotPairSelf,
          // Already paired: say so now, rather than offer a button that can only
          // fail. (The server enforces it too; this is only the kinder screen.)
          PairInviteStatus.pending when PairService.instance.isPaired =>
            PairErrorCode.alreadyPaired,
          PairInviteStatus.pending => null,
        };
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _problem = PairErrorCode.fromError(e);
        _loading = false;
      });
    }
  }

  Future<void> _accept() async {
    setState(() => _accepting = true);
    try {
      await PairService.instance.acceptInvite(widget.code);
      PairService.instance.pendingPairCode = null;
      if (!mounted) return;
      showPTSnack(context, 'You two are paired.', kind: .success);
      await offerPushAfterPairing(
        context,
        (_invite?.inviter.displayName ?? 'your person').split(' ').first,
      );
      if (mounted) context.go('/lobby/pair');
    } catch (e) {
      final failure = PairErrorCode.fromError(e);
      if (mounted) {
        setState(() {
          _accepting = false;
          _problem = failure;
        });
      }
    }
  }

  void _notNow() {
    PairService.instance.dismissBanner(widget.code);
    PairService.instance.pendingPairCode = null;
    context.go('/lobby');
  }

  @override
  Widget build(BuildContext context) {
    final guest = !PairService.instance.isSignedInAccount;
    final invite = _invite;
    final name = invite?.inviter.displayName ?? 'Someone';

    if (_loading) {
      return const PairPage(
        title: 'Pair up',
        children: [
          Padding(
            padding: EdgeInsets.only(top: 80),
            child: Center(child: PTLoader()),
          ),
        ],
      );
    }

    return PairPage(
      title: 'Pair up',
      spacing: 18,
      children: [
        const SizedBox(height: 8),
        if (invite != null)
          Center(
            child: Row(
              mainAxisSize: .min,
              spacing: 14,
              children: [
                PTAvatar(
                  userId: invite.inviter.id,
                  displayName: invite.inviter.displayName,
                  avatarUrl: invite.inviter.avatarUrl,
                  size: 64,
                ),
                const Icon(BoothIcons.heart, color: PTColors.primary, size: 24),
                PTAvatar(
                  userId: ProfileService.instance.profile?.id ?? '',
                  displayName: ProfileService.instance.profile?.displayName ?? 'You',
                  avatarUrl: ProfileService.instance.profile?.avatarUrl,
                  size: 64,
                ),
              ],
            ),
          ),
        Text(
          _problem == null || _problem == PairErrorCode.cannotPairSelf && invite == null
              ? '$name wants to pair with you'
              : _problem!.message,
          textAlign: TextAlign.center,
          style: PTText.display.copyWith(fontSize: 32, height: 1),
        ),
        if (_problem == null) ...[
          PairPanel(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: const Column(
              children: [
                PairRow(icon: BoothIcons.chat, title: 'A private room that is always yours'),
                PairDivider(),
                PairRow(icon: BoothIcons.calendar, title: 'Date nights with both your time zones'),
                PairDivider(),
                PairRow(icon: BoothIcons.fire, title: 'A watch history and a weekly streak'),
              ],
            ),
          ),
          if (guest) ...[
            const PairNote(
              'Pairing lives on an account, so you will sign in first. This invite waits for you.',
              center: true,
            ),
            if (AuthService.instance.isAppleSupported)
              AppleButton(
                label: 'Sign in with Apple',
                onPressed: () => _link(AuthService.instance.linkAppleIdentity),
              ),
            GoogleButton(
              label: 'Sign in with Google',
              onPressed: () => _link(AuthService.instance.linkGoogleIdentity),
            ),
          ] else ...[
            const PairNameCheck(),
            PTButton(label: 'Pair with $name', loading: _accepting, onPressed: _accept),
            Center(
              child: DialogTextLink(label: 'Not now', onPressed: _notNow),
            ),
          ],
          const PairNote('You can unpair any time from Your person.', center: true),
        ] else
          PTButton(
            label: 'Back to the lobby',
            variant: .secondary,
            onPressed: () => context.go('/lobby'),
          ),
      ],
    );
  }

  Future<void> _link(Future<void> Function() go) async {
    try {
      await go();
    } catch (e, s) {
      reportNonFatal(e, s, during: 'linking an identity from the pair invite');
      if (mounted) showPTSnack(context, "Couldn't start sign-in. Try again.", kind: .error);
    }
  }
}

/// A quiet text link, centred under a primary action.
class DialogTextLink extends StatelessWidget {
  const DialogTextLink({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    child: Text(
      label,
      style: PTText.body.copyWith(color: PTColors.link, fontWeight: .w500),
    ),
  );
}
