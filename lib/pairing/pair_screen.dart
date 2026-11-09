import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../analytics.dart';
import '../app_router.dart';
import '../auth/auth_service.dart';
import '../diagnostics.dart';
import '../nav.dart';
import '../ui/pt_motion.dart';
import '../profile/profile_service.dart';
import '../ui/banners.dart';
import '../ui/booth.dart';
import '../ui/booth_icons.g.dart';
import '../ui/buttons.dart';
import '../ui/glass.dart';
import '../ui/inputs.dart';
import '../ui/loader.dart';
import '../ui/panel_switcher.dart';
import '../ui/reveal.dart';
import '../ui/pt_date_time_picker.dart';
import '../ui/pt_theme.dart';
import 'pair_logic.dart';
import 'pair_models.dart';
import 'pair_page.dart';
import 'pair_prompts.dart';
import 'pair_service.dart';
import 'pair_share.dart';
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

  /// One automatic attempt per time this screen finds itself unpaired with no
  /// code (it opened that way, or an unpair - yours or theirs - just happened).
  /// Reset whenever the hub is showing, so the next unpair gets its own.
  bool _autoTried = false;

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

  String _message(PairInvite invite) =>
      "Come watch with me on SyncTogether: ${pairInviteLink(invite.code)}\n"
      "Or open the app and enter ${invite.code}.";

  /// The native share sheet - Messages, WhatsApp, whatever the two of you use.
  /// Where there is none, the same message is copied instead.
  Future<void> _share(PairInvite invite, BuildContext buttonContext) async {
    final shared = await shareText(buttonContext, _message(invite), subject: 'Pair with me');
    Analytics.instance.track('pair_invite_shared', {'via': 'share'});
    if (shared || !mounted) return;
    await Clipboard.setData(ClipboardData(text: _message(invite)));
    if (mounted) showPTSnack(context, 'Copied. Paste it to your person.', kind: .success);
  }

  Future<void> _copyLink(PairInvite invite) async {
    await Clipboard.setData(ClipboardData(text: _message(invite)));
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
            'Our Room, date nights and the pair streak go away for both of you. '
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
        if (svc.isPaired) {
          _autoTried = false;
          return _Hub(onUnpair: _unpair, busy: _ending);
        }
        if (svc.loaded && svc.sentInvite == null && !_creating && !_autoTried) {
          _autoTried = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(_makeInvite());
          });
        }
        return _InviteFlow(
          invite: svc.sentInvite,
          busy: _creating,
          onShare: _share,
          onCopyLink: _copyLink,
          onCopyCode: _copyCode,
          onCancel: () async {
            await PairService.instance.cancelInvite();
            if (mounted) await _makeInvite();
          },
          loading: !svc.loaded,
          onRetry: _makeInvite,
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
    required this.onCopyLink,
    required this.onCopyCode,
    required this.onCancel,
    required this.onRetry,
  });

  final PairInvite? invite;
  final bool busy;
  final bool loading;
  final void Function(PairInvite, BuildContext) onShare;
  final void Function(PairInvite) onCopyLink;
  final void Function(PairInvite) onCopyCode;
  final VoidCallback onCancel;
  final VoidCallback onRetry;

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
        const PairNameCheck(),
        // The three states of the invite (couldn't get one, getting one, here it is)
        // trade places as one motion: the height follows and nothing pops.
        PTPanelSwitcher(
          child: inv == null
              ? (!busy && !loading
                    ? KeyedSubtree(
                        key: const ValueKey('invite-retry'),
                        // The request came back with nothing (offline, a server hiccup). Say
                        // so and offer another go, rather than spin for ever.
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Column(
                            spacing: 12,
                            children: [
                              Text(
                                "Couldn't get a code just now.",
                                style: PTText.body.copyWith(color: PTColors.fgSoft),
                              ),
                              PTButton(
                                label: 'Try again',
                                variant: .secondary,
                                expand: false,
                                onPressed: onRetry,
                              ),
                            ],
                          ),
                        ),
                      )
                    : KeyedSubtree(
                        key: const ValueKey('invite-loading'),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 28),
                          child: Center(child: PTLoader()),
                        ),
                      ))
              : Column(
                  key: const ValueKey('invite-ready'),
                  crossAxisAlignment: .stretch,
                  spacing: 14,
                  children: [
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
                              style: PTText.label.copyWith(
                                color: PTColors.liveInk,
                                letterSpacing: 1.2,
                              ),
                            ),
                            Text(
                              'Your pair code',
                              style: PTText.cardHeading.copyWith(
                                color: PTColors.canvas,
                                fontSize: 22,
                              ),
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
                    Builder(
                      builder: (buttonContext) => PTButton(
                        label: 'Share invite',
                        icon: BoothIcons.share,
                        onPressed: () => onShare(inv, buttonContext),
                      ),
                    ),
                    Row(
                      spacing: 10,
                      children: [
                        Expanded(
                          child: PTButton(
                            label: 'Copy link',
                            variant: .secondary,
                            icon: BoothIcons.link,
                            onPressed: () => onCopyLink(inv),
                          ),
                        ),
                        Expanded(
                          child: PTButton(
                            label: 'Copy code',
                            variant: .secondary,
                            icon: BoothIcons.file,
                            onPressed: () => onCopyCode(inv),
                          ),
                        ),
                      ],
                    ),
                    const _EmailInvite(),
                    const PairPushPrompt(text: 'Get a ping the moment they accept.'),
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
                    const PairCodeEntry(),
                  ],
                ),
        ),
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
                children: [
                  PairAvatars(
                    myId: me?.id ?? '',
                    myName: me?.displayName ?? 'You',
                    myAvatarUrl: me?.avatarUrl,
                    partner: partner,
                    partnerOnline: svc.partnerOnline,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: .start,
                      spacing: 3,
                      children: [
                        Semantics(
                          button: true,
                          excludeSemantics: true,
                          label: 'Rename ${partner.displayName}',
                          child: PTPressable(
                            onTap: () => showPartnerNicknameDialog(context, partner),
                            pressedScale: 0.98,
                            child: Row(
                              mainAxisSize: .min,
                              spacing: 8,
                              children: [
                                Flexible(
                                  child: Text(
                                    partner.displayName,
                                    style: PTText.cardHeading.copyWith(fontSize: 21),
                                    maxLines: 1,
                                    overflow: .ellipsis,
                                  ),
                                ),
                                const Icon(BoothIcons.edit, size: 15, color: PTColors.fgMute),
                              ],
                            ),
                          ),
                        ),
                        Text(
                          'Paired since ${_since(pair.since)}',
                          style: PTText.caption.copyWith(color: PTColors.fgSoft),
                        ),
                      ],
                    ),
                  ),
                  // Unfolds in beside the name when they come online, folds away when
                  // they leave; its gap travels with it so a hidden pill leaves none.
                  PTRevealKeep(
                    visible: svc.partnerOnline,
                    axis: Axis.horizontal,
                    alignment: Alignment.centerRight,
                    gap: 14,
                    child: const PairPill('Online'),
                  ),
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
        PairPushPrompt(text: 'Hear it when ${partner.displayName.split(' ').first} calls.'),
        const SizedBox(height: 4),
        const PairKicker('Shared'),
        PairPanel(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
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
                onTap: () => openPage(context, '/lobby/pair/streak'),
              ),
              const PairDivider(),
              PairRow(
                icon: BoothIcons.reunion,
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
        const PairPatronNote(),
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
  final me = ProfileService.instance.profile?.id;
  // Someone else set it and keeps it to themselves: I can still choose whether it shows on
  // my lobby, but not change the date.
  final locked = !pair.canEditReunion(me);
  final iSetIt = pair.reunionSetBy == null || pair.reunionSetBy == me;
  final first = pair.partner.displayName.split(' ').first;
  final labelController = TextEditingController(text: pair.reunionLabel ?? '');
  var picked = pair.reunionOn;
  var shared = pair.reunionSharedEdit;
  var show = pair.showReunion;
  Future<void> run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (context.mounted) showPTSnack(context, PairErrorCode.fromError(e).message, kind: .error);
    }
  }

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
            onPressed: locked
                ? null
                : () async {
                    final now = DateTime.now();
                    final d = await showPTDateTimePicker(
                      ctx,
                      initial: picked ?? now.add(const Duration(days: 30)),
                      min: DateTime(now.year, now.month, now.day),
                      max: now.add(const Duration(days: 365 * 3)),
                      dateOnly: true,
                      boundsCaption: 'Three years ahead is as far as we can plan.',
                    );
                    if (d != null) setState(() => picked = d);
                  },
          ),
          TextField(
            controller: labelController,
            enabled: !locked,
            maxLength: 60,
            style: PTText.body,
            decoration: const InputDecoration(hintText: 'A label, like "Sam lands at Heathrow"'),
          ),
          PTToggleRow(
            title: 'Show on the lobby',
            subtitle: 'Only on your own lobby',
            value: show,
            onChanged: (v) => setState(() => show = v),
          ),
          if (iSetIt)
            PTToggleRow(
              title: 'Either of us can edit',
              subtitle: shared ? '$first can change the date too' : 'Only you can change it',
              value: shared,
              onChanged: (v) => setState(() => shared = v),
            )
          else
            Text(
              '$first set this date and keeps it to themselves.',
              style: PTText.caption.copyWith(color: PTColors.fgSoft),
            ),
          Row(
            spacing: 10,
            children: [
              if (!locked)
                Expanded(
                  child: PTButton(
                    label: 'Clear',
                    variant: .secondary,
                    height: 44,
                    onPressed: () async {
                      Navigator.of(ctx).pop();
                      await run(
                        () => PairService.instance.setReunion(null, null, showOnLobby: show),
                      );
                    },
                  ),
                ),
              Expanded(
                child: PTButton(
                  label: locked ? 'Done' : 'Save',
                  height: 44,
                  onPressed: !locked && picked == null
                      ? null
                      : () async {
                          Navigator.of(ctx).pop();
                          await run(
                            () => locked
                                ? PairService.instance.setReunion(
                                    pair.reunionOn,
                                    pair.reunionLabel,
                                    showOnLobby: show,
                                  )
                                : PairService.instance.setReunion(
                                    picked,
                                    labelController.text,
                                    sharedEdit: iSetIt ? shared : null,
                                    showOnLobby: show,
                                  ),
                          );
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

/// Invite by email. The wording is deliberate: the answer is the same whether or
/// not an account matched, because a different one would tell anybody which
/// addresses have accounts. The invite link above stays the sure way to reach
/// someone who has not signed up yet.
class _EmailInvite extends StatefulWidget {
  const _EmailInvite();

  @override
  State<_EmailInvite> createState() => _EmailInviteState();
}

class _EmailInviteState extends State<_EmailInvite> {
  final _email = TextEditingController();
  bool _busy = false;
  bool _sent = false;
  String? _problem;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _problem = null;
      _sent = false;
    });
    try {
      await PairService.instance.inviteByEmail(_email.text);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _sent = true;
        _email.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _problem = PairErrorCode.fromError(e).message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 10,
      children: [
        const SizedBox(height: 4),
        const PairKicker('Or invite by email'),
        TextField(
          key: const ValueKey('pair-email'),
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => _busy ? null : _send(),
          style: PTText.body,
          decoration: const InputDecoration(hintText: 'Their email address'),
        ),
        PTButton(
          label: 'Send invite',
          variant: .secondary,
          icon: BoothIcons.mail,
          height: 44,
          loading: _busy,
          onPressed: _send,
        ),
        // The note and the two lines that can follow it share a column, so a line that
        // is not there takes no space and one that is folds open under the note.
        Column(
          crossAxisAlignment: .stretch,
          children: [
            Text(
              "Accounts that hide their email with Apple can't be found this way. Send those the link or code.",
              style: PTText.caption.copyWith(color: PTColors.fgMute, height: 1.45),
            ),
            PTRevealKeep(
              visible: _sent,
              gap: 10,
              child: Text(
                'Invite on its way. If that address has an account, they will see it in the app. '
                'Not sure they have one? The link above works either way.',
                style: PTText.caption.copyWith(color: PTColors.fgSoft, height: 1.45),
              ),
            ),
            PTRevealKeep(
              visible: _problem != null,
              gap: 10,
              child: Text(
                _problem ?? '',
                style: PTText.body.copyWith(color: PTColors.danger, fontSize: 14),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
