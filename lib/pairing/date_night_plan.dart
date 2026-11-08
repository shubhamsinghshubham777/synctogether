import 'dart:async';

import 'package:flutter/material.dart';

import '../analytics.dart';
import '../nav.dart';
import '../platform.dart';
import '../player/youtube/youtube_links.dart';
import '../ui/banners.dart';
import '../ui/booth_icons.g.dart';
import '../ui/buttons.dart';
import '../ui/glass.dart';
import '../ui/inputs.dart';
import '../ui/pt_motion.dart';
import '../ui/pt_theme.dart';
import '../ui/responsive.dart';
import 'pair_logic.dart';
import 'pair_models.dart';
import 'pair_page.dart';
import 'pair_service.dart';
import 'pair_widgets.dart';

/// Date then time, as the platform's own pickers. Returns the chosen local
/// moment, or null if either was dismissed.
Future<DateTime?> pickNightTime(BuildContext context, {DateTime? initial}) async {
  final now = DateTime.now();
  final start = initial ?? DateTime(now.year, now.month, now.day + 1, 21);
  final day = await showDatePicker(
    context: context,
    initialDate: start.isBefore(now) ? now : start,
    firstDate: DateTime(now.year, now.month, now.day),
    lastDate: now.add(const Duration(days: 365)),
  );
  if (day == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: start.hour, minute: start.minute),
  );
  if (time == null) return null;
  return DateTime(day.year, day.month, day.day, time.hour, time.minute);
}

/// Plan a date night. A phone gets a full page (the form is long and wants its
/// primary pinned under it); everything wider gets the dialog. Shows the Patron
/// explanation instead when neither partner has it.
Future<void> showPlanNight(BuildContext context) async {
  final pair = PairService.instance.pair;
  if (pair == null) return;
  if (!pair.patron) {
    await _showGate(context);
    return;
  }
  if (layoutOf(context) == PTLayout.portrait) {
    openPage(context, '/lobby/pair/plan-night');
    return;
  }
  final form = PlanNightController(pair);
  await showGlassDialog<void>(
    context: context,
    width: 440,
    sheetOnCompact: true,
    builder: (ctx) => ListenableBuilder(
      listenable: form,
      builder: (context, _) => Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        spacing: 14,
        children: [
          Text('Plan a date night', style: PTText.screenTitle.copyWith(fontSize: 24)),
          Flexible(
            child: SingleChildScrollView(child: PlanNightBody(form: form)),
          ),
          Row(
            spacing: 10,
            children: [
              Expanded(
                child: PTButton(
                  label: form.lateForThem ? 'Pick another time' : 'Cancel',
                  variant: .secondary,
                  height: 44,
                  onPressed: form.lateForThem
                      ? () => form.pickTime(ctx)
                      : () => Navigator.of(ctx).pop(),
                ),
              ),
              Expanded(
                child: PTButton(
                  label: form.sendLabel,
                  height: 44,
                  loading: form.busy,
                  onPressed: () async {
                    if (await form.send() && ctx.mounted) Navigator.of(ctx).pop();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  form.dispose();
}

/// The phone's version of the same form: a page with the primary pinned.
class PlanNightScreen extends StatefulWidget {
  const PlanNightScreen({super.key});

  @override
  State<PlanNightScreen> createState() => _PlanNightScreenState();
}

class _PlanNightScreenState extends State<PlanNightScreen> {
  PlanNightController? _form;

  @override
  void initState() {
    super.initState();
    final pair = PairService.instance.pair;
    if (pair != null) _form = PlanNightController(pair);
  }

  @override
  void dispose() {
    _form?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final form = _form;
    if (form == null) {
      return const PairPage(title: 'Plan a date night', children: []);
    }
    return ListenableBuilder(
      listenable: form,
      builder: (context, _) => PairPage(
        title: 'Plan a date night',
        footer: PTButton(
          label: form.sendLabel,
          icon: BoothIcons.play,
          loading: form.busy,
          onPressed: () async {
            if (await form.send() && context.mounted) Navigator.of(context).maybePop();
          },
        ),
        children: [PlanNightBody(form: form)],
      ),
    );
  }
}

/// What the planner has typed and chosen, and what sending it means. Owned by
/// whichever surface (dialog or page) shows the form, so both behave the same.
class PlanNightController extends ChangeNotifier {
  PlanNightController(this.pair)
    : when = DateTime.now()
          .add(const Duration(days: 1))
          .copyWith(hour: 21, minute: 0, second: 0, millisecond: 0, microsecond: 0);

  final PairInfo pair;
  final title = TextEditingController();
  final link = TextEditingController();
  DateTime when;
  bool watchingLink = false;
  bool busy = false;
  String? problem;

  // The pasted link, judged only once typing pauses (a half-typed address is not
  // an error), and sooner when the field is emptied.
  LinkCheck linkCheck = LinkCheck.empty;
  Timer? _linkTimer;

  String get first => pair.partner.displayName.split(' ').first;

  NightPlacement get placement => placeNight(when.toUtc(), partnerZone: pair.partner.timezone);

  bool get lateForThem => placement.lateForThem;

  String get sendLabel => lateForThem ? 'Send anyway' : 'Send to $first';

  /// The link in the one shape every room understands, or null.
  String? get canonicalLink {
    final id = youtubeVideoId(link.text.trim());
    return id == null ? null : canonicalYouTubeUrl(id);
  }

  void setWatching({required bool link}) {
    watchingLink = link;
    problem = null;
    notifyListeners();
  }

  void linkChanged(String _) {
    _linkTimer?.cancel();
    if (link.text.trim().isEmpty) {
      linkCheck = LinkCheck.empty;
      notifyListeners();
      return;
    }
    _linkTimer = Timer(const Duration(milliseconds: 500), () {
      linkCheck = canonicalLink == null ? LinkCheck.invalid : LinkCheck.valid;
      notifyListeners();
    });
  }

  Future<void> pickDay(BuildContext context) async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: when.isBefore(now) ? now : when,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (day == null) return;
    when = DateTime(day.year, day.month, day.day, when.hour, when.minute);
    notifyListeners();
  }

  Future<void> pickClock(BuildContext context) async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: when.hour, minute: when.minute),
    );
    if (time == null) return;
    when = DateTime(when.year, when.month, when.day, time.hour, time.minute);
    notifyListeners();
  }

  /// Both pickers in turn: the late-for-them warning's "Pick another time".
  Future<void> pickTime(BuildContext context) async {
    final picked = await pickNightTime(context, initial: when);
    if (picked == null) return;
    when = picked;
    notifyListeners();
  }

  /// Send it. Returns true when it went. Nothing exists on the server until it
  /// does, so a retry after a failure can never make a second night.
  Future<bool> send() async {
    if (busy) return false;
    if (title.text.trim().isEmpty) {
      problem = 'Give the night a name first.';
      notifyListeners();
      return false;
    }
    String? url;
    if (watchingLink) {
      url = canonicalLink;
      if (url == null) {
        linkCheck = link.text.trim().isEmpty ? LinkCheck.empty : LinkCheck.invalid;
        problem = link.text.trim().isEmpty ? 'Paste a link, or choose together.' : null;
        notifyListeners();
        return false;
      }
    }
    busy = true;
    problem = null;
    notifyListeners();
    try {
      await PairService.instance.planNight(title: title.text, startsAt: when, youtubeUrl: url);
      return true;
    } catch (e) {
      final failure = PairErrorCode.fromError(e);
      problem = failure == PairErrorCode.unknown ? "Couldn't send that just now." : failure.message;
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _linkTimer?.cancel();
    title.dispose();
    link.dispose();
    super.dispose();
  }
}

enum LinkCheck { empty, valid, invalid }

/// The form's fields: what the night is, when, how that lands on each clock, and
/// what (if anything) you will be watching.
class PlanNightBody extends StatelessWidget {
  const PlanNightBody({super.key, required this.form});

  final PlanNightController form;

  @override
  Widget build(BuildContext context) {
    final placement = form.placement;
    final differ = placement.zonesDiffer && placement.theirs != null;
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 12,
      children: [
        const PairKicker("What's the night?"),
        PTTextField(
          controller: form.title,
          hint: 'Spirited Away',
          prefixIcon: BoothIcons.film,
          maxLength: 120,
        ),
        Row(
          spacing: 10,
          children: [
            Expanded(
              child: _PickerField(
                label: 'Day',
                icon: BoothIcons.calendar,
                value: formatDay(form.when),
                onTap: () => form.pickDay(context),
              ),
            ),
            Expanded(
              child: _PickerField(
                label: 'Your time',
                icon: BoothIcons.clock,
                value: formatClock(form.when),
                onTap: () => form.pickClock(context),
              ),
            ),
          ],
        ),
        if (differ) ...[
          const PairKicker('Both of you, side by side'),
          _Strips(placement: placement, partnerName: form.first),
          if (placement.lateForThem)
            _Verdict(
              warn: true,
              text:
                  'That is ${formatClock(placement.theirs!)} for ${form.first}. Send it anyway, '
                  'or try a time that lands in their evening.',
            )
          else
            _Verdict(
              warn: false,
              text:
                  '${daypart(placement.theirs!.hour)} for ${form.first}.'
                  '${placement.meAwake ? ' Both of you are awake.' : ''}',
            ),
        ] else
          // Same zone, or theirs is unknown: one clock is the whole story.
          PairPanel(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              spacing: 10,
              children: [
                const Icon(BoothIcons.clock, size: 18, color: PTColors.primary),
                Expanded(
                  child: Text(
                    formatMoment(form.when),
                    style: PTText.mono.copyWith(fontSize: 15, color: PTColors.fg),
                  ),
                ),
              ],
            ),
          ),
        const PairKicker('What are you watching? · optional'),
        _AttachRow(
          icon: BoothIcons.youtube,
          title: 'A YouTube link',
          caption: 'Nothing to upload. Plays for both of you.',
          selected: form.watchingLink,
          onTap: () => form.setWatching(link: true),
        ),
        _AttachRow(
          icon: BoothIcons.film,
          title: "We'll choose together",
          caption: 'Pick something in Our Room on the night.',
          selected: !form.watchingLink,
          onTap: () => form.setWatching(link: false),
        ),
        if (form.watchingLink) _LinkField(form: form),
        if (form.problem != null)
          Text(form.problem!, style: PTText.body.copyWith(color: PTColors.danger, fontSize: 14)),
      ],
    );
  }
}

String daypart(int hour) => hour < 12
    ? 'Morning'
    : hour < 17
    ? 'Afternoon'
    : hour < 22
    ? 'Evening'
    : 'Night';

class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.label,
    required this.icon,
    required this.value,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 6,
      children: [
        PairKicker(label),
        PTButton(label: value, variant: .secondary, icon: icon, height: 46, onPressed: onTap),
      ],
    );
  }
}

/// One of the attach options: a single-select row with a radio at the right.
class _AttachRow extends StatelessWidget {
  const _AttachRow({
    required this.icon,
    required this.title,
    required this.caption,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String caption;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$title. $caption',
      excludeSemantics: true,
      child: PTPressable(
        onTap: onTap,
        pressedScale: 0.99,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? PTColors.aisle : PTColors.glassBase,
            borderRadius: BorderRadius.circular(PTRadius.control),
            border: Border.all(color: selected ? PTColors.primary : PTColors.rail),
          ),
          child: Row(
            spacing: 12,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: PTColors.canvas,
                  borderRadius: BorderRadius.circular(PTRadius.control),
                ),
                child: Icon(icon, size: 18, color: PTColors.primary),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  spacing: 2,
                  children: [
                    Text(title, style: PTText.body.copyWith(fontSize: 14.5, color: PTColors.fg)),
                    Text(caption, style: PTText.caption.copyWith(color: PTColors.fgSoft)),
                  ],
                ),
              ),
              _Radio(selected: selected),
            ],
          ),
        ),
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  const _Radio({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? PTColors.primary : null,
        border: selected ? null : Border.all(color: PTColors.railStrong, width: 1.5),
      ),
      child: selected ? const Icon(BoothIcons.checkBold, size: 13, color: PTColors.canvas) : null,
    );
  }
}

class _LinkField extends StatelessWidget {
  const _LinkField({required this.form});

  final PlanNightController form;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 8,
      children: [
        PTTextField(
          controller: form.link,
          hint: 'youtube.com/watch?v=…',
          prefixIcon: BoothIcons.link,
          autofocus: true,
          errorText: form.linkCheck == LinkCheck.invalid
              ? "Hmm, that doesn't look like a YouTube link."
              : null,
          onChanged: form.linkChanged,
        ),
        if (form.linkCheck == LinkCheck.valid)
          Row(
            spacing: 8,
            children: [
              const Icon(BoothIcons.check, size: 16, color: PTColors.online),
              Expanded(
                child: Text(
                  'Found it. This plays for both of you.',
                  style: PTText.caption.copyWith(color: PTColors.online),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _Verdict extends StatelessWidget {
  const _Verdict({required this.warn, required this.text});

  final bool warn;
  final String text;

  @override
  Widget build(BuildContext context) {
    if (!warn) {
      return Row(
        spacing: 8,
        children: [
          const Icon(BoothIcons.check, size: 16, color: PTColors.online),
          Expanded(
            child: Text(text, style: PTText.caption.copyWith(color: PTColors.online)),
          ),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PTColors.pillWarning,
        borderRadius: BorderRadius.circular(PTRadius.control),
        border: Border.all(color: PTColors.primary.withValues(alpha: 0.4)),
      ),
      child: Row(
        spacing: 10,
        children: [
          const Icon(BoothIcons.clock, size: 18, color: PTColors.warning),
          Expanded(
            child: Text(text, style: PTText.caption.copyWith(color: PTColors.warning, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

/// "Change what we're watching": the planner swaps the YouTube link on a night
/// already sent, or goes back to choosing together. Only the planner reaches it.
Future<void> showChangeWatching(BuildContext context, DateNight night) async {
  final link = TextEditingController(text: night.youtubeUrl ?? '');
  final result = await showGlassDialog<_WatchingChoice>(
    context: context,
    width: 420,
    sheetOnCompact: true,
    builder: (ctx) => _ChangeWatching(night: night, link: link),
  );
  link.dispose();
  if (result == null || !context.mounted) return;
  try {
    await PairService.instance.setNightAttachment(night.id, result.url);
  } catch (e) {
    if (context.mounted) {
      final failure = PairErrorCode.fromError(e);
      showPTSnack(
        context,
        failure == PairErrorCode.unknown ? "Couldn't change that just now." : failure.message,
        kind: .error,
      );
    }
  }
}

class _WatchingChoice {
  const _WatchingChoice(this.url);
  final String? url;
}

class _ChangeWatching extends StatefulWidget {
  const _ChangeWatching({required this.night, required this.link});

  final DateNight night;
  final TextEditingController link;

  @override
  State<_ChangeWatching> createState() => _ChangeWatchingState();
}

class _ChangeWatchingState extends State<_ChangeWatching> {
  late bool _useLink = widget.night.hasLink;
  String? _problem;

  void _save() {
    if (!_useLink) {
      Navigator.of(context).pop(const _WatchingChoice(null));
      return;
    }
    final id = youtubeVideoId(widget.link.text.trim());
    if (id == null) {
      setState(() => _problem = "Hmm, that doesn't look like a YouTube link.");
      return;
    }
    Navigator.of(context).pop(_WatchingChoice(canonicalYouTubeUrl(id)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      spacing: 12,
      children: [
        Text("Change what we're watching", style: PTText.screenTitle.copyWith(fontSize: 22)),
        _AttachRow(
          icon: BoothIcons.youtube,
          title: 'A YouTube link',
          caption: 'Nothing to upload. Plays for both of you.',
          selected: _useLink,
          onTap: () => setState(() => _useLink = true),
        ),
        _AttachRow(
          icon: BoothIcons.film,
          title: "We'll choose together",
          caption: 'Pick something in Our Room on the night.',
          selected: !_useLink,
          onTap: () => setState(() {
            _useLink = false;
            _problem = null;
          }),
        ),
        if (_useLink)
          PTTextField(
            controller: widget.link,
            hint: 'youtube.com/watch?v=…',
            prefixIcon: BoothIcons.link,
            autofocus: true,
            errorText: _problem,
            onChanged: (_) {
              if (_problem != null) setState(() => _problem = null);
            },
          ),
        Row(
          spacing: 10,
          children: [
            Expanded(
              child: PTButton(
                label: 'Cancel',
                variant: .secondary,
                height: 44,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            Expanded(
              child: PTButton(label: 'Save', height: 44, onPressed: _save),
            ),
          ],
        ),
      ],
    );
  }
}

Future<void> _showGate(BuildContext context) async {
  Analytics.instance.track('upgrade_cta_shown', {'surface': 'date_night'});
  await showGlassDialog<void>(
    context: context,
    width: 420,
    sheetOnCompact: true,
    builder: (ctx) => Column(
      crossAxisAlignment: .stretch,
      spacing: 14,
      children: [
        Row(
          spacing: 10,
          children: [
            Expanded(child: Text('Date nights', style: PTText.screenTitle.copyWith(fontSize: 24))),
            const PatronTag(),
          ],
        ),
        Text(
          'Planning a date night needs Patron on either side - one seat covers the both of you. '
          "Answering, moving or cancelling one you're sent never does.",
          style: PTText.body.copyWith(color: PTColors.fgSoft, height: 1.5),
        ),
        if (canSellPremium)
          PTButton(
            label: 'Get a Patron seat',
            icon: BoothIcons.crown,
            onPressed: () {
              Analytics.instance.track('upgrade_cta_clicked', {
                'surface': 'date_night',
                'action': 'subscribe',
              });
              Navigator.of(ctx).pop();
              openPage(context, '/lobby/subscribe?source=date_night');
            },
          ),
        PTButton(label: 'Not now', variant: .secondary, onPressed: () => Navigator.of(ctx).pop()),
      ],
    ),
  );
}

/// Both people's day as two 24-hour strips with the proposed time marked, night
/// shaded: the "is this a bad hour for them" answer, at a glance.
class _Strips extends StatelessWidget {
  const _Strips({required this.placement, required this.partnerName});

  final NightPlacement placement;
  final String partnerName;

  @override
  Widget build(BuildContext context) {
    return PairPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 12,
        children: [
          _Strip(label: 'You', wall: placement.mine, warn: false),
          if (placement.theirs != null)
            _Strip(
              label: placement.theirCity.isEmpty
                  ? partnerName
                  : '$partnerName · ${placement.theirCity}',
              wall: placement.theirs!,
              warn: placement.lateForThem,
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final h in const ['00', '06', '12', '18', '24'])
                Text(h, style: PTText.mono.copyWith(fontSize: 9, color: PTColors.fgMute)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip({required this.label, required this.wall, required this.warn});

  final String label;
  final DateTime wall;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final start = wall.hour + wall.minute / 60;
    final color = warn ? PTColors.warning : PTColors.primary;
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 6,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: .ellipsis,
                style: PTText.body.copyWith(fontSize: 13, color: PTColors.fgDim),
              ),
            ),
            Text(
              formatClock(wall),
              style: PTText.mono.copyWith(
                fontSize: 13,
                color: warn ? PTColors.warning : PTColors.fg,
              ),
            ),
          ],
        ),
        LayoutBuilder(
          builder: (context, box) {
            double x(double h) => box.maxWidth * h / 24;
            final window = (start + 3 > 24) ? 24 - start : 3.0;
            return SizedBox(
              height: 18,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: PTColors.glassBase,
                  borderRadius: BorderRadius.circular(PTRadius.control),
                  border: Border.all(color: PTColors.rail),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(PTRadius.control),
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        width: x(7),
                        top: 0,
                        bottom: 0,
                        child: const ColoredBox(color: PTColors.aisle),
                      ),
                      Positioned(
                        left: x(22),
                        right: 0,
                        top: 0,
                        bottom: 0,
                        child: const ColoredBox(color: PTColors.aisle),
                      ),
                      Positioned(
                        left: x(start),
                        width: x(window),
                        top: 2,
                        bottom: 2,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
