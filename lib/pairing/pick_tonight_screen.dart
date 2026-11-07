import 'dart:async';

import 'package:flutter/material.dart';

import '../profile/profile_service.dart';
import '../ui/booth_icons.g.dart';
import '../ui/buttons.dart';
import '../ui/identity.dart';
import '../ui/loader.dart';
import '../ui/pt_theme.dart';
import 'pair_models.dart';
import 'pair_page.dart';
import 'pair_pick.dart';
import 'pair_service.dart';
import 'pair_widgets.dart';
import 'watchlist_screen.dart';

enum _Phase { swiping, waiting, matched, noMatch }

/// One card at a time, you and your person answering privately, and the screen
/// ends with a film - so choosing what to watch takes a minute, not an evening.
/// Neither of you sees the other's answers until you have both finished.
class PickTonightScreen extends StatefulWidget {
  const PickTonightScreen({super.key});

  @override
  State<PickTonightScreen> createState() => _PickTonightScreenState();
}

class _PickTonightScreenState extends State<PickTonightScreen> {
  late final List<WatchlistItem> _items;
  final _yes = <String>[];
  int _index = 0;
  _Phase _phase = _Phase.swiping;
  WatchlistItem? _picked;
  StreamSubscription<Map<String, dynamic>>? _sub;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _items = [
      for (final i in PairService.instance.watchlist)
        if (!i.watched) i,
    ];
    // The partner may finish while we are still swiping, or after we start
    // waiting: either way this is the one place their answers are folded in.
    _sub = PairService.instance.partnerPicks.listen((_) => _tryResolve());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _answer(bool yes) {
    final item = _items[_index];
    if (yes) _yes.add(item.id);
    if (_index + 1 < _items.length) {
      setState(() => _index++);
      return;
    }
    setState(() => _phase = _Phase.waiting);
    unawaited(PairService.instance.sendPicks(_yes, round: DateTime.now().millisecondsSinceEpoch));
    _tryResolve();
  }

  void _tryResolve() {
    if (!mounted || _phase != _Phase.waiting) return;
    final theirs = PairService.instance.freshPartnerPicks;
    if (theirs == null) return;
    final id = choosePick(_yes, theirs);
    setState(() {
      if (id == null) {
        _phase = _Phase.noMatch;
      } else {
        _picked = _byId(id);
        _phase = _Phase.matched;
      }
    });
  }

  WatchlistItem? _byId(String id) {
    for (final i in _items) {
      if (i.id == id) return i;
    }
    return null;
  }

  void _pickAnyway() {
    final theirs = PairService.instance.freshPartnerPicks ?? const <String>[];
    final id = choosePickFromEither(_yes, theirs);
    setState(() {
      _picked = id == null ? null : _byId(id);
      _phase = _picked == null ? _Phase.noMatch : _Phase.matched;
    });
  }

  void _restart() => setState(() {
    _yes.clear();
    _index = 0;
    _picked = null;
    _phase = _Phase.swiping;
  });

  Future<void> _start() async {
    final item = _picked;
    if (item == null) return;
    setState(() => _starting = true);
    await startInOurRoom(context, item);
    if (mounted) setState(() => _starting = false);
  }

  @override
  Widget build(BuildContext context) {
    final partner = PairService.instance.pair?.partner;
    final first = partner?.displayName.split(' ').first ?? 'your person';
    return PairPage(
      title: 'Pick tonight',
      spacing: 16,
      children: switch (_phase) {
        _Phase.swiping => _swiping(first),
        _Phase.waiting => _waiting(first),
        _Phase.matched => _matched(first),
        _Phase.noMatch => _noMatch(first),
      },
    );
  }

  List<Widget> _swiping(String first) {
    final item = _items[_index];
    final adder = item.addedBy == ProfileService.instance.profile?.id ? 'you' : first;
    return [
      Row(
        children: [
          Expanded(child: PairKicker('${_index + 1} of ${_items.length}')),
          if (PairService.instance.partnerOnline)
            Text('$first is picking too', style: PTText.caption.copyWith(color: PTColors.online)),
        ],
      ),
      PairPanel(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: .stretch,
          spacing: 14,
          children: [
            Container(
              height: 190,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: PTColors.aisle,
                borderRadius: BorderRadius.circular(PTRadius.control),
              ),
              child: Icon(
                item.source == WatchSource.youtube ? BoothIcons.youtube : BoothIcons.film,
                size: 48,
                color: PTColors.fgMute,
              ),
            ),
            Text(
              item.title,
              maxLines: 3,
              overflow: .ellipsis,
              style: PTText.cardHeading.copyWith(fontSize: 26, height: 1.05),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: .center,
              children: [
                PTAvatar(userId: item.addedBy, displayName: adder, size: 22),
                Text('Added by $adder', style: PTText.caption.copyWith(color: PTColors.fgSoft)),
                PairTag(item.source == WatchSource.youtube ? 'YouTube' : 'Local file'),
              ],
            ),
          ],
        ),
      ),
      Row(
        spacing: 12,
        children: [
          Expanded(
            child: PTButton(
              label: 'Pass',
              variant: .secondary,
              icon: BoothIcons.close,
              height: 54,
              onPressed: () => _answer(false),
            ),
          ),
          Expanded(
            child: PTButton(
              label: 'Yes',
              icon: BoothIcons.check,
              height: 54,
              onPressed: () => _answer(true),
            ),
          ),
        ],
      ),
      const PairNote(
        'Neither of you sees the other\'s answers until you both finish.',
        center: true,
      ),
    ];
  }

  List<Widget> _waiting(String first) => [
    const SizedBox(height: 40),
    const Center(child: PTLoader(size: 22)),
    Text(
      'Waiting for $first to finish…',
      textAlign: TextAlign.center,
      style: PTText.cardHeading.copyWith(fontSize: 22),
    ),
    const PairNote(
      'They will see the same cards. Your answers stay private until then.',
      center: true,
    ),
    const SizedBox(height: 8),
    PTButton(label: 'Pick without $first', variant: .secondary, onPressed: _pickAnyway),
  ];

  List<Widget> _matched(String first) {
    final item = _picked!;
    return [
      const SizedBox(height: 24),
      const PairKicker('You both said yes', color: PTColors.primary),
      Text(item.title, style: PTText.display.copyWith(fontSize: 40, height: 0.95)),
      Text("Tonight's pick", style: PTText.body.copyWith(color: PTColors.fgSoft)),
      const SizedBox(height: 8),
      PTButton(
        label: 'Start in Our Room',
        icon: BoothIcons.play,
        loading: _starting,
        onPressed: _start,
      ),
      PTButton(label: 'Spin again', variant: .secondary, onPressed: _restart),
    ];
  }

  List<Widget> _noMatch(String first) => [
    const SizedBox(height: 24),
    Text('No overlap tonight', style: PTText.display.copyWith(fontSize: 34, height: 1)),
    Text(
      "You and $first didn't both say yes to the same one. Pick from either list, or go round again.",
      style: PTText.body.copyWith(color: PTColors.fgSoft, height: 1.5),
    ),
    const SizedBox(height: 8),
    PTButton(label: 'Pick from either list', onPressed: _pickAnyway),
    PTButton(label: 'Go round again', variant: .secondary, onPressed: _restart),
  ];
}
