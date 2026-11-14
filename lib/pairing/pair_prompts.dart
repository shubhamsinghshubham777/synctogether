import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../analytics.dart';
import '../diagnostics.dart';
import '../nav.dart';
import '../platform.dart';
import '../profile/profile_service.dart';
import '../ui/booth_icons.g.dart';
import '../ui/banners.dart';
import '../ui/buttons.dart';
import '../ui/glass.dart';
import '../ui/inputs.dart';
import '../ui/pt_theme.dart';
import 'pair_logic.dart';
import 'pair_models.dart';
import 'pair_service.dart';
import 'pair_widgets.dart';
import 'push_service.dart';

/// Ask the OS for notification permission right here. Only a refusal sends the
/// person on to the settings screen, which explains how to undo it.
Future<void> turnOnPush(BuildContext context) async {
  final result = await PushService.instance.enable();
  if (result == PushPermission.denied && context.mounted) {
    openPage(context, '/lobby/pair/notifications');
  }
}

/// A quiet one-line offer to turn notifications on, gone once they are on (or
/// where the platform cannot). [text] says what it is for, in that moment.
class PairPushPrompt extends StatelessWidget {
  const PairPushPrompt({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PushService.instance,
      builder: (context, _) {
        final push = PushService.instance;
        if (!push.supported || push.enabled) return const SizedBox.shrink();
        return PairPanel(
          padding: const EdgeInsets.all(14),
          child: Row(
            spacing: 12,
            children: [
              const Icon(BoothIcons.bell, size: 20, color: PTColors.fgDim),
              Expanded(
                child: Text(
                  text,
                  style: PTText.body.copyWith(fontSize: 14, color: PTColors.fgDim, height: 1.35),
                ),
              ),
              DialogTextButton(label: 'Turn on', onPressed: () => turnOnPush(context)),
            ],
          ),
        );
      },
    );
  }
}

/// Right after two people pair is the one moment a notification is obviously
/// worth having, so ask once, in words, before the system prompt does.
Future<void> offerPushAfterPairing(BuildContext context, String partnerFirstName) async {
  final push = PushService.instance;
  if (!push.supported || push.enabled) return;
  final yes = await showGlassDialog<bool>(
    context: context,
    width: 420,
    builder: (ctx) => Column(
      crossAxisAlignment: .stretch,
      spacing: 16,
      children: [
        Text('Hear it when $partnerFirstName calls?', style: PTText.screenTitle),
        Text(
          'A quick ping when they call, or when a date night is about to start. '
          'Quiet at night, and you can change it any time.',
          style: PTText.body.copyWith(color: PTColors.fgSoft, height: 1.5),
        ),
        Row(
          spacing: 10,
          children: [
            Expanded(
              child: PTButton(
                label: 'Not now',
                variant: .secondary,
                height: 44,
                onPressed: () => Navigator.of(ctx).pop(false),
              ),
            ),
            Expanded(
              child: PTButton(
                label: 'Turn on',
                height: 44,
                onPressed: () => Navigator.of(ctx).pop(true),
              ),
            ),
          ],
        ),
      ],
    ),
  );
  if (yes == true) await push.enable();
}

/// "What should your person call you?" - only for an account whose name is just
/// its email's local part (Sign in with Apple's hidden address gives a random
/// handle), shown on the invite and accept screens where the other person is
/// about to read it. Asked until answered, once, per account per device.
class PairNameCheck extends StatefulWidget {
  const PairNameCheck({super.key});

  @override
  State<PairNameCheck> createState() => _PairNameCheckState();
}

class _PairNameCheckState extends State<PairNameCheck> {
  final _name = TextEditingController();
  bool _seeded = false;
  bool _answered = false;
  bool _saving = false;
  String? _checkedFor;

  static String _key(String id) => 'pair_name_answered_$id';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _readAnswered(String id) async {
    _checkedFor = id;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted && (prefs.getBool(_key(id)) ?? false)) setState(() => _answered = true);
    } catch (_) {
      // Unreadable storage only means we may ask again.
    }
  }

  Future<void> _remember(String id) async {
    if (mounted) setState(() => _answered = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key(id), true);
    } catch (_) {}
  }

  Future<void> _save(String id) async {
    final value = _name.text.trim();
    if (value.isEmpty) {
      showPTSnack(context, 'Add a name first, or keep the one you have.', kind: .error);
      return;
    }
    setState(() => _saving = true);
    try {
      await ProfileService.instance.updateDisplayName(value);
      await _remember(id);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'saving the display name from pairing');
      if (mounted) {
        setState(() => _saving = false);
        showPTSnack(context, "Couldn't save that. Try again.", kind: .error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ProfileService.instance,
      builder: (context, _) {
        final p = ProfileService.instance.profile;
        if (p == null || _answered || !isGenericName(p.displayName, p.email)) {
          return const SizedBox.shrink();
        }
        if (_checkedFor != p.id) _readAnswered(p.id);
        if (!_seeded) {
          _seeded = true;
          _name.text = suggestedName(p.email);
        }
        return PairPanel(
          child: Column(
            crossAxisAlignment: .stretch,
            spacing: 10,
            children: [
              Text('What should your person call you?', style: PTText.panelHeading),
              Text(
                'This is the name they see. You can change it later in Profile.',
                style: PTText.caption.copyWith(color: PTColors.fgSoft, height: 1.45),
              ),
              TextField(
                controller: _name,
                maxLength: 40,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _saving ? null : _save(p.id),
                style: PTText.body,
                decoration: const InputDecoration(
                  hintText: 'Your first name works',
                  counterText: '',
                ),
              ),
              Row(
                spacing: 10,
                children: [
                  Expanded(
                    child: PTButton(
                      label: 'Save',
                      variant: .secondary,
                      height: 44,
                      loading: _saving,
                      onPressed: () => _save(p.id),
                    ),
                  ),
                  DialogTextButton(
                    label: 'Keep it',
                    onPressed: _saving ? null : () => _remember(p.id),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The invitee's way in when all they were sent is a code: type it here and the
/// accept screen opens. (The lobby's ticket box takes it too, but nothing there
/// says so.)
class PairCodeEntry extends StatefulWidget {
  const PairCodeEntry({super.key});

  @override
  State<PairCodeEntry> createState() => _PairCodeEntryState();
}

class _PairCodeEntryState extends State<PairCodeEntry> {
  final _codeKey = GlobalKey<PTCodeInputState>();
  String _code = '';
  bool _busy = false;

  Future<void> _go() async {
    if (_code.length != PTCodeInput.length) {
      showPTSnack(context, 'Enter the 6-character code.', kind: .error);
      return;
    }
    setState(() => _busy = true);
    try {
      final invite = await PairService.instance.previewInvite(_code);
      if (!mounted) return;
      if (invite.status != PairInviteStatus.pending) {
        showPTSnack(context, 'That code has already been used or has expired.', kind: .error);
        _codeKey.currentState?.clear();
        return;
      }
      _codeKey.currentState?.clear();
      context.go('/lobby/pair/accept/${invite.code}');
    } catch (e) {
      if (mounted) {
        showPTSnack(context, PairErrorCode.fromError(e).message, kind: .error);
        _codeKey.currentState?.clear();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 10,
      children: [
        const SizedBox(height: 4),
        const PairKicker('Got a code from your person?'),
        PTCodeInput(key: _codeKey, boxHeight: 52, onChanged: (v) => _code = v),
        PTButton(
          label: 'Pair with this code',
          variant: .secondary,
          height: 44,
          loading: _busy,
          onPressed: _busy ? null : _go,
        ),
      ],
    );
  }
}

/// One Patron seat covers both people, which is the honest reason for a couple
/// to buy one - so say it, once, where they manage the pair, and only to a pair
/// that has none. A quiet row, not a gate: nothing here is taken away.
class PairPatronNote extends StatefulWidget {
  const PairPatronNote({super.key});

  @override
  State<PairPatronNote> createState() => _PairPatronNoteState();
}

class _PairPatronNoteState extends State<PairPatronNote> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    final pair = PairService.instance.pair;
    if (!canSellPremium || pair == null || pair.patron) return const SizedBox.shrink();
    if (!_shown) {
      _shown = true;
      Analytics.instance.track('upgrade_cta_shown', {'surface': 'pair_hub'});
    }
    return PairPanel(
      brass: true,
      padding: const EdgeInsets.all(14),
      child: Row(
        spacing: 12,
        children: [
          const Icon(BoothIcons.crown, size: 20, color: PTColors.premium),
          Expanded(
            child: Text(
              'A Patron seat on either side gives you both video, date nights and your full history.',
              style: PTText.body.copyWith(fontSize: 14, color: PTColors.fgDim, height: 1.35),
            ),
          ),
          DialogTextButton(
            label: 'See Patron',
            onPressed: () {
              Analytics.instance.track('upgrade_cta_clicked', {
                'surface': 'pair_hub',
                'action': 'subscribe',
              });
              openPage(context, '/lobby/subscribe?source=pair_hub');
            },
          ),
        ],
      ),
    );
  }
}

/// What do I call my person? A label only I see, kept per person in the pair and
/// never shown to them. Empty (or "Use their name") goes back to the name they
/// chose. Reachable any time after pairing, from the pencil by their name.
Future<void> showPartnerNicknameDialog(BuildContext context, PairPartner partner) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final result = await showGlassDialog<String>(
    context: context,
    width: 420,
    builder: (ctx) => _NicknameForm(partner: partner),
  );
  if (result == null) return;
  try {
    await PairService.instance.setPartnerNickname(result);
  } catch (e) {
    final failure = PairErrorCode.fromError(e);
    final text = failure == PairErrorCode.unknown
        ? "Couldn't save that. Try again."
        : failure.message;
    if (context.mounted) {
      showPTSnack(context, text, kind: .error);
    } else {
      messenger?.showSnackBar(SnackBar(content: Text(text)));
    }
  }
}

/// The dialog's own widget, so it owns - and disposes - its controller: closing
/// the dialog leaves it on screen for the exit animation, and a controller
/// disposed by the caller at that moment is used after it is gone.
class _NicknameForm extends StatefulWidget {
  const _NicknameForm({required this.partner});

  final PairPartner partner;

  @override
  State<_NicknameForm> createState() => _NicknameFormState();
}

class _NicknameFormState extends State<_NicknameForm> {
  late final _controller = TextEditingController(text: widget.partner.nickname ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final partner = widget.partner;
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 14,
      children: [
        Text('What do you call ${partner.nameTheyChose}?', style: PTText.screenTitle),
        Text(
          'Only you see this. ${partner.nameTheyChose.split(' ').first} keeps their own name, '
          'and nobody is told what you chose.',
          style: PTText.body.copyWith(color: PTColors.fgSoft, height: 1.5),
        ),
        TextField(
          controller: _controller,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
          style: PTText.body,
          decoration: InputDecoration(hintText: partner.nameTheyChose, counterText: ''),
        ),
        Row(
          spacing: 10,
          children: [
            Expanded(
              child: PTButton(
                label: 'Save',
                height: 44,
                onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
              ),
            ),
            if (partner.nickname != null)
              DialogTextButton(
                label: 'Use their name',
                onPressed: () => Navigator.of(context).pop(''),
              ),
          ],
        ),
      ],
    );
  }
}
