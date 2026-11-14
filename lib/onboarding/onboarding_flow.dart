import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../platform.dart';
import '../profile/profile_models.dart';
import '../ui/booth.dart';
import '../ui/booth_icons.g.dart';
import '../ui/buttons.dart';
import '../ui/coach_mark.dart';
import '../ui/glass.dart';
import '../ui/identity.dart';
import '../ui/inputs.dart';
import '../ui/pt_motion.dart';
import '../ui/pt_theme.dart';
import '../ui/responsive.dart';
import '../ui/rolling_text.dart';
import 'onboarding_logic.dart';

/// What the first-night flow came back with.
class OnboardingResult {
  const OnboardingResult({required this.name, this.path, this.skippedAt});

  /// The name to save, or null to keep the current one (skipped before it).
  final String? name;

  /// Null when skipped, or when the flow had no path question (an invite).
  final OnboardingPath? path;

  /// The step Skip was pressed on, or null when the flow was finished.
  final OnboardingStep? skippedAt;

  bool get skipped => skippedAt != null;
}

/// Shows the first-night flow (boards 87 and 88): full screen on a phone, a
/// 480 px panel over the dimmed lobby from [kDesktopMinWidth] up. Always
/// completes with a result - there is no way out of it that is not Skip.
Future<OnboardingResult> showOnboarding(
  BuildContext context, {
  required Profile profile,
  String? inviteCode,
}) async {
  final wide = MediaQuery.sizeOf(context).width >= kDesktopMinWidth;
  Widget flow(bool panel) => OnboardingFlow(profile: profile, inviteCode: inviteCode, panel: panel);
  final OnboardingResult? result;
  if (wide) {
    result = await showGlassDialog<OnboardingResult>(
      context: context,
      barrierDismissible: false,
      scrollable: false,
      width: 480,
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 28),
      builder: (_) => flow(true),
    );
  } else {
    result = await Navigator.of(context, rootNavigator: true).push<OnboardingResult>(
      PageRouteBuilder(
        transitionDuration: PTMotion.functional(context, PTMotion.page),
        reverseTransitionDuration: PTMotion.functional(context, PTMotion.page),
        // Off the hinge on a fold, like every one-column screen.
        pageBuilder: (_, _, _) => PTHingeSafe(child: flow(false)),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: PTMotion.enter),
          child: child,
        ),
      ),
    );
  }
  return result ?? const OnboardingResult(name: null, skippedAt: .name);
}

class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key, required this.profile, required this.panel, this.inviteCode});

  final Profile profile;

  /// The desktop panel shape (inside a glass dialog) rather than a full page.
  final bool panel;

  /// Set when the user arrived from an invite: name only, then the room.
  final String? inviteCode;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  late final bool _invited = widget.inviteCode != null;
  late final List<OnboardingStep> _steps = onboardingSteps(invited: _invited);
  late final List<OnboardingPath> _options = pathOptions(isGuest: widget.profile.isGuest);
  late final TextEditingController _name = TextEditingController(
    text: initialName(widget.profile.displayName),
  );

  /// Holds focus for the shortcuts (Esc, arrows) wherever no text field has it.
  final _keys = FocusNode(debugLabel: 'onboarding', skipTraversal: true);
  int _index = 0;

  /// Which way the last step change went, so the swap slides the way the user moved.
  int _dir = 1;
  OnboardingPath _path = .friends;
  String? _error;

  OnboardingStep get _step => _steps[_index];
  bool get _last => _index == _steps.length - 1;

  @override
  void initState() {
    super.initState();
    _name.addListener(() {
      if (_error != null) setState(() => _error = null);
      setState(() {}); // the ticket preview follows the field
    });
    // On desktop the name field takes focus itself; elsewhere the shortcuts do
    // (a phone should not open its keyboard before the user has read the step).
    if (!isDesktop) WidgetsBinding.instance.addPostFrameCallback((_) => _keys.requestFocus());
  }

  @override
  void dispose() {
    _keys.dispose();
    _name.dispose();
    super.dispose();
  }

  void _skip() => Navigator.of(context).pop(
    OnboardingResult(
      // Skipping past the name step keeps what was typed there.
      name: _index > 0 ? _name.text.trim() : null,
      skippedAt: _step,
    ),
  );

  void _continue() {
    if (_step == .name) {
      final err = nameError(_name.text);
      if (err != null) {
        setState(() => _error = err);
        return;
      }
    }
    if (!_last) {
      setState(() {
        _index++;
        _dir = 1;
      });
      _keys.requestFocus();
      return;
    }
    Navigator.of(context)
        .pop(OnboardingResult(name: _name.text.trim(), path: _invited ? null : _path));
  }

  void _back() => setState(() {
    _index--;
    _dir = -1;
  });

  void _movePath(int delta) {
    final i = (_options.indexOf(_path) + delta).clamp(0, _options.length - 1);
    setState(() => _path = _options[i]);
  }

  @override
  Widget build(BuildContext context) {
    final body = LayoutBuilder(
      builder: (context, box) {
        // Pinned header and footer with only the step scrolling, unless the
        // space is too short for even that (a phone on its side with the
        // keyboard up): then everything scrolls together.
        final tight = box.hasBoundedHeight && box.maxHeight < 200;
        final step = SingleChildScrollView(
          keyboardDismissBehavior: .onDrag,
          primary: false,
          child: _shifting(),
        );
        final column = Column(
          mainAxisSize: widget.panel || tight ? .min : .max,
          crossAxisAlignment: .stretch,
          children: [
            _header(),
            SizedBox(height: widget.panel ? 18 : 26),
            // The step's words and controls change as one keyed swap; the
            // panel's height eases to the new step's (PTShift sizes itself).
            if (tight)
              _shifting()
            else if (widget.panel)
              Flexible(child: step)
            else
              Expanded(child: step),
            SizedBox(height: widget.panel ? 22 : 16),
            _footer(),
          ],
        );
        return tight
            ? SingleChildScrollView(keyboardDismissBehavior: .onDrag, child: column)
            : column;
      },
    );
    final shortcuts = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _skip,
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _movePath(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _movePath(-1),
      },
      child: Focus(focusNode: _keys, child: body),
    );
    if (widget.panel) return shortcuts;
    return Scaffold(
      backgroundColor: PTColors.canvas,
      body: SafeArea(
        child: Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 16), child: shortcuts),
      ),
    );
  }

  /// The step swap. The leaving step is laid out unbounded while it slides, so
  /// both are pinned to the width the flow really has.
  Widget _shifting() => LayoutBuilder(
    builder: (context, box) => PTShift(
      keyValue: _step,
      dir: _dir,
      axis: Axis.horizontal,
      distance: 0.25,
      align: Alignment.topCenter,
      child: SizedBox(width: box.maxWidth, child: _stepBody()),
    ),
  );

  Widget _header() {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          if (_invited)
            Text("YOU'RE INVITED", style: PTText.label)
          else
            CoachDots(step: _index + 1, steps: _steps.length),
          const Spacer(),
          TextButton(onPressed: _skip, child: const Text('Skip')),
        ],
      ),
    );
  }

  Widget _stepBody() => switch (_step) {
    .name => _nameStep(),
    .path => _pathStep(),
  };

  Widget _heading({required String kicker, required String title, String? lead}) {
    return Column(
      crossAxisAlignment: .start,
      spacing: 10,
      children: [
        if (kicker.isNotEmpty) Text(kicker, style: PTText.label),
        Text(
          title,
          style: PTText.display.copyWith(
            fontSize: widget.panel ? 34 : 40,
            height: 1.0,
            letterSpacing: -1.6,
          ),
        ),
        if (lead != null)
          Text(lead, style: PTText.body.copyWith(color: PTColors.fgSoft, height: 1.45)),
      ],
    );
  }

  Widget _nameStep() {
    final typed = _name.text.trim();
    final shown = typed.isEmpty ? 'Your name' : typed;
    final p = widget.profile;
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 18,
      children: [
        if (_invited)
          _heading(kicker: '', title: 'Someone saved you a seat.')
        else
          _heading(
            kicker: 'STEP 1 OF ${_steps.length} · YOUR TICKET',
            title: 'What name goes on your ticket?',
            lead: "It's what everyone in the room sees next to your chat and your facecam.",
          ),
        if (_invited) _inviteTicket() else _nameTicket(p, shown),
        Column(
          crossAxisAlignment: .stretch,
          spacing: 8,
          children: [
            PTTextField(
              controller: _name,
              label: _invited ? 'Your name in the room' : 'Display name',
              hint: 'Maya',
              maxLength: kMaxDisplayName,
              autofocus: isDesktop,
              errorText: _error,
              onSubmitted: (_) => _continue(),
            ),
            if (!_invited)
              Text(
                nameNote(p.authProvider, displayName: p.displayName, email: p.email),
                style: PTText.finePrint,
              ),
          ],
        ),
      ],
    );
  }

  Widget _nameTicket(Profile p, String shown) {
    return PTTicket(
      paper: true,
      stubWidth: 80,
      semanticLabel: 'Your ticket, for $shown',
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
        child: Column(
          crossAxisAlignment: .start,
          mainAxisSize: .min,
          spacing: 8,
          children: [
            Text(
              'ADMIT ONE · SCREEN 01',
              style: PTText.label.copyWith(
                fontSize: 10,
                color: PTColors.canvas.withValues(alpha: 0.62),
              ),
            ),
            Row(
              spacing: 10,
              children: [
                PTAvatar(userId: p.id, displayName: shown, avatarUrl: p.avatarUrl, size: 28),
                Flexible(
                  child: Text(
                    shown,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: PTText.cardHeading.copyWith(fontSize: 21, color: PTColors.canvas),
                  ),
                ),
              ],
            ),
            Text(
              p.isGuest ? 'Guest seat' : 'Free seat',
              style: PTText.finePrint.copyWith(color: PTColors.canvas.withValues(alpha: 0.62)),
            ),
          ],
        ),
      ),
      stub: Column(
        mainAxisSize: .min,
        spacing: 6,
        children: [
          Text(
            'SEAT',
            style: PTText.label.copyWith(
              fontSize: 10,
              color: PTColors.canvas.withValues(alpha: 0.62),
            ),
          ),
          Text(
            'A·01',
            style: PTText.mono.copyWith(fontSize: 18, fontWeight: .w600, color: PTColors.canvas),
          ),
        ],
      ),
    );
  }

  Widget _inviteTicket() {
    return PTTicket(
      paper: true,
      stubWidth: 104,
      semanticLabel: 'Invite to room ${widget.inviteCode}',
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
        child: Column(
          crossAxisAlignment: .start,
          mainAxisSize: .min,
          spacing: 5,
          children: [
            Text(
              'INVITE LINK',
              style: PTText.label.copyWith(fontSize: 10, color: PTColors.liveInk),
            ),
            Text(
              'Admit one',
              style: PTText.cardHeading.copyWith(fontSize: 18, color: PTColors.canvas),
            ),
            Text(
              'Your name first, then the room',
              style: PTText.mono.copyWith(
                fontSize: 11,
                color: PTColors.canvas.withValues(alpha: 0.62),
              ),
            ),
          ],
        ),
      ),
      stub: Text(
        widget.inviteCode!,
        style: PTText.mono.copyWith(
          fontSize: 14,
          fontWeight: .w600,
          letterSpacing: 0.6,
          color: PTColors.canvas,
        ),
      ),
    );
  }

  Widget _pathStep() {
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 18,
      children: [
        _heading(
          kicker: 'STEP 2 OF ${_steps.length} · TONIGHT',
          title: "Who's watching with you?",
          lead: "We'll set up the right first step. Everything stays open either way.",
        ),
        Column(
          crossAxisAlignment: .stretch,
          spacing: 10,
          children: [for (final o in _options) _option(o)],
        ),
      ],
    );
  }

  Widget _option(OnboardingPath o) {
    final on = o == _path;
    final (icon, tint) = switch (o) {
      .friends => (BoothIcons.group, PTColors.primary),
      .partner => (BoothIcons.heart, PTColors.dangerBorder),
      .browsing => (BoothIcons.search, PTColors.fgDim),
    };
    return Semantics(
      selected: on,
      inMutuallyExclusiveGroup: true,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _path = o),
        child: AnimatedContainer(
          duration: PTMotion.functional(context, PTMotion.hover),
          curve: PTMotion.enter,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: widget.panel ? PTColors.canvas : PTColors.glassBase,
            border: Border.all(color: on ? PTColors.primary : PTColors.rail),
            borderRadius: BorderRadius.circular(PTRadius.panel),
          ),
          child: Row(
            crossAxisAlignment: .start,
            spacing: 14,
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: PTColors.aisle,
                  borderRadius: BorderRadius.circular(PTRadius.control),
                ),
                child: Icon(icon, size: 20, color: tint),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  spacing: 3,
                  children: [
                    Text(pathTitle(o), style: PTText.panelHeading.copyWith(fontSize: 16)),
                    Text(
                      pathBody(o),
                      style: PTText.caption.copyWith(color: PTColors.fgSoft, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _footer() {
    final label = _invited ? 'Take your seat' : (_step == .name ? "That's me" : 'Continue');
    final primary = PTButton(
      label: label,
      height: widget.panel ? 46 : 50,
      expand: !widget.panel,
      onPressed: _continue,
    );
    if (!widget.panel) return primary;
    return Row(
      children: [
        if (_index > 0) TextButton(onPressed: _back, child: const Text('Back')),
        const Spacer(),
        primary,
      ],
    );
  }
}
