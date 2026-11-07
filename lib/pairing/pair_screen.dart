import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../analytics.dart';
import '../app_router.dart';
import '../auth/auth_service.dart';
import '../diagnostics.dart';
import '../nav.dart';
import '../profile/profile_service.dart';
import '../ui/banners.dart';
import '../ui/booth.dart';
import '../ui/booth_icons.g.dart';
import '../ui/buttons.dart';
import '../ui/glass.dart';
import '../ui/loader.dart';
import '../ui/pt_theme.dart';
import 'pair_logic.dart';
import 'pair_models.dart';
import 'pair_page.dart';
import 'pair_service.dart';
import 'pair_widgets.dart';

/// "Your person": pair up, or - once paired - the hub for everything the two of
/// you share. One route, three states: a guest sees why pairing needs an
/// account, an unpaired account sees its invite, a pair sees the hub.
class PairScreen extends StatefulWidget {
  const PairScreen({super.key});

  @override
  State<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends State<PairScreen> {
  bool _creating = false;
  bool _ending = false;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    final svc = PairService.instance;
    await svc.load();
    unawaited(svc.syncTimezone());
    if (!mounted || !svc.isSignedInAccount || svc.isPaired) return;
    // Opening this page is the person asking to pair, so a code is minted now.
    // The server reuses the pending one, so revisiting never mints a second.
    if (svc.sentInvite == null) await _makeInvite();
  }

  Future<void> _makeInvite() async {
    if (_creating) return;
    setState(() => _creating = true);
    try {
      await PairService.instance.createInvite();
    } catch (e) {
      final failure = PairErrorCode.fromError(e);
      if (mounted) showPTSnack(context, failure.message, kind: .error);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _copyLink(PairInvite invite) async {
    await Clipboard.setData(
      ClipboardData(
        text:
            "Come watch with me on SyncTogether: ${pairInviteLink(invite.code)}\n"
            "Or open the app and enter ${invite.code}.",
      ),
    );
    Analytics.instance.track('pair_invite_shared', {'via': 'link'});
    if (mounted) showPTSnack(context, 'Copied. Paste it to your person.', kind: .success);
  }

  Future<void> _copyCode(PairInvite invite) async {
    await Clipboard.setData(ClipboardData(text: invite.code));
    Analytics.instance.track('pair_invite_shared', {'via': 'code'});
    if (mounted) showPTSnack(context, 'Code copied.', kind: .success);
  }

  Future<void> _unpair() async {
    final partner = PairService.instance.pair?.partner.displayName ?? 'your person';
    final go = await showGlassDialog<bool>(
      context: context,
      width: 420,
      builder: (ctx) => Column(
        crossAxisAlignment: .stretch,
        spacing: 16,
        children: [
          Text('Unpair from $partner?', style: PTText.screenTitle),
          Text(
            'Our Room, the shared watchlist, date nights and the pair streak go away for both of you. '
            'Your own rooms and your personal streak stay put.',
            style: PTText.body.copyWith(color: PTColors.fgSoft, height: 1.5),
          ),
          Row(
            spacing: 10,
            children: [
              Expanded(
                child: PTButton(
                  label: 'Keep pairing',
                  variant: .secondary,
                  height: 44,
                  onPressed: () => Navigator.of(ctx).pop(false),
                ),
              ),
              Expanded(
                child: PTButton(
                  label: 'Unpair',
                  variant: .destructive,
                  height: 44,
                  onPressed: () => Navigator.of(ctx).pop(true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    setState(() => _ending = true);
    try {
      await PairService.instance.unpair();
    } catch (e) {
      if (mounted) showPTSnack(context, PairErrorCode.fromError(e).message, kind: .error);
    } finally {
      if (mounted) setState(() => _ending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PairService.instance,
      builder: (context, _) {
        final svc = PairService.instance;
        if (!svc.isSignedInAccount) return const _GuestGate();
        if (svc.isPaired) return _Hub(onUnpair: _unpair, busy: _ending);
        return _InviteFlow(
          invite: svc.sentInvite,
          busy: _creating,
          onShare: _copyLink,
          onCopyCode: _copyCode,
          onCancel: () async {
            await PairService.instance.cancelInvite();
            if (mounted) await _makeInvite();
          },
          loading: !svc.loaded,
        );
      },
    );
  }
}

// ---------------------------------------------------------------- guest gate

class _GuestGate extends StatelessWidget {
  const _GuestGate();

  @override
  Widget build(BuildContext context) {
    Future<void> link(Future<void> Function() go, String who) async {
      try {
        await go();
      } catch (e, s) {
        reportNonFatal(e, s, during: 'linking $who from the pair gate');
        if (context.mounted) {
          showPTSnack(context, "Couldn't start sign-in. Try again.", kind: .error);
        }
      }
    }

    return PairPage(
      title: 'Your person',
      children: [
        const PairKicker('Pairing'),
        Text(
          'Pairing lives on an account',
          style: PTText.display.copyWith(fontSize: 34, height: 1),
        ),
        Text(
          'Guests can join any room, but pairing, Our Room and your shared history are kept on an account, '
          'so they follow you to a new phone.',
          style: PTText.body.copyWith(color: PTColors.fgSoft, height: 1.5),
        ),
        const SizedBox(height: 4),
        if (AuthService.instance.isAppleSupported)
          AppleButton(
            label: 'Sign in with Apple',
            onPressed: () => link(AuthService.instance.linkAppleIdentity, 'an Apple identity'),
          ),
        GoogleButton(
          label: 'Sign in with Google',
          onPressed: () => link(AuthService.instance.linkGoogleIdentity, 'a Google identity'),
        ),
        const PairNote('Your current session carries over.', center: true),
      ],
    );
  }
}

// --------------------------------------------------------------- invite flow

class _InviteFlow extends StatelessWidget {
  const _InviteFlow({
    required this.invite,
    required this.busy,
    required this.loading,
    required this.onShare,
    required this.onCopyCode,
    required this.onCancel,
  });

  final PairInvite? invite;
  final bool busy;
  final bool loading;
  final void Function(PairInvite) onShare;
  final void Function(PairInvite) onCopyCode;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final inv = invite;
    final hoursLeft = inv?.expiresAt.difference(DateTime.now().toUtc()).inHours;
    return PairPage(
      title: 'Pair up',
      children: [
        const PairKicker('Your person'),
        Text('Pair with your person', style: PTText.display.copyWith(fontSize: 38, height: 0.98)),
        Text(
          'One private room, one shared history. Just the two of you, whatever the time zones.',
          style: PTText.body.copyWith(color: PTColors.fgSoft, height: 1.5),
        ),
        if (inv == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(child: PTLoader()),
          )
        else ...[
          PTTicket(
            paper: true,
            stubWidth: 124,
            semanticLabel: 'Pair code ${inv.code}',
            body: Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 12, 18),
              child: Column(
                crossAxisAlignment: .start,
                mainAxisSize: .min,
                spacing: 6,
                children: [
                  Text(
                    'PAIR CODE · ${(hoursLeft ?? 48).clamp(1, 48)} H LEFT',
                    style: PTText.label.copyWith(color: PTColors.liveInk, letterSpacing: 1.2),
                  ),
                  Text(
                    'Your pair code',
                    style: PTText.cardHeading.copyWith(color: PTColors.canvas, fontSize: 22),
                  ),
                  Text(
                    'Works once. Send it to your person.',
                    style: PTText.mono.copyWith(
                      fontSize: 11,
                      color: PTColors.canvas.withValues(alpha: 0.62),
                    ),
                  ),
                ],
              ),
            ),
            stub: Center(
              child: Text(
                inv.code,
                style: PTText.mono.copyWith(
                  fontSize: 17,
                  fontWeight: .w600,
                  letterSpacing: 1.4,
                  color: PTColors.canvas,
                ),
              ),
            ),
          ),
          PTButton(
            label: 'Copy invite link',
            icon: BoothIcons.share,
            onPressed: () => onShare(inv),
          ),
          PTButton(
            label: 'Copy code',
            variant: .secondary,
            icon: BoothIcons.link,
            onPressed: () => onCopyCode(inv),
          ),
          Row(
            spacing: 10,
            children: [
              const Icon(BoothIcons.clock, size: 16, color: PTColors.fgMute),
              Expanded(
                child: Text(
                  'Waiting for your person to accept…',
                  style: PTText.body.copyWith(color: PTColors.fgSoft, fontSize: 14),
                ),
              ),
              DialogTextButton(label: 'New code', onPressed: busy ? null : onCancel),
            ],
          ),
        ],
        const SizedBox(height: 8),
        const PairNote(
          'Pairing is optional. Rooms with friends and family work exactly as before.',
          center: true,
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------------- hub

class _Hub extends StatelessWidget {
  const _Hub({required this.onUnpair, required this.busy});

  final VoidCallback onUnpair;
  final bool busy;

  String _since(DateTime t) => formatDay(t.toLocal()).split(' ').skip(1).join(' ');

  @override
  Widget build(BuildContext context) {
    final svc = PairService.instance;
    final pair = svc.pair!;
    final me = ProfileService.instance.profile;
    final partner = pair.partner;
    final now = DateTime.now();
    final nextNight = upcomingNights(now.toUtc(), svc.nights).firstOrNull;
    final reunion = pair.reunionOn == null ? null : reunionView(pair.reunionOn!, now);
    final streak = svc.stats.streakWeeks;

    return PairPage(
      title: 'Your person',
      children: [
        PairPanel(
          live: svc.partnerOnline,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: .stretch,
            spacing: 14,
            children: [
              Row(
                spacing: 14,
                children: [
                  PairAvatars(
                    myId: me?.id ?? '',
                    myName: me?.displayName ?? 'You',
                    myAvatarUrl: me?.avatarUrl,
                    partner: partner,
                    partnerOnline: svc.partnerOnline,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: .start,
                      spacing: 3,
                      children: [
                        Text(
                          partner.displayName,
                          style: PTText.cardHeading.copyWith(fontSize: 21),
                          maxLines: 1,
                          overflow: .ellipsis,
                        ),
                        Text(
                          'Paired since ${_since(pair.since)}',
                          style: PTText.caption.copyWith(color: PTColors.fgSoft),
                        ),
                      ],
                    ),
                  ),
                  if (svc.partnerOnline) const PairPill('Online'),
                ],
              ),
              PartnerClockLine(partner: partner),
              const PairDivider(),
              PTButton(
                label: 'Open Our Room',
                icon: BoothIcons.film,
                onPressed: () => openOurRoom(context),
              ),
              PTButton(
                label: 'Plan a date night',
                variant: .secondary,
                icon: BoothIcons.calendar,
                onPressed: () => openPage(context, '/lobby/pair/nights'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        const PairKicker('Shared'),
        PairPanel(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              PairRow(
                icon: BoothIcons.film,
                title: 'Watchlist',
                value: '${svc.watchlist.where((i) => !i.watched).length} to watch',
                onTap: () => openPage(context, '/lobby/pair/watchlist'),
              ),
              const PairDivider(),
              PairRow(
                icon: BoothIcons.calendar,
                title: 'Date nights',
                value: nextNight == null ? 'None planned' : formatDay(nextNight.startsAt.toLocal()),
                onTap: () => openPage(context, '/lobby/pair/nights'),
              ),
              const PairDivider(),
              PairRow(
                icon: BoothIcons.fire,
                title: 'Streak and history',
                value: streak > 0 ? '$streak ${streak == 1 ? 'week' : 'weeks'}' : 'Start one',
                valueColor: streak > 0 ? PTColors.streak : null,
                onTap: () => openPage(context, '/lobby/pair/history'),
              ),
              const PairDivider(),
              PairRow(
                icon: BoothIcons.plane,
                title: 'Reunion countdown',
                value: reunion == null || reunion.phase == ReunionPhase.past
                    ? 'Set a date'
                    : '${reunion.daysLeft} ${reunion.daysLeft == 1 ? 'day' : 'days'}',
                onTap: () => editReunion(context),
              ),
              const PairDivider(),
              PairRow(
                icon: BoothIcons.bell,
                title: 'Notifications',
                onTap: () => openPage(context, '/lobby/pair/notifications'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: DialogTextButton(
            label: busy ? 'Unpairing…' : 'Unpair from ${partner.displayName}',
            onPressed: busy ? null : onUnpair,
            color: PTColors.danger,
          ),
        ),
      ],
    );
  }
}

/// Create-or-resume Our Room and go in. Used by the hub, the lobby card and a
/// notification tap, so the failure copy lives in one place.
Future<void> openOurRoom(BuildContext context, {bool call = false}) async {
  final router = GoRouter.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final room = await PairService.instance.openOurRoom();
    if (call) {
      final sent = await PairService.instance.callPartner();
      trace('called the partner', category: 'room', data: {'sent': sent});
    }
    router.go(roomPath(room.id));
  } catch (e) {
    showPTSnackVia(messenger, PairErrorCode.fromError(e).message, kind: .error);
  }
}

/// The reunion date and label, as a small dialog.
Future<void> editReunion(BuildContext context) async {
  final pair = PairService.instance.pair;
  if (pair == null) return;
  final labelController = TextEditingController(text: pair.reunionLabel ?? '');
  var picked = pair.reunionOn;
  await showGlassDialog<void>(
    context: context,
    width: 420,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => Column(
        crossAxisAlignment: .stretch,
        spacing: 14,
        children: [
          Text('When do you see each other?', style: PTText.screenTitle.copyWith(fontSize: 24)),
          PTButton(
            label: picked == null ? 'Pick a date' : formatDay(picked!),
            variant: .secondary,
            icon: BoothIcons.calendar,
            height: 46,
            onPressed: () async {
              final now = DateTime.now();
              final d = await showDatePicker(
                context: ctx,
                initialDate: picked ?? now.add(const Duration(days: 30)),
                firstDate: DateTime(now.year, now.month, now.day),
                lastDate: now.add(const Duration(days: 365 * 3)),
              );
              if (d != null) setState(() => picked = d);
            },
          ),
          TextField(
            controller: labelController,
            maxLength: 60,
            style: PTText.body,
            decoration: const InputDecoration(hintText: 'A label, like "Sam lands at Heathrow"'),
          ),
          Row(
            spacing: 10,
            children: [
              Expanded(
                child: PTButton(
                  label: 'Clear',
                  variant: .secondary,
                  height: 44,
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    await PairService.instance.setReunion(null, null);
                  },
                ),
              ),
              Expanded(
                child: PTButton(
                  label: 'Save',
                  height: 44,
                  onPressed: picked == null
                      ? null
                      : () async {
                          Navigator.of(ctx).pop();
                          await PairService.instance.setReunion(picked, labelController.text);
                        },
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  labelController.dispose();
}
