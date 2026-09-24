import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

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
        Row(
          spacing: 10,
          // Top-aligned: a heading that wraps keeps its icon by the first line.
          crossAxisAlignment: .start,
          children: [
            const Icon(Symbols.flag_rounded, size: 22, color: PTColors.warningBorder),
            Expanded(
              child: Text(
                'Report a concern',
                textScaler: dialogHeadingScaler(context),
                style: PTText.screenTitle.copyWith(fontSize: 18),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'SyncTogether does not allow harassment, hate, or abusive behaviour. '
          'Tell us what happened and our team will review it.',
          style: PTText.body.copyWith(color: PTColors.white(0.8), height: 1.45),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: PTColors.white(0.05),
            border: Border.all(color: PTColors.white(0.08)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: .start,
            spacing: 4,
            children: [
              Text(
                'Reporting ${widget.targetName}',
                style: PTText.caption.copyWith(color: PTColors.textAccent),
              ),
              if (widget.roomCode != null)
                Text(
                  'Room ${widget.roomCode}',
                  style: PTText.finePrint.copyWith(color: PTColors.white(0.55)),
                ),
              if (snippet != null)
                Text(
                  '"${snippet.length > 140 ? '${snippet.substring(0, 140)}…' : snippet}"',
                  style: PTText.caption.copyWith(color: PTColors.white(0.7)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text('What went wrong?', style: PTText.body.copyWith(fontWeight: .w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final reason in ReportReason.values)
              _ReasonChip(
                label: reason.label,
                selected: _reason == reason,
                onTap: () => setState(() => _reason = reason),
              ),
          ],
        ),
        const SizedBox(height: 14),
        PTTextField(
          controller: _details,
          label: 'Anything else? (optional)',
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
              icon: Symbols.send_rounded,
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
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? PTColors.primary.withValues(alpha: 0.22) : PTColors.white(0.05),
          border: Border.all(
            color: selected ? PTColors.primary.withValues(alpha: 0.55) : PTColors.white(0.09),
          ),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text(
          label,
          style: PTText.body.copyWith(
            fontSize: 13,
            fontWeight: selected ? .w600 : .w500,
            color: selected ? Colors.white : PTColors.white(0.72),
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
                color: value ? PTColors.primary : PTColors.white(0.06),
                border: Border.all(color: value ? PTColors.primary : PTColors.white(0.18)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: value
                  ? const Icon(Symbols.check_rounded, size: 15, color: Colors.white)
                  : null,
            ),
            Expanded(
              child: Text(
                'Also block $name - you will stop seeing their messages and camera',
                style: PTText.body.copyWith(fontSize: 13, color: PTColors.white(0.8)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
