import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../analytics.dart';
import '../../ui/banners.dart';
import '../../ui/buttons.dart';
import '../../ui/glass.dart';
import '../../ui/loader.dart';
import '../../ui/pt_theme.dart';
import '../../ui/scroll_fade.dart';
import '../rewards_logic.dart';
import '../rewards_models.dart';
import '../rewards_service.dart';

/// Everything this account has published, with a way to take any of it back.
///
/// A recap is a public URL that was shared with particular people. Somebody who
/// changes their mind must be able to make the link stop working now, rather
/// than waiting ninety days for the sweep - and they must be able to find the
/// list without remembering which room it came from.
Future<void> showSharedRecapsDialog(BuildContext context) {
  return showGlassDialog(
    context: context,
    width: 520,
    scrollable: false,
    padding: const EdgeInsets.fromLTRB(28, 26, 20, 22),
    builder: (context) => const _SharedRecaps(),
  );
}

class _SharedRecaps extends StatefulWidget {
  const _SharedRecaps();

  @override
  State<_SharedRecaps> createState() => _SharedRecapsState();
}

class _SharedRecapsState extends State<_SharedRecaps> {
  List<SharedRecap>? _recaps;
  final _deleting = <String>{};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final recaps = await RewardsService.instance.loadSharedRecaps();
    if (!mounted) return;
    setState(() => _recaps = recaps);
  }

  Future<void> _delete(SharedRecap recap) async {
    setState(() => _deleting.add(recap.id));
    final gone = await RewardsService.instance.deleteSharedRecap(recap.id);
    if (gone) {
      // The counter-signal to `recap_shared`, and the only one there is. A
      // share that gets taken back is not a share, and taking back the ones
      // that were actually being opened says something different again - which
      // is why the view count travels with it.
      Analytics.instance.track('recap_deleted', {'views': recap.views});
    }
    if (!mounted) return;
    setState(() {
      _deleting.remove(recap.id);
      if (gone) _recaps = [...?_recaps?.where((r) => r.id != recap.id)];
    });
    if (!gone) showPTSnack(context, "Couldn't take that one down. Try again in a bit.");
  }

  @override
  Widget build(BuildContext context) {
    final recaps = _recaps;
    // Below this height a pinned header plus a scrolling list leaves the list
    // no room at all, so the whole body scrolls as one instead.
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            recaps == null ||
            recaps.isEmpty ||
            constraints.maxHeight < MediaQuery.textScalerOf(context).scale(360);
        final list = ListView.separated(
          shrinkWrap: true,
          physics: compact ? const NeverScrollableScrollPhysics() : null,
          padding: const EdgeInsets.only(right: 16),
          itemCount: recaps?.length ?? 0,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) => _RecapRow(
            recap: recaps![i],
            busy: _deleting.contains(recaps[i].id),
            onDelete: () => unawaited(_delete(recaps[i])),
          ),
        );
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
                        Text('Shared recaps', style: PTText.screenTitle.copyWith(fontSize: 20)),
                        Text(
                          'Public pages you have made. Deleting one breaks its link '
                          'immediately, for everyone.',
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
            if (recaps == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: PTLoader(size: 26)),
              )
            else if (recaps.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 24, 16, 24),
                child: Text(
                  "You haven't shared any recaps yet. When you leave a room after a "
                  'proper session, the card you get is the thing that lands here.',
                  style: PTText.caption,
                ),
              )
            else if (compact)
              list
            else
              Flexible(child: ScrollFadeEdge(child: list)),
          ],
        );
        return compact ? SingleChildScrollView(child: body) : body;
      },
    );
  }
}

class _RecapRow extends StatelessWidget {
  const _RecapRow({required this.recap, required this.busy, required this.onDelete});

  final SharedRecap recap;
  final bool busy;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: PTColors.white(0.03),
        border: Border.all(color: PTColors.white(0.07)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        spacing: 10,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              spacing: 3,
              children: [
                Text(
                  recap.roomName ?? 'A watch party',
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: PTText.body.copyWith(fontSize: 14, fontWeight: .w600),
                ),
                Text(
                  '${formatWatchTime(recap.length)} · '
                  '${recap.people + 1} ${recap.people == 0 ? 'person' : 'people'} · '
                  '${recap.views} ${recap.views == 1 ? 'view' : 'views'}',
                  style: PTText.finePrint.copyWith(fontSize: 11.5),
                ),
              ],
            ),
          ),
          PTIconButton(
            icon: Symbols.link_rounded,
            iconSize: 17,
            size: 34,
            tooltip: 'Copy link',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: recapUrl(recap.id)));
              // The same event as the first share, on purpose: splitting it
              // would split the one funnel this feature is judged by. The
              // surface is what separates "shared on the way out" from "went
              // looking for the link again", and the second is the stronger
              // signal of the two.
              Analytics.instance.track('recap_shared', {'surface': 'manage'});
              if (context.mounted) {
                showPTSnack(context, 'Link copied.', kind: .success);
              }
            },
          ),
          PTIconButton(
            icon: busy ? Symbols.hourglass_empty_rounded : Symbols.delete_rounded,
            iconSize: 17,
            size: 34,
            tooltip: 'Delete this recap',
            onPressed: busy ? null : onDelete,
          ),
        ],
      ),
    );
  }
}
