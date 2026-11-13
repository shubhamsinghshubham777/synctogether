import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../nav.dart';
import '../../platform.dart';
import '../../ui/booth_icons.g.dart';
import '../../ui/pt_theme.dart';
import '../../ui/inputs.dart';
import '../../ui/reveal.dart';
import '../shake_to_report.dart';
import 'open_report.dart';
import '../contract.dart';
import '../feedback_services.dart';
import 'discovery_logic.dart';
import 'discovery_triggers.dart';

/// Profile > Help: Report a bug, Your reports, Rate. Always findable, and the
/// subtitle says how to reach the bug button without Profile.
class FeedbackHelpRows extends StatelessWidget {
  const FeedbackHelpRows({super.key});

  String get _how {
    if (isDesktop) {
      return defaultTargetPlatform == TargetPlatform.macOS
          ? 'Press ⌘⇧B any time'
          : 'Press Ctrl+Shift+B any time';
    }
    return 'Or tap the bug at the top of any screen';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Row(
          icon: BoothIcons.bug,
          lit: true,
          title: 'Report a bug',
          subtitle: _how,
          onTap: () => openReportFrom(context, 'profile'),
        ),
        // Phones only, and only once the device has said it can shake.
        ValueListenableBuilder<bool>(
          valueListenable: ShakeToReport.instance.available,
          builder: (context, available, _) => PTReveal(
            visible: available,
            child: ValueListenableBuilder<bool>(
              valueListenable: ShakeToReport.instance.enabled,
              builder: (context, on, _) => _Row(
                icon: BoothIcons.shake,
                title: 'Shake to report',
                subtitle: 'Shake your phone to open a bug report',
                onTap: () => ShakeToReport.instance.setEnabled(!on),
                trailing: PTSwitch(value: on, onChanged: ShakeToReport.instance.setEnabled),
              ),
            ),
          ),
        ),
        StreamBuilder<List<BugReportRow>>(
          stream: FeedbackServices.instance.watchMine(),
          builder: (context, snap) => _Row(
            title: 'Your reports',
            subtitle: reportsSummary(snap.data ?? const []),
            onTap: () => openPage(context, '/lobby/profile/reports'),
          ),
        ),
        // The rating sheet is the platform's own; until it is wired the row
        // stays out rather than point nowhere.
        if (DiscoveryTriggers.onRate != null)
          _Row(
            title: 'Rate SyncTogether',
            subtitle: 'Something not right? Tell us first: we answer fast.',
            onTap: DiscoveryTriggers.onRate!,
            ruled: true,
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    this.icon,
    this.lit = false,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.ruled = false,
    this.trailing,
  });

  final IconData? icon;
  final bool lit;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool ruled;

  /// Replaces the chevron (a switch row).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title, $subtitle',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PTRadius.control),
        child: Container(
          constraints: const BoxConstraints(minHeight: 54),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: lit ? PTColors.primary.withValues(alpha: 0.08) : null,
            borderRadius: BorderRadius.circular(PTRadius.control),
            border: ruled ? const Border(top: BorderSide(color: PTColors.aisle)) : null,
          ),
          child: Row(
            spacing: 12,
            children: [
              if (icon != null)
                Icon(icon, size: 20, color: lit ? PTColors.primary : PTColors.fgDim),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  children: [
                    Text(
                      title,
                      style: PTText.body.copyWith(fontWeight: .w500, color: PTColors.fg),
                    ),
                    Text(subtitle, style: PTText.finePrint.copyWith(color: PTColors.fgMute)),
                  ],
                ),
              ),
              trailing ?? const Icon(BoothIcons.chevronRight, size: 16, color: PTColors.fgMute),
            ],
          ),
        ),
      ),
    );
  }
}
