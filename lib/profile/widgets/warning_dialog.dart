import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:synctogether/profile/profile_service.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/pt_theme.dart';

Future<void> showWarningDialog(BuildContext context) {
  return showGlassDialog<void>(
    context: context,
    width: 480,
    barrierDismissible: false,
    builder: (_) => const _WarningDialog(),
  );
}

class _WarningDialog extends StatefulWidget {
  const _WarningDialog();

  @override
  State<_WarningDialog> createState() => _WarningDialogState();
}

class _WarningDialogState extends State<_WarningDialog> {
  bool _loading = false;

  Future<void> _acknowledge() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await ProfileService.instance.acknowledgeWarning();
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ProfileService.instance.profile;
    final reason =
        profile?.warningReason ??
        'A room or media content associated with your account violated SyncTogether copyright or community guidelines.';

    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassDialogHeader(
          eyebrow: 'Account Notice',
          title: 'Moderation Warning',
          onClose: () {}, // Blocking: must acknowledge
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: PTColors.warning.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(PTRadius.control),
            border: Border.all(color: PTColors.warningBorder.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Symbols.warning_rounded, color: PTColors.warning, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'STRIKE 1 OF 2 ISSUED',
                      style: PTText.label.copyWith(
                        color: PTColors.warning,
                        fontSize: 11,
                        fontWeight: .bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'A formal strike has been recorded against your account.',
                      style: PTText.caption.copyWith(color: PTColors.fg),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: PTColors.aisle,
            borderRadius: BorderRadius.circular(PTRadius.control),
            border: Border.all(color: PTColors.rail),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'INFRACTION DETAILS',
                style: PTText.label.copyWith(fontSize: 10, color: PTColors.fgMute),
              ),
              const SizedBox(height: 6),
              Text(reason, style: PTText.body.copyWith(fontSize: 13, color: PTColors.fg)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'SyncTogether takes intellectual property and user safety seriously. Sharing pirated media, unauthorized commercial broadcasts, or violating our terms is strictly prohibited. A second strike will result in permanent account termination.',
          style: PTText.finePrint.copyWith(color: PTColors.fgMute),
        ),
        const SizedBox(height: 20),
        PTButtonBar(
          buttons: [
            PTButton(
              label: _loading ? 'Saving...' : 'I Understand & Agree',
              icon: _loading ? null : Symbols.check_circle_rounded,
              variant: .primary,
              onPressed: _loading ? null : _acknowledge,
            ),
          ],
        ),
      ],
    );
  }
}
