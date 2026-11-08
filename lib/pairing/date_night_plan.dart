import 'dart:async';

import 'package:flutter/material.dart';

import '../analytics.dart';
import '../diagnostics.dart';
import '../nav.dart';
import '../platform.dart';
import '../player/local_video.dart';
import '../player/local_video_chooser.dart';
import '../player/youtube/youtube_links.dart';
import '../profile/entitlement_service.dart';
import '../profile/profile_models.dart';
import '../profile/profile_service.dart';
import '../rooms/media_sharing_service.dart';
import '../ui/banners.dart';
import '../ui/booth_icons.g.dart';
import '../ui/buttons.dart';
import '../ui/glass.dart';
import '../ui/inputs.dart';
import '../ui/pt_date_time_logic.dart';
import '../ui/pt_date_time_picker.dart';
import '../ui/pt_motion.dart';
import '../ui/pt_theme.dart';
import '../ui/responsive.dart';
import 'date_night_upload.dart';
import 'pair_logic.dart';
import 'pair_models.dart';
import 'pair_page.dart';
import 'pair_service.dart';
import 'pair_widgets.dart';

/// One line about the other person's clock for a chosen moment, or null when
/// there is nothing to say (the same time zone, or a zone we do not know).
String? Function(DateTime moment) partnerLineFor(PairInfo pair, {required bool is24Hour}) {
  final first = pair.partner.displayName.split(' ').first;
  return (moment) {
    final p = placeNight(moment.toUtc(), partnerZone: pair.partner.timezone);
    final theirs = p.theirs;
    if (!p.zonesDiffer || theirs == null) return null;
    final onDay = theirs.day == p.mine.day ? '' : ' on ${weekdayLong(theirs.weekday)}';
    return "That's ${clockText(theirs.hour, theirs.minute, is24Hour: is24Hour)}$onDay for $first.";
  };
}

/// Date and time in one PT picker. Returns the chosen local moment, or null if it
/// was dismissed. [moving] says it is an existing night being moved; [part] is the
/// part of the picker that opens focused.
Future<DateTime?> pickNightTime(
  BuildContext context, {
  DateTime? initial,
  bool moving = false,
  PickerPart part = PickerPart.date,
}) {
  final now = DateTime.now();
  final start = initial ?? DateTime(now.year, now.month, now.day + 1, 21);
  final pair = PairService.instance.pair;
  return showPTDateTimePicker(
    context,
    initial: start,
    min: now,
    max: now.add(const Duration(days: 365)),
    part: part,
    movingFrom: moving && initial != null
        ? 'Moving from ${formatDay(initial)}, ${formatClock(initial)}'
        : null,
    partnerLine: pair == null
        ? null
        : partnerLineFor(pair, is24Hour: MediaQuery.alwaysUse24HourFormatOf(context)),
  );
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
                  maxLines: 2,
                  loading: form.busy,
                  onPressed: form.canSend
                      ? () async {
                          if (await form.send() && ctx.mounted) Navigator.of(ctx).pop();
                        }
                      : null,
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
          icon: form.watchingFile ? BoothIcons.upload : BoothIcons.play,
          loading: form.busy,
          onPressed: form.canSend
              ? () async {
                  if (await form.send() && context.mounted) Navigator.of(context).maybePop();
                }
              : null,
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
  PlanAttach attach = PlanAttach.none;
  bool busy = false;
  String? problem;

  /// The file chosen for the night, and its size. Held (with its platform
  /// access) until it is handed to the uploader or another choice replaces it.
  LocalVideo? video;
  int? fileSize;

  bool get watchingLink => attach == PlanAttach.link;
  bool get watchingFile => attach == PlanAttach.file;

  /// Whether the chosen file can be sent under the planner's own limits, judged
  /// before sending so nobody finds out after the upload. (The server is the
  /// authority; this is the affordance, from the same numbers.)
  FileCheck get fileCheck => fileCheckFor(fileSize, hasFile: video != null);

  /// Sending needs a usable file when a file is the choice.
  bool get canSend => !watchingFile || fileCheck == FileCheck.ok;

  // The pasted link, judged only once typing pauses (a half-typed address is not
  // an error), and sooner when the field is emptied.
  LinkCheck linkCheck = LinkCheck.empty;
  Timer? _linkTimer;

  String get first => pair.partner.displayName.split(' ').first;

  NightPlacement get placement => placeNight(when.toUtc(), partnerZone: pair.partner.timezone);

  bool get lateForThem => placement.lateForThem;

  String get sendLabel {
    final base = lateForThem ? 'Send anyway' : 'Send to $first';
    return watchingFile ? '$base, start upload' : base;
  }

  /// The link in the one shape every room understands, or null.
  String? get canonicalLink {
    final id = youtubeVideoId(link.text.trim());
    return id == null ? null : canonicalYouTubeUrl(id);
  }

  void setWatching({required bool link}) {
    attach = link ? PlanAttach.link : PlanAttach.none;
    _releaseVideo();
    problem = null;
    notifyListeners();
  }

  /// Pick the file with the same chooser the lobby uses. Leaves the previous
  /// choice alone if the chooser is dismissed.
  Future<void> chooseFile(BuildContext context) async {
    final choice = await showLocalVideoChooser(context);
    final picked = choice?.video;
    if (picked == null) return;
    int size;
    try {
      size = picked.sizeBytes ?? await picked.uploadSource().length();
    } catch (e, s) {
      reportNonFatal(e, s, during: 'sizing a date night video');
      unawaited(picked.release());
      problem = "Hmm, we can't read that video. Pick it again to try once more.";
      notifyListeners();
      return;
    }
    _releaseVideo();
    video = picked;
    fileSize = size;
    attach = PlanAttach.file;
    problem = null;
    notifyListeners();
  }

  void _releaseVideo() {
    unawaited(video?.release());
    video = null;
    fileSize = null;
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

  Future<void> pickDay(BuildContext context) => _pick(context, PickerPart.date);

  Future<void> pickClock(BuildContext context) => _pick(context, PickerPart.time);

  /// The late-for-them warning's "Pick another time".
  Future<void> pickTime(BuildContext context) => _pick(context, PickerPart.time);

  Future<void> _pick(BuildContext context, PickerPart part) async {
    final picked = await pickNightTime(context, initial: when, part: part);
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
    if (watchingFile) return _sendWithFile();
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

  Future<bool> _sendWithFile() async {
    final chosen = video;
    if (chosen == null || fileCheck != FileCheck.ok) {
      problem = 'Choose a file first, or choose together.';
      notifyListeners();
      return false;
    }
    busy = true;
    problem = null;
    notifyListeners();
    try {
      // The upload starts now and carries on after this form has closed; what
      // comes back is the night, as soon as the slot was granted.
      await DateNightUploader.instance.start(video: chosen, title: title.text, startsAt: when);
      video = null; // the uploader holds it from here
      return true;
    } catch (e) {
      problem = e is MediaSharingException
          ? e.message
          : PairErrorCode.fromError(e) == PairErrorCode.unknown
          ? "Couldn't send that just now."
          : PairErrorCode.fromError(e).message;
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
    unawaited(video?.release());
    super.dispose();
  }
}

enum LinkCheck { empty, valid, invalid }

enum PlanAttach { none, link, file }

/// Where a chosen file stands against the planner's limits.
enum FileCheck { none, ok, overCap, overWeek }

/// A file of [size] bytes against the per-file cap and the weekly allowance.
/// Pure over the limits and profile it is handed, so it is testable.
FileCheck fileCheckFor(int? size, {required bool hasFile, TierLimits? limits, Profile? profile}) {
  if (!hasFile || size == null) return FileCheck.none;
  final l = limits ?? EntitlementService.instance.limitsOrFallback;
  if (size > l.mediaSharingMaxSizeBytes) return FileCheck.overCap;
  final p = profile ?? ProfileService.instance.profile;
  if (l.hasWeeklyQuota && p != null) {
    final remaining = p.remainingWeeklyBytes(l.mediaSharingWeeklyBytes);
    if (remaining >= 0 && size > remaining) return FileCheck.overWeek;
  }
  return FileCheck.ok;
}

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
          icon: BoothIcons.upload,
          title: 'A file from this device',
          caption: 'Uploads after you send. ${form.first} streams it.',
          selected: form.watchingFile,
          onTap: () => form.chooseFile(context),
        ),
        _AttachRow(
          icon: BoothIcons.film,
          title: "We'll choose together",
          caption: 'Pick something in Our Room on the night.',
          selected: form.attach == PlanAttach.none,
          onTap: () => form.setWatching(link: false),
        ),
        if (form.watchingLink) _LinkField(form: form),
        if (form.watchingFile && form.video != null) _FilePanel(form: form),
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

/// The chosen file: its name and size, the planner's allowance for it, and what
/// to do if it does not fit. All of it is judged before sending.
class _FilePanel extends StatelessWidget {
  const _FilePanel({required this.form});

  final PlanNightController form;

  @override
  Widget build(BuildContext context) {
    final video = form.video!;
    final size = form.fileSize ?? 0;
    final limits = EntitlementService.instance.limitsOrFallback;
    final profile = ProfileService.instance.profile;
    final check = form.fileCheck;
    final remaining = limits.hasWeeklyQuota && profile != null
        ? profile.remainingWeeklyBytes(limits.mediaSharingWeeklyBytes)
        : -1;
    final first = form.first;

    return Column(
      crossAxisAlignment: .stretch,
      spacing: 10,
      children: [
        PairPanel(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          child: Row(
            spacing: 12,
            children: [
              const Icon(BoothIcons.file, size: 18, color: PTColors.primary),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  spacing: 2,
                  children: [
                    Text(
                      video.name,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: PTText.body.copyWith(fontSize: 14, color: PTColors.fg),
                    ),
                    Text(
                      Profile.formatBytes(size),
                      style: PTText.mono.copyWith(fontSize: 11.5, color: PTColors.fgSoft),
                    ),
                  ],
                ),
              ),
              DialogTextButton(label: 'Change', onPressed: () => form.chooseFile(context)),
            ],
          ),
        ),
        if (limits.hasWeeklyQuota)
          _AllowanceCard(
            limit: limits.mediaSharingWeeklyBytes,
            remaining: remaining < 0 ? limits.mediaSharingWeeklyBytes : remaining,
            file: size,
            maxFile: limits.mediaSharingMaxSizeBytes,
          )
        else
          _UnlimitedCard(maxFile: limits.mediaSharingMaxSizeBytes),
        if (check == FileCheck.overCap) ...[
          Text(
            'That file is over the ${Profile.formatBytes(limits.mediaSharingMaxSizeBytes)} '
            'a free seat can share.',
            style: PTText.body.copyWith(color: PTColors.danger, fontSize: 14, height: 1.4),
          ),
          Row(
            spacing: 10,
            children: [
              Expanded(
                child: PTButton(
                  label: 'Pick a smaller file',
                  variant: .secondary,
                  height: 42,
                  maxLines: 2,
                  onPressed: () => form.chooseFile(context),
                ),
              ),
              if (canSellPremium)
                Expanded(
                  child: PTButton(
                    label: 'See Patron',
                    variant: .secondary,
                    icon: BoothIcons.crown,
                    height: 42,
                    onPressed: () => openPage(context, '/lobby/subscribe?source=date_night_file'),
                  ),
                ),
            ],
          ),
        ] else if (check == FileCheck.overWeek) ...[
          Text(
            'Only ${Profile.formatBytes(remaining)} is left this week and that file is '
            '${Profile.formatBytes(size)}.${_resets(profile)}',
            style: PTText.body.copyWith(color: PTColors.danger, fontSize: 14, height: 1.4),
          ),
          Row(
            spacing: 10,
            children: [
              Expanded(
                child: PTButton(
                  label: 'Pick a smaller file',
                  variant: .secondary,
                  height: 42,
                  maxLines: 2,
                  onPressed: () => form.chooseFile(context),
                ),
              ),
              Expanded(
                child: PTButton(
                  label: 'Send without a file',
                  variant: .secondary,
                  height: 42,
                  maxLines: 2,
                  onPressed: () => form.setWatching(link: false),
                ),
              ),
            ],
          ),
        ] else
          Text(
            'Uploads in the background right after you send. Keep SyncTogether open until '
            'it says Ready, and $first can already stream it on the night.',
            style: PTText.caption.copyWith(color: PTColors.fgMute, height: 1.45),
          ),
      ],
    );
  }

  /// " Your week resets Monday." when the window start is known.
  static String _resets(Profile? profile) {
    final start = profile?.r2UploadWindowStart;
    if (start == null) return '';
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final resets = start.add(const Duration(days: 7)).toLocal();
    return ' Your week resets ${days[resets.weekday - 1]}.';
  }
}

/// A free seat's weekly allowance as a bar: what is spent, and what this file
/// would take.
class _AllowanceCard extends StatelessWidget {
  const _AllowanceCard({
    required this.limit,
    required this.remaining,
    required this.file,
    required this.maxFile,
  });

  final int limit;
  final int remaining;
  final int file;
  final int maxFile;

  @override
  Widget build(BuildContext context) {
    final used = (limit - remaining).clamp(0, limit);
    final usedFraction = limit == 0 ? 0.0 : used / limit;
    final fileFraction = limit == 0 ? 0.0 : (file / limit).clamp(0.0, 1.0 - usedFraction);
    return PairPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 10,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  "This week's upload allowance",
                  style: PTText.body.copyWith(fontSize: 13, color: PTColors.fgDim),
                ),
              ),
              Text(
                '${Profile.formatBytes(remaining)} left',
                style: PTText.mono.copyWith(fontSize: 13, color: PTColors.fg),
              ),
            ],
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: LayoutBuilder(
                builder: (context, box) => Stack(
                  children: [
                    const Positioned.fill(child: ColoredBox(color: PTColors.aisle)),
                    Positioned(
                      left: 0,
                      width: box.maxWidth * usedFraction,
                      top: 0,
                      bottom: 0,
                      child: const ColoredBox(color: PTColors.railStrong),
                    ),
                    Positioned(
                      left: box.maxWidth * usedFraction,
                      width: box.maxWidth * fileFraction,
                      top: 0,
                      bottom: 0,
                      child: const ColoredBox(color: PTColors.primary),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Text(
            'Free seats share up to ${Profile.formatBytes(limit)} a week, one file up to '
            '${Profile.formatBytes(maxFile)}. It counts against the person who plans the night.',
            style: PTText.caption.copyWith(color: PTColors.fgMute, height: 1.45),
          ),
        ],
      ),
    );
  }
}

/// A Patron planner has no weekly bar to spend: said as the perk it is.
class _UnlimitedCard extends StatelessWidget {
  const _UnlimitedCard({required this.maxFile});

  final int maxFile;

  @override
  Widget build(BuildContext context) {
    return PairPanel(
      brass: true,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 6,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Upload allowance',
                  style: PTText.body.copyWith(fontSize: 13, color: PTColors.fgDim),
                ),
              ),
              Text(
                'UNLIMITED',
                style: PTText.mono.copyWith(fontSize: 12.5, color: PTColors.premium),
              ),
            ],
          ),
          Text(
            'Patron seats upload files up to ${Profile.formatBytes(maxFile)}, as many as you like.',
            style: PTText.caption.copyWith(color: PTColors.fgMute, height: 1.45),
          ),
        ],
      ),
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
  // Swapping a file for something else stops the upload that was feeding it.
  if (night.hasFile) await DateNightUploader.instance.cancel(night.id);
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
