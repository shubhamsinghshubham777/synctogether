import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../nav.dart';
import '../profile/profile_service.dart';
import '../ui/banners.dart';
import '../ui/booth_icons.g.dart';
import '../ui/buttons.dart';
import '../ui/glass.dart';
import '../ui/identity.dart';
import '../ui/pt_motion.dart';
import '../ui/pt_theme.dart';
import 'pair_models.dart';
import 'pair_page.dart';
import 'pair_service.dart';
import 'pair_widgets.dart';

/// The two of you, one list: things to watch, things watched. Either person adds
/// a YouTube link or the name of a file; a local file says up front that the
/// other person needs the same one, instead of failing at the start.
class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key});

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  bool _watched = false;

  @override
  void initState() {
    super.initState();
    unawaited(PairService.instance.load());
  }

  Future<void> _add() async {
    await showAddToWatchlist(context);
  }

  Future<void> _menu(WatchlistItem item) async {
    await showGlassDialog<void>(
      context: context,
      width: 380,
      builder: (ctx) => Column(
        crossAxisAlignment: .stretch,
        spacing: 6,
        children: [
          Text(item.title, style: PTText.cardHeading, maxLines: 2, overflow: .ellipsis),
          const SizedBox(height: 6),
          DialogOptionRow(
            icon: item.watched ? BoothIcons.replay : BoothIcons.check,
            label: item.watched ? 'Move back to watch' : 'Mark as watched',
            onTap: () async {
              Navigator.of(ctx).pop();
              await PairService.instance.setWatched(item.id, !item.watched);
            },
          ),
          DialogOptionRow(
            icon: BoothIcons.delete,
            label: 'Remove from the list',
            onTap: () async {
              Navigator.of(ctx).pop();
              await PairService.instance.removeWatchlistItem(item.id);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PairService.instance,
      builder: (context, _) {
        final svc = PairService.instance;
        final me = ProfileService.instance.profile?.id;
        final partner = svc.pair?.partner;
        final toWatch = [
          for (final i in svc.watchlist)
            if (!i.watched) i,
        ];
        final watched = [
          for (final i in svc.watchlist)
            if (i.watched) i,
        ];
        final shown = _watched ? watched : toWatch;

        return PairPage(
          title: 'Our watchlist',
          trailing: PTIconButton(
            icon: BoothIcons.add,
            tooltip: 'Add a title',
            size: isCompactTrailing(context) ? 40 : 44,
            onPressed: _add,
          ),
          footer: toWatch.length >= 2
              ? PTButton(
                  label: 'Pick tonight',
                  icon: BoothIcons.shuffle,
                  onPressed: () => openPage(context, '/lobby/pair/pick'),
                )
              : null,
          children: [
            _Segments(
              labels: ['To watch · ${toWatch.length}', 'Watched · ${watched.length}'],
              selected: _watched ? 1 : 0,
              onSelect: (i) => setState(() => _watched = i == 1),
            ),
            if (shown.isEmpty)
              PairPanel(
                child: Column(
                  crossAxisAlignment: .start,
                  spacing: 6,
                  children: [
                    Text(
                      _watched ? 'Nothing watched yet' : 'Nothing on the list yet',
                      style: PTText.cardHeading.copyWith(fontSize: 17),
                    ),
                    Text(
                      _watched
                          ? 'Films you finish together land here.'
                          : 'Add a YouTube link or a film you both have, and it is here for both of you.',
                      style: PTText.body.copyWith(
                        color: PTColors.fgSoft,
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              )
            else
              PairPanel(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Column(
                  children: [
                    for (var i = 0; i < shown.length; i++) ...[
                      if (i > 0) const PairDivider(),
                      _ItemRow(
                        item: shown[i],
                        mine: shown[i].addedBy == me,
                        partnerName: partner?.displayName.split(' ').first ?? 'Your person',
                        adderName: shown[i].addedBy == me
                            ? (ProfileService.instance.profile?.displayName ?? 'You')
                            : partner?.displayName ?? '',
                        onMenu: () => _menu(shown[i]),
                      ),
                    ],
                  ],
                ),
              ),
            if (!_watched && toWatch.length == 1)
              const PairNote('Add one more and you can pick tonight together.', center: true),
          ],
        );
      },
    );
  }
}

/// Header buttons are 44 on desktop's marquee and 40 inside the phone header.
bool isCompactTrailing(BuildContext context) => MediaQuery.sizeOf(context).width < 720;

class _Segments extends StatelessWidget {
  const _Segments({required this.labels, required this.selected, required this.onSelect});

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: PTColors.glassBase,
        borderRadius: BorderRadius.circular(PTRadius.control),
        border: Border.all(color: PTColors.rail),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == selected,
                label: labels[i],
                child: PTPressable(
                  onTap: () => onSelect(i),
                  pressedScale: 0.98,
                  child: Container(
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == selected ? PTColors.aisle : Colors.transparent,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      labels[i],
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: PTText.body.copyWith(
                        fontSize: 14,
                        fontWeight: .w600,
                        color: i == selected ? PTColors.fg : PTColors.fgMute,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.mine,
    required this.partnerName,
    required this.adderName,
    required this.onMenu,
  });

  final WatchlistItem item;
  final bool mine;
  final String partnerName;
  final String adderName;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    // A local file only plays for both of you if you both have it (or the host
    // shares it), so the person who added it is told so right here.
    final needsCopy = mine && item.source == WatchSource.local && !item.watched;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        spacing: 12,
        children: [
          Container(
            width: 44,
            height: 60,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: PTColors.aisle,
              borderRadius: BorderRadius.circular(PTRadius.control),
            ),
            child: Icon(
              item.source == WatchSource.youtube ? BoothIcons.youtube : BoothIcons.film,
              size: 20,
              color: PTColors.fgMute,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              spacing: 6,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: .ellipsis,
                  style: PTText.body.copyWith(fontSize: 15, fontWeight: .w600, color: PTColors.fg),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: .center,
                  children: [
                    PTAvatar(userId: item.addedBy, displayName: adderName, size: 18),
                    PairTag(item.source == WatchSource.youtube ? 'YouTube' : 'Local file'),
                    if (needsCopy)
                      Text(
                        '${partnerName.toUpperCase()} NEEDS THE SAME FILE',
                        style: PTText.mono.copyWith(fontSize: 10, color: PTColors.warning),
                      ),
                  ],
                ),
              ],
            ),
          ),
          PTIconButton(
            icon: BoothIcons.moreHoriz,
            glass: false,
            size: 40,
            iconSize: 20,
            tooltip: 'More',
            onPressed: onMenu,
          ),
        ],
      ),
    );
  }
}

/// A dialog that adds one title: a name, and either a YouTube link or "a file we
/// both have". Returns whether something was added.
Future<bool> showAddToWatchlist(BuildContext context) async {
  final title = TextEditingController();
  final url = TextEditingController();
  var source = WatchSource.local;
  var busy = false;
  String? problem;
  final added = await showGlassDialog<bool>(
    context: context,
    width: 420,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        Future<void> submit() async {
          setState(() {
            busy = true;
            problem = null;
          });
          try {
            await PairService.instance.addWatchlistItem(
              title: title.text,
              source: source,
              url: source == WatchSource.youtube ? url.text.trim() : null,
            );
            if (ctx.mounted) Navigator.of(ctx).pop(true);
          } catch (e) {
            setState(() {
              busy = false;
              problem = PairErrorCode.fromError(e).message;
            });
          }
        }

        return Column(
          crossAxisAlignment: .stretch,
          spacing: 14,
          children: [
            Text('Add to the list', style: PTText.screenTitle.copyWith(fontSize: 24)),
            _Segments(
              labels: const ['A file we have', 'YouTube link'],
              selected: source == WatchSource.local ? 0 : 1,
              onSelect: (i) =>
                  setState(() => source = i == 0 ? WatchSource.local : WatchSource.youtube),
            ),
            TextField(
              controller: title,
              autofocus: true,
              maxLength: 120,
              textCapitalization: TextCapitalization.sentences,
              style: PTText.body,
              decoration: const InputDecoration(hintText: 'What is it called?'),
            ),
            if (source == WatchSource.youtube)
              TextField(
                controller: url,
                keyboardType: TextInputType.url,
                style: PTText.body,
                decoration: const InputDecoration(hintText: 'Paste the YouTube link'),
              )
            else
              const PairNote(
                'For a file, both of you need the same one - or whoever hosts shares it in the room.',
              ),
            if (problem != null)
              Text(problem!, style: PTText.body.copyWith(color: PTColors.danger, fontSize: 14)),
            Row(
              spacing: 10,
              children: [
                Expanded(
                  child: PTButton(
                    label: 'Cancel',
                    variant: .secondary,
                    height: 44,
                    onPressed: () => Navigator.of(ctx).pop(false),
                  ),
                ),
                Expanded(
                  child: PTButton(label: 'Add', height: 44, loading: busy, onPressed: submit),
                ),
              ],
            ),
          ],
        );
      },
    ),
  );
  title.dispose();
  url.dispose();
  return added ?? false;
}

/// Starts [item] in Our Room: open the room, and when it is a YouTube link and
/// the caller can set media (both partners are hosts there), load it. A local
/// file cannot be loaded for you - paths never leave a device - so the room just
/// opens and its source picker is one tap away.
Future<void> startInOurRoom(BuildContext context, WatchlistItem item) async {
  final router = GoRouter.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final room = await PairService.instance.openOurRoom();
    if (item.source == WatchSource.youtube && item.sourceUrl != null) {
      await PairService.instance.setOurRoomYouTube(room.id, item.sourceUrl!);
    } else {
      showPTSnackVia(messenger, 'Pick "${item.title}" from the source picker.', kind: .info);
    }
    router.go('/lobby/room/${room.id}');
  } catch (e) {
    showPTSnackVia(messenger, PairErrorCode.fromError(e).message, kind: .error);
  }
}
