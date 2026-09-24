import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'analytics_catalog.dart';
import 'ui/buttons.dart';
import 'ui/glass.dart';
import 'ui/pt_theme.dart';
import 'ui/scroll_fade.dart';

/// The complete list of what leaves the device, shown on request.
///
/// It exists to make the usage-data toggle a decision rather than a leap of
/// faith. Everything in it is generated from [kAnalyticsEvents], which a test
/// keeps in step with the actual `Analytics.track` calls - so this cannot drift
/// into telling somebody a comfortable half-truth.
Future<void> showAnalyticsDisclosure(BuildContext context) {
  return showGlassDialog(
    context: context,
    width: 560,
    scrollable: false,
    padding: const EdgeInsets.fromLTRB(28, 26, 20, 22),
    builder: (context) => const _Disclosure(),
  );
}

class _Disclosure extends StatelessWidget {
  const _Disclosure();

  @override
  Widget build(BuildContext context) {
    final grouped = analyticsEventsByGroup();
    // A short window cannot spare a pinned header and footer around the
    // list, so below this the whole body scrolls as one.
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < MediaQuery.textScalerOf(context).scale(420);
        Widget list(Widget child) =>
            compact ? child : Flexible(child: ScrollFadeEdge(child: child));
        final body = Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: .start,
                      spacing: 4,
                      children: [
                        Text('What we collect', style: PTText.screenTitle.copyWith(fontSize: 20)),
                        Text(
                          'All of it. This is the complete list - there is no second one.',
                          style: PTText.caption,
                        ),
                      ],
                    ),
                  ),
                  PTIconButton(
                    icon: Symbols.close_rounded,
                    iconSize: 18,
                    size: 36,
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            list(
              compact
                  ? Padding(
                      padding: const EdgeInsets.only(right: 16, bottom: 4),
                      child: _list(grouped),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.only(right: 16, bottom: 4),
                      child: _list(grouped),
                    ),
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: PTButton(label: 'Got it', onPressed: () => Navigator.of(context).pop()),
            ),
          ],
        );
        return compact ? SingleChildScrollView(child: body) : body;
      },
    );
  }

  Widget _list(Map<AnalyticsGroup, List<AnalyticsEventDoc>> grouped) {
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        _NeverPanel(),
        const SizedBox(height: 20),
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              entry.key.title,
              style: PTText.finePrint.copyWith(
                fontSize: 11,
                letterSpacing: 0.8,
                fontWeight: .w700,
                color: PTColors.textAccent,
              ),
            ),
          ),
          for (final doc in entry.value)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _EventRow(doc: doc),
            ),
          const SizedBox(height: 10),
        ],
        Text(
          'Events are tied to your account ID and, before you sign in, to a '
          'random ID generated on this device. Deleting your account deletes '
          'all of it.',
          style: PTText.finePrint.copyWith(fontSize: 11.5),
        ),
      ],
    );
  }
}

class _NeverPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: 16,
      opacity: 0.4,
      blur: 16,
      shadow: false,
      borderColor: PTColors.online.withValues(alpha: 0.28),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: .start,
        spacing: 9,
        children: [
          Row(
            spacing: 8,
            children: [
              const Icon(Symbols.shield_rounded, size: 17, fill: 1, color: PTColors.online),
              Expanded(
                child: Text(
                  'Never collected, on any plan',
                  style: PTText.body.copyWith(fontSize: 14, fontWeight: .w600),
                ),
              ),
            ],
          ),
          for (final line in kAnalyticsNeverCollected)
            Row(
              crossAxisAlignment: .start,
              spacing: 8,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: PTColors.online.withValues(alpha: 0.7),
                      shape: .circle,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(line, style: PTText.finePrint.copyWith(fontSize: 12, height: 1.45)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.doc});

  final AnalyticsEventDoc doc;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: PTColors.white(0.03),
        border: Border.all(color: PTColors.white(0.07)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: .start,
        spacing: 5,
        children: [
          Text(doc.what, style: PTText.body.copyWith(fontSize: 13.5, fontWeight: .w600)),
          Text(doc.why, style: PTText.finePrint.copyWith(fontSize: 12, height: 1.45)),
          if (doc.properties.isNotEmpty)
            Text(
              'Sends: ${doc.properties.join(' · ')}',
              style: PTText.finePrint.copyWith(
                fontSize: 11,
                fontFamily: PTFonts.mono,
                color: PTColors.white(0.4),
                height: 1.4,
              ),
            ),
        ],
      ),
    );
  }
}
