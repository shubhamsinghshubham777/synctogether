import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../diagnostics.dart';
import '../../ui/booth.dart';
import '../../ui/booth_icons.g.dart';
import '../../ui/buttons.dart';
import '../../ui/glass.dart';
import '../../ui/inputs.dart';
import '../../ui/loader.dart';
import '../../ui/pt_motion.dart';
import '../../ui/pt_theme.dart';
import '../../ui/reveal.dart';
import '../../ui/rolling_text.dart';
import '../contract.dart';
import '../feedback_analytics.dart';

enum _Phase { form, sending, sent, queued }

/// The body of the bug report sheet / dialog (boards 82 and 83): what was
/// captured, an optional note and category, what exactly gets sent, and the
/// reassurance once it has gone.
///
/// Takes its [service] and [capture] so a test drives it with no network.
class BugReportForm extends StatefulWidget {
  const BugReportForm({super.key, required this.service, required this.capture, this.initialNote});

  final FeedbackService service;
  final BugCapture capture;

  /// Prefills the note (a follow-up to an earlier report names it).
  final String? initialNote;

  @override
  State<BugReportForm> createState() => _BugReportFormState();
}

class _BugReportFormState extends State<BugReportForm> {
  late final _note = TextEditingController(text: widget.initialNote)
    ..selection = TextSelection.collapsed(offset: widget.initialNote?.length ?? 0);
  final _more = TextEditingController();
  late BugCapture _capture = widget.capture;
  late final bool _hasShot = widget.capture.screenshotPng != null;
  late bool _includeShot = _hasShot;

  /// The video's file name travels only when the user switches it on, every
  /// time: a fresh sheet always starts with it off.
  bool _includeFileName = false;
  Future<void>? _gatherFuture;
  bool _gathered = false;
  bool _showSent = false;
  BugCategory? _category;
  _Phase _phase = .form;
  String? _code;
  String? _error;

  /// What the success screen's two controls talk to the service about: the code
  /// a [Sent] carried, or the local id a [Queued] carried.
  String? _ref;
  bool _notify = true;
  bool _moreOpen = false;
  bool _moreSaving = false;
  bool _moreAdded = false;
  String? _doneError;

  @override
  void initState() {
    super.initState();
    _gatherFuture = _gather();
  }

  @override
  void dispose() {
    _note.dispose();
    _more.dispose();
    super.dispose();
  }

  Future<void> _gather() async {
    try {
      final c = await widget.service.gather(widget.capture);
      if (!mounted) return;
      setState(() {
        _capture = c;
        _gathered = true;
      });
    } catch (e, s) {
      reportNonFatal(e, s, during: 'bug report gather');
      if (mounted) setState(() => _gathered = true);
    }
  }

  Future<void> _send() async {
    if (_phase == .sending) return;
    setState(() {
      _phase = .sending;
      _error = null;
    });
    try {
      // Send is live from the first frame; if the slower data is still on its
      // way, give it a moment rather than file a thinner report.
      await _gatherFuture?.timeout(const Duration(seconds: 3), onTimeout: () {});
      final note = _note.text.trim();
      final result = await widget.service.submit(
        _capture.copyWith(includeFileName: _includeFileName && _capture.fileName != null),
        category: _category,
        note: note.isEmpty ? null : note,
        includeScreenshot: _includeShot && _hasShot,
      );
      if (!mounted) return;
      trace(
        'bug report submitted',
        category: 'feedback',
        data: {
          'result': result.runtimeType.toString(),
          'category': _category?.name,
          'note': note.isNotEmpty,
          'screenshot': _includeShot && _hasShot,
        },
      );
      if (result is Sent || result is Queued) {
        FeedbackAnalytics.sent(
          category: _category?.name ?? 'none',
          screenshot: _includeShot && _hasShot,
          queued: result is Queued,
        );
      }
      switch (result) {
        case Sent(:final code):
          setState(() {
            _code = code;
            _ref = code;
            _phase = .sent;
          });
        case Queued(:final localId):
          setState(() {
            _ref = localId;
            _phase = .queued;
          });
        case RateLimited(:final retryIn):
          setState(() {
            _phase = .form;
            _error =
                'Easy there, you just sent one. Give it ${retryIn.inSeconds.clamp(1, 600)} '
                'seconds and try again.';
          });
      }
    } catch (e, s) {
      reportNonFatal(e, s, during: 'bug report submit');
      if (!mounted) return;
      setState(() {
        _phase = .form;
        _error = "Hmm, that didn't go through. Give it another try in a moment.";
      });
    }
  }

  Future<void> _setNotify(bool on) async {
    final ref = _ref;
    if (ref == null) return;
    setState(() {
      _notify = on;
      _doneError = null;
    });
    try {
      await widget.service.setNotifyWhenFixed(ref, on);
      trace('bug report notify toggled', category: 'feedback', data: {'on': on});
    } catch (e, s) {
      reportNonFatal(e, s, during: 'bug report notify choice');
      if (!mounted) return;
      setState(() {
        _notify = !on;
        _doneError = "Hmm, that didn't save. Give it another try in a moment.";
      });
    }
  }

  Future<void> _addMore() async {
    final ref = _ref;
    final text = _more.text.trim();
    if (ref == null || text.isEmpty || _moreSaving) return;
    setState(() {
      _moreSaving = true;
      _doneError = null;
    });
    try {
      await widget.service.appendNote(ref, text);
      trace('bug report details added', category: 'feedback', data: {'chars': text.length});
      if (!mounted) return;
      setState(() {
        _moreSaving = false;
        _moreAdded = true;
        _moreOpen = false;
      });
    } catch (e, s) {
      reportNonFatal(e, s, during: 'bug report add details');
      if (!mounted) return;
      setState(() {
        _moreSaving = false;
        _doneError = "Hmm, that didn't go through. Give it another try in a moment.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = _phase == .sent || _phase == .queued;
    // PTShift lays its children out unbounded while they slide, so each is
    // pinned to the width the dialog gave us.
    return LayoutBuilder(
      builder: (context, box) => PTShift(
        keyValue: done ? 'done' : 'form',
        dir: 1,
        axis: .horizontal,
        distance: 0.12,
        align: Alignment.topCenter,
        child: SizedBox(
          width: box.maxWidth,
          child: done ? _buildDone(context) : _buildForm(context),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final sending = _phase == .sending;
    final wide = MediaQuery.sizeOf(context).width >= kGlassSheetBreakpoint;
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: [
        GlassDialogHeader(
          eyebrow: 'Bug report',
          title: wide ? 'Something off? Tell us.' : "Something off?\nTell us. We're on it.",
          onClose: sending ? null : () => Navigator.of(context).pop(),
        ),
        const SizedBox(height: 14),
        _Attachments(
          capture: _capture,
          includeShot: _includeShot && _hasShot,
          hasShot: _hasShot,
          gathered: _gathered,
          wide: wide,
        ),
        const SizedBox(height: 14),
        _NoteField(controller: _note, enabled: !sending),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in BugCategory.values)
              _CategoryChip(
                label: _label(c),
                selected: _category == c,
                onTap: sending ? null : () => setState(() => _category = _category == c ? null : c),
              ),
          ],
        ),
        PTReveal(
          visible: _error != null,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _error ?? '',
              style: PTText.finePrint.copyWith(fontSize: 12.5, color: PTColors.danger),
            ),
          ),
        ),
        const SizedBox(height: 16),
        PTButton(
          label: 'Send report',
          icon: BoothIcons.send,
          loading: sending,
          onPressed: sending ? null : _send,
        ),
        const SizedBox(height: 12),
        Text(
          'No chat messages, file paths or passwords.',
          textAlign: .center,
          style: PTText.finePrint.copyWith(color: PTColors.fgMute),
        ),
        const SizedBox(height: 4),
        _DisclosureLink(open: _showSent, onTap: () => setState(() => _showSent = !_showSent)),
        PTReveal(
          visible: _showSent,
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _WhatWeSend(
              capture: _capture,
              gathered: _gathered,
              hasShot: _hasShot,
              includeShot: _includeShot,
              onIncludeShot: (v) => setState(() => _includeShot = v),
              includeFileName: _includeFileName,
              onIncludeFileName: (v) => setState(() => _includeFileName = v),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDone(BuildContext context) {
    final sent = _phase == .sent;
    final note = _note.text.trim();
    return PTColumn(
      mainAxisSize: .min,
      spacing: 16,
      children: [
        const SizedBox(height: 8),
        Center(
          child: PTStamp(
            color: sent ? PTColors.online : PTColors.warning,
            size: 96,
            child: Column(
              mainAxisSize: .min,
              spacing: 2,
              children: [
                Icon(sent ? BoothIcons.checkBold : BoothIcons.bug, size: 28),
                Text(
                  sent ? 'RECEIVED' : 'SAVED',
                  style: PTText.label.copyWith(
                    fontSize: 10,
                    letterSpacing: 1.4,
                    color: sent ? PTColors.online : PTColors.warning,
                  ),
                ),
              ],
            ),
          ),
        ),
        Text(
          sent ? "Thanks. We've got it." : 'Saved on this device.',
          textAlign: .center,
          style: PTText.screenTitle.copyWith(fontSize: 28),
        ),
        Text(
          sent
              ? "A real person reads every report. We'll look at this one first thing, and "
                    "tell you the moment it's fixed."
              : "No signal right now. It sends itself the moment you're back online, so "
                    'there is nothing for you to do.',
          textAlign: .center,
          style: PTText.body.copyWith(height: 1.5, color: PTColors.fgDim),
        ),
        if (sent && _code != null)
          PTTicket(
            paper: true,
            stubWidth: 112,
            semanticLabel: 'Report ${_code!}',
            body: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Column(
                mainAxisAlignment: .center,
                crossAxisAlignment: .start,
                spacing: 4,
                children: [
                  Text(
                    'REPORT · ${_stamp(DateTime.now())}',
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: PTText.label.copyWith(fontSize: 10, color: PTColors.liveInk),
                  ),
                  Text(
                    note.isNotEmpty
                        ? note
                        : (_category != null ? _label(_category!) : 'Bug report'),
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: PTText.cardHeading.copyWith(fontSize: 16, color: PTColors.canvas),
                  ),
                ],
              ),
            ),
            stub: Center(
              child: Text(
                _code!,
                style: PTText.mono.copyWith(
                  fontSize: 13,
                  fontWeight: .w600,
                  letterSpacing: 1,
                  color: PTColors.canvas,
                ),
              ),
            ),
          ),
        PTToggleRow(
          title: "Tell me when it's fixed",
          subtitle: 'One quiet notification, and it shows in Your reports.',
          value: _notify,
          onChanged: _setNotify,
        ),
        PTRevealKeep(
          visible: _moreOpen,
          child: Column(
            crossAxisAlignment: .stretch,
            spacing: 10,
            children: [
              _NoteField(
                controller: _more,
                enabled: !_moreSaving,
                hint: 'Anything else that would help us?',
              ),
              PTButton(
                label: 'Add to my report',
                variant: .secondary,
                loading: _moreSaving,
                onPressed: _moreSaving ? null : _addMore,
              ),
            ],
          ),
        ),
        PTRevealKeep(
          visible: _doneError != null,
          child: Text(
            _doneError ?? '',
            textAlign: .center,
            style: PTText.finePrint.copyWith(fontSize: 12.5, color: PTColors.danger),
          ),
        ),
        PTButton(
          label: sent ? 'Back to the show' : 'Got it',
          onPressed: () => Navigator.of(context).pop(),
        ),
        PTRevealKeep(
          visible: _moreAdded,
          child: Text(
            'Added to your report. Thank you.',
            textAlign: .center,
            style: PTText.finePrint.copyWith(fontSize: 13, color: PTColors.fgDim),
          ),
        ),
        PTRevealKeep(
          visible: !_moreOpen && !_moreAdded,
          child: _TextLink(
            label: 'Add more details',
            onTap: () => setState(() => _moreOpen = true),
          ),
        ),
      ],
    );
  }
}

String _label(BugCategory c) => switch (c) {
  .video => 'Video',
  .sound => 'Sound',
  .sync => 'Sync',
  .chat => 'Chat',
  .camera => 'Camera',
  .other => 'Something else',
};

String _stamp(DateTime t) {
  const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
  String two(int n) => n.toString().padLeft(2, '0');
  return '${days[t.weekday - 1]} ${two(t.hour)}:${two(t.minute)}';
}

/// The screenshot thumbnail and the four things being attached, each ticking
/// in as it is gathered.
class _Attachments extends StatelessWidget {
  const _Attachments({
    required this.capture,
    required this.includeShot,
    required this.hasShot,
    required this.gathered,
    required this.wide,
  });

  final BugCapture capture;
  final bool includeShot;
  final bool hasShot;
  final bool gathered;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final size = wide ? const Size(150, 94) : const Size(92, 150);
    return Row(
      crossAxisAlignment: .center,
      spacing: 14,
      children: [
        _Thumb(png: includeShot ? capture.screenshotPng : null, size: size, hasShot: hasShot),
        Expanded(
          child: Column(
            crossAxisAlignment: .start,
            children: [
              _AttachRow(
                label: 'Screenshot',
                state: !hasShot
                    ? _Attach.skipped
                    : includeShot
                    ? _Attach.done
                    : _Attach.skipped,
              ),
              _AttachRow(label: 'Recent activity', state: gathered ? .done : .pending),
              _AttachRow(
                label: wide ? 'Room, sync, app, device' : 'Room and sync',
                state: gathered ? .done : .pending,
              ),
              if (!wide) _AttachRow(label: 'App and device', state: gathered ? .done : .pending),
            ],
          ),
        ),
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.png, required this.size, required this.hasShot});

  final Uint8List? png;
  final Size size;
  final bool hasShot;

  @override
  Widget build(BuildContext context) {
    // The picture is clipped to the radius *inside* the hairline. Clipping the
    // Container to the outer radius lets the square corners of the image
    // overpaint the rounded border, which then reads as square.
    return Container(
      width: size.width,
      height: size.height,
      decoration: BoxDecoration(
        color: PTColors.ink,
        border: Border.all(color: PTColors.rail),
        borderRadius: BorderRadius.circular(PTRadius.control),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(PTRadius.control - 1),
        child: Stack(
          fit: .expand,
          children: [
            if (png != null)
              Image.memory(
                png!,
                fit: .cover,
                alignment: Alignment.topCenter,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                color: PTColors.canvasScrim,
                child: Text(
                  png != null
                      ? 'THIS SCREEN'
                      : hasShot
                      ? 'LEFT OUT'
                      : 'NO PICTURE',
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: PTText.label.copyWith(
                    fontSize: 9,
                    letterSpacing: 1,
                    color: PTColors.fgDim,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _Attach { pending, done, skipped }

class _AttachRow extends StatelessWidget {
  const _AttachRow({required this.label, required this.state});

  final String label;
  final _Attach state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        spacing: 10,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: AnimatedSwitcher(
              duration: PTMotion.functional(context, PTMotion.state),
              child: switch (state) {
                _Attach.pending => const Center(key: ValueKey('p'), child: PTLoader(size: 12)),
                _Attach.done => const Icon(
                  BoothIcons.check,
                  key: ValueKey('d'),
                  size: 16,
                  color: PTColors.online,
                ),
                _Attach.skipped => const Icon(
                  BoothIcons.close,
                  key: ValueKey('s'),
                  size: 14,
                  color: PTColors.fgMute,
                ),
              },
            ),
          ),
          Expanded(
            child: Text(
              label,
              style: PTText.body.copyWith(
                fontSize: 13.5,
                fontWeight: .w500,
                color: state == _Attach.skipped ? PTColors.fgMute : PTColors.fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A multi-line note. PTTextField is single-line, and a report note wants room.
class _NoteField extends StatelessWidget {
  const _NoteField({
    required this.controller,
    required this.enabled,
    this.hint = 'What went wrong? (optional)',
  });

  final TextEditingController controller;
  final bool enabled;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PTColors.canvas,
        border: Border.all(color: PTColors.rail),
        borderRadius: BorderRadius.circular(PTRadius.control),
      ),
      child: TextField(
        controller: controller,
        enabled: enabled,
        minLines: 3,
        maxLines: 5,
        maxLength: 2000,
        keyboardType: TextInputType.multiline,
        textCapitalization: TextCapitalization.sentences,
        style: PTText.body.copyWith(fontSize: 15, height: 1.4, color: PTColors.fg),
        cursorColor: PTColors.textAccent,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: PTText.body.copyWith(fontSize: 15, color: PTColors.fgMute),
          border: InputBorder.none,
          counterText: '',
          isDense: true,
          contentPadding: const EdgeInsets.all(12),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: PTPressable(
        onTap: onTap ?? () {},
        child: AnimatedContainer(
          duration: PTMotion.hover,
          curve: PTMotion.enter,
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected
                ? PTColors.accentBorderSoft.withValues(alpha: 0.14)
                : Colors.transparent,
            border: Border.all(color: selected ? PTColors.primary : PTColors.rail),
            borderRadius: BorderRadius.circular(PTRadius.control),
          ),
          // A min-width Row inside the fixed height: centred, but it hugs the
          // label, so the chips wrap side by side instead of stretching.
          child: Row(
            mainAxisSize: .min,
            children: [
              Text(
                label,
                style: PTText.body.copyWith(
                  fontSize: 13,
                  fontWeight: .w500,
                  color: selected ? PTColors.accentBright : PTColors.fgDim,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Underlined text link, centred, with the press feel every control has.
class _TextLink extends StatelessWidget {
  const _TextLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        button: true,
        child: PTPressable(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            child: Text(
              label,
              style: PTText.body.copyWith(
                fontSize: 14,
                fontWeight: .w600,
                color: PTColors.fg,
                decoration: TextDecoration.underline,
                decorationColor: PTColors.fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DisclosureLink extends StatelessWidget {
  const _DisclosureLink({required this.open, required this.onTap});

  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        button: true,
        child: PTPressable(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            child: Text(
              open ? 'Hide what we send' : 'See exactly what we send',
              style: PTText.finePrint.copyWith(
                color: PTColors.fgDim,
                decoration: TextDecoration.underline,
                decorationColor: PTColors.fgDim,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "See exactly what we send": the labelled lines the service gathered, in
/// plain mono, plus the screenshot's off switch. No JSON.
class _WhatWeSend extends StatelessWidget {
  const _WhatWeSend({
    required this.capture,
    required this.gathered,
    required this.hasShot,
    required this.includeShot,
    required this.onIncludeShot,
    required this.includeFileName,
    required this.onIncludeFileName,
  });

  final BugCapture capture;
  final bool gathered;
  final bool hasShot;
  final bool includeShot;
  final ValueChanged<bool> onIncludeShot;
  final bool includeFileName;
  final ValueChanged<bool> onIncludeFileName;

  @override
  Widget build(BuildContext context) {
    final lines = capture.summary.entries.toList();
    final fileName = capture.fileName;
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 12,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: PTColors.canvas,
            border: Border.all(color: PTColors.aisle),
            borderRadius: BorderRadius.circular(PTRadius.control),
          ),
          child: lines.isEmpty
              ? Text(
                  gathered ? 'Nothing extra to add.' : 'Still gathering…',
                  style: PTText.mono.copyWith(fontSize: 11, color: PTColors.fgMute),
                )
              : Column(
                  crossAxisAlignment: .start,
                  spacing: 3,
                  children: [
                    for (final e in lines)
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${e.key} ',
                              style: const TextStyle(color: PTColors.fgMute),
                            ),
                            TextSpan(text: e.value),
                          ],
                        ),
                        style: PTText.mono.copyWith(
                          fontSize: 11,
                          height: 1.5,
                          color: PTColors.fgDim,
                        ),
                      ),
                  ],
                ),
        ),
        if (hasShot)
          PTToggleRow(
            title: 'Include the screenshot',
            subtitle: 'Taken just now, of this window only.',
            value: includeShot,
            onChanged: onIncludeShot,
          ),
        if (fileName != null) ...[
          PTToggleRow(
            title: "Include the video's file name",
            subtitle: 'Off unless you switch it on. It helps us spot odd names.',
            value: includeFileName,
            onChanged: onIncludeFileName,
          ),
          PTReveal(
            visible: includeFileName,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: PTColors.canvas,
                border: Border.all(color: PTColors.aisle),
                borderRadius: BorderRadius.circular(PTRadius.control),
              ),
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(
                      text: 'file ',
                      style: TextStyle(color: PTColors.fgMute),
                    ),
                    TextSpan(text: fileName),
                  ],
                ),
                style: PTText.mono.copyWith(fontSize: 11, height: 1.5, color: PTColors.fgDim),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
