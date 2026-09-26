import 'package:flutter/material.dart';
import '../../ui/booth_icons.g.dart';

import '../../ui/buttons.dart';
import '../../ui/glass.dart';
import '../../ui/inputs.dart';
import '../../ui/pt_motion.dart';
import '../../ui/pt_theme.dart';
import '../moderation_service.dart';

/// What the user asked for when they closed the report dialog.
@immutable
class ReportOutcome {
  const ReportOutcome({required this.reason, this.details, this.block = false});

  final ReportReason reason;
  final String? details;

  /// Whether they also asked to stop seeing this person. Blocking is offered
  /// inside the report rather than as a separate hunt through a menu, because
  /// the moment somebody wants one they usually want both.
  final bool block;
}

Future<ReportOutcome?> showReportDialog(
  BuildContext context, {
  required String targetName,
  String? roomCode,
  String? messageSnippet,
  bool alreadyBlocked = false,
}) {
  return showGlassDialog<ReportOutcome>(
    context: context,
    width: 460,
    sheetOnCompact: true,
    builder: (_) => _ReportDialog(
      targetName: targetName,
      roomCode: roomCode,
      messageSnippet: messageSnippet,
      alreadyBlocked: alreadyBlocked,
    ),
  );
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({
    required this.targetName,
    this.roomCode,
    this.messageSnippet,
    this.alreadyBlocked = false,
  });

  final String targetName;
  final String? roomCode;
  final String? messageSnippet;
  final bool alreadyBlocked;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final _details = TextEditingController();
  ReportReason? _reason;
  late bool _block = !widget.alreadyBlocked;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snippet = widget.messageSnippet;
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: [
        GlassDialogHeader(
          eyebrow: 'Front of house',
          title: 'Report a concern',
          onClose: () => Navigator.of(context).pop(),
        ),
        const SizedBox(height: 14),
        // What is being reported, on an Aisle well. The house rules live in
        // the footer's contact line and the published terms (Guideline 1.2).
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: PTColors.aisle,
            borderRadius: BorderRadius.circular(PTRadius.control),
          ),
          child: Column(
            crossAxisAlignment: .start,
            spacing: 4,
            children: [
              Row(
                spacing: 10,
                crossAxisAlignment: .baseline,
                textBaseline: .alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      snippet != null
                          ? "${widget.targetName}'s message"
                          : 'Reporting ${widget.targetName}',
                      maxLines: 2,
                      overflow: .ellipsis,
                      style: PTText.body.copyWith(
                        fontSize: 14,
                        fontWeight: .w600,
                        color: PTColors.fg,
                      ),
                    ),
                  ),
                  if (widget.roomCode != null)
                    Text('Room ${widget.roomCode}'.toUpperCase(), style: PTText.label),
                ],
              ),
              if (snippet != null)
                Text(
                  '"${snippet.length > 140 ? '${snippet.substring(0, 140)}…' : snippet}"',
                  maxLines: 3,
                  overflow: .ellipsis,
                  style: PTText.caption.copyWith(color: PTColors.white(0.7)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('What went wrong?'.toUpperCase(), style: PTText.label),
        const SizedBox(height: 8),
        // Two equal columns. Every category stays, copyright included -
        // media sharing redistributes a host's file, so owners need a route.
        Column(
          spacing: 8,
          children: [
            for (var i = 0; i < ReportReason.values.length; i += 2)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: .stretch,
                  spacing: 8,
                  children: [
                    for (final reason in ReportReason.values.skip(i).take(2))
                      Expanded(
                        child: _ReasonChip(
                          label: _shortLabel(reason),
                          selected: _reason == reason,
                          onTap: () => setState(() => _reason = reason),
                        ),
                      ),
                    if (i + 1 >= ReportReason.values.length) const Expanded(child: SizedBox()),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        PTTextField(
          controller: _details,
          label: 'What happened? (optional)',
          hint: 'What happened, and when',
          maxLength: 2000,
        ),
        const SizedBox(height: 6),
        if (!widget.alreadyBlocked)
          _BlockCheck(
            name: widget.targetName,
            value: _block,
            onChanged: (v) => setState(() => _block = v),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'You have already blocked ${widget.targetName}.',
              style: PTText.finePrint.copyWith(color: PTColors.white(0.55)),
            ),
          ),
        const SizedBox(height: 10),
        Text(
          'Reports are reviewed by our team. You can also email support@synctogether.app.',
          style: PTText.finePrint.copyWith(color: PTColors.white(0.5)),
        ),
        const SizedBox(height: 16),
        PTButtonBar(
          buttons: [
            PTButton(
              maxLines: 2,
              label: 'Cancel',
              variant: .secondary,
              onPressed: () => Navigator.of(context).pop(),
            ),
            PTButton(
              maxLines: 2,
              label: 'Send report',
              icon: BoothIcons.send,
              // A report with no category is not triageable, so the button
              // waits rather than filing something nobody can act on.
              onPressed: _reason == null
                  ? null
                  : () => Navigator.of(context).pop(
                      ReportOutcome(
                        reason: _reason!,
                        details: _details.text.trim().isEmpty ? null : _details.text.trim(),
                        block: _block && !widget.alreadyBlocked,
                      ),
                    ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Grid-sized category names. The wire value and full label are unchanged.
String _shortLabel(ReportReason reason) => switch (reason) {
  .harassment => 'Harassment',
  .sexualContent => 'Sexual content',
  .copyright => 'Copyright',
  _ => reason.label,
};

class _ReasonChip extends StatelessWidget {
  const _ReasonChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PTPressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: PTMotion.hover,
        curve: PTMotion.enter,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        alignment: AlignmentDirectional.centerStart,
        // Square segments: pills are for people.
        decoration: BoxDecoration(
          color: selected ? PTColors.aisle : Colors.transparent,
          border: Border.all(color: selected ? PTColors.primary : PTColors.rail),
          borderRadius: BorderRadius.circular(PTRadius.control),
        ),
        child: Text(
          label,
          style: PTText.body.copyWith(
            fontSize: 13,
            fontWeight: selected ? .w600 : .w500,
            color: selected ? PTColors.primary : PTColors.white(0.75),
          ),
        ),
      ),
    );
  }
}

class _BlockCheck extends StatelessWidget {
  const _BlockCheck({required this.name, required this.value, required this.onChanged});

  final String name;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return PTPressable(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          spacing: 10,
          children: [
            AnimatedContainer(
              duration: PTMotion.hover,
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: value ? PTColors.primary : Colors.transparent,
                border: Border.all(color: value ? PTColors.primary : PTColors.rail),
                borderRadius: BorderRadius.circular(PTRadius.control),
              ),
              child: value
                  ? const Icon(BoothIcons.check, size: 15, color: PTColors.onAccent)
                  : null,
            ),
            Expanded(
              child: Text(
                'Also block $name: their messages and camera disappear for you',
                style: PTText.body.copyWith(fontSize: 13, color: PTColors.white(0.8)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
