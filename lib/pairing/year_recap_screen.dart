import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../analytics.dart';
import '../profile/profile_service.dart';
import '../ui/booth_icons.g.dart';
import '../ui/buttons.dart';
import '../ui/loader.dart';
import '../ui/pt_theme.dart';
import 'pair_logic.dart';
import 'pair_models.dart';
import 'pair_page.dart';
import 'pair_service.dart';
import 'pair_share.dart';
import 'pair_widgets.dart';

/// "Our year": one card, stats only - no titles, no chat - sized 4:5 for a story
/// or a chat, with the wordmark on it. Safe to share by construction.
class YearRecapScreen extends StatefulWidget {
  const YearRecapScreen({super.key});

  @override
  State<YearRecapScreen> createState() => _YearRecapScreenState();
}

class _YearRecapScreenState extends State<YearRecapScreen> {
  final _boundary = GlobalKey();
  PairStats? _stats;
  int _year = DateTime.now().year;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final now = DateTime.now();
    var year = now.year;
    var stats = await PairService.instance.loadStatsForYear(year);
    // In January the new year has nothing in it yet: show the one just finished.
    final recap = recapYear(now, thisYearHasNights: stats.nights > 0);
    if (recap != year) {
      year = recap;
      stats = await PairService.instance.loadStatsForYear(year);
    }
    if (mounted) {
      setState(() {
        _stats = stats;
        _year = year;
      });
    }
  }

  Future<void> _share(BuildContext buttonContext) async {
    final render = _boundary.currentContext?.findRenderObject();
    if (render is! RenderRepaintBoundary) return;
    setState(() => _sharing = true);
    try {
      final image = await render.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null || !buttonContext.mounted) return;
      final shared = await shareBytes(
        buttonContext,
        bytes: data.buffer.asUint8List(),
        name: 'our-year-$_year.png',
        mimeType: 'image/png',
      );
      if (shared) Analytics.instance.track('pair_year_shared');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    final pair = PairService.instance.pair;
    final me = ProfileService.instance.profile;
    if (stats == null || pair == null) {
      return const PairPage(
        title: 'Our year',
        children: [
          Padding(
            padding: EdgeInsets.only(top: 80),
            child: Center(child: PTLoader()),
          ),
        ],
      );
    }
    final mine = (me?.displayName ?? 'You').split(' ').first;
    final theirs = pair.partner.displayName.split(' ').first;
    final apart = shouldShowPartnerTime(pair.partner.timezone, DateTime.now())
        ? '${cityOfZone(pair.partner.timezone)} · ${offsetLabel(offsetFromMe(pair.partner.timezone, DateTime.now())!).replaceAll(' behind', '').replaceAll(' ahead', '')} apart'
        : null;

    return PairPage(
      title: 'Our year',
      spacing: 16,
      children: [
        Center(
          child: RepaintBoundary(
            key: _boundary,
            child: _YearCard(year: _year, mine: mine, theirs: theirs, apart: apart, stats: stats),
          ),
        ),
        Builder(
          builder: (buttonContext) => PTButton(
            label: 'Share image',
            icon: BoothIcons.share,
            loading: _sharing,
            onPressed: stats.nights == 0 ? null : () => _share(buttonContext),
          ),
        ),
        PairNote(
          stats.nights == 0
              ? 'Spend a night together and this fills in.'
              : '$theirs can share their own copy. Stats only: no film titles, no chat.',
          center: true,
        ),
      ],
    );
  }
}

class _YearCard extends StatelessWidget {
  static const _w = 340.0;
  static const _h = 425.0;

  const _YearCard({
    required this.year,
    required this.mine,
    required this.theirs,
    required this.apart,
    required this.stats,
  });

  final int year;
  final String mine;
  final String theirs;
  final String? apart;
  final PairStats stats;

  @override
  Widget build(BuildContext context) {
    // The card is an image people share, so it is drawn at one fixed design size
    // with text scaling off - it must look the same for everyone who sends it,
    // however large their system text is - and scaled down to fit the screen.
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth < _w ? box.maxWidth : _w;
        return SizedBox(
          width: width,
          height: width * _h / _w,
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: _w,
              height: _h,
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
                child: Container(
                  padding: const EdgeInsets.all(26),
                  decoration: BoxDecoration(
                    color: PTColors.canvas,
                    borderRadius: BorderRadius.circular(PTRadius.panel),
                    border: Border.all(color: PTColors.rail),
                  ),
                  child: Column(
                    crossAxisAlignment: .start,
                    spacing: 14,
                    children: [
                      Text(
                        'OUR YEAR · $year',
                        style: PTText.label.copyWith(color: PTColors.primary, letterSpacing: 2),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '$mine & $theirs',
                          style: PTText.display.copyWith(fontSize: 38, height: 0.95),
                        ),
                      ),
                      if (apart != null)
                        Row(
                          spacing: 8,
                          children: [
                            const Icon(BoothIcons.globe, size: 16, color: PTColors.fgDim),
                            Expanded(
                              child: Text(
                                apart!,
                                maxLines: 1,
                                overflow: .ellipsis,
                                style: PTText.caption.copyWith(color: PTColors.fgSoft),
                              ),
                            ),
                          ],
                        ),
                      const Spacer(),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          hoursLabel(stats.hours),
                          style: PTText.display.copyWith(
                            fontSize: 84,
                            height: 0.9,
                            color: PTColors.streak,
                          ),
                        ),
                      ),
                      Text(
                        'hours watching the same screen',
                        style: PTText.body.copyWith(fontSize: 15, color: PTColors.fgDim),
                      ),
                      const Divider(height: 1, color: PTColors.rail),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (final t in [
                            '${stats.nights} NIGHTS',
                            '${stats.films} FILMS',
                            '${stats.bestStreakWeeks} WK STREAK',
                          ])
                            Text(
                              t,
                              style: PTText.mono.copyWith(fontSize: 10.5, color: PTColors.fgSoft),
                            ),
                        ],
                      ),
                      Text(
                        'sync·together',
                        style: PTText.cardHeading.copyWith(fontSize: 14, color: PTColors.fgMute),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
